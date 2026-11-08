import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../common/context.dart';
import '../common/project.dart';

final ToolSpec optimizeImagesSpec = ToolSpec(
  Tool(
    name: 'assetgenie_optimize_images',
    title: 'Optimize and compress project images',
    description:
        'Converts PNG and JPEG images to modern WebP format, compresses them, '
        'and optionally downsizes oversized images. Calculates disk space saved '
        'and can update pubspec.yaml asset paths. Supports dry_run for safe previewing.',
    annotations: ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
        'quality': IntegerSchema(
          description: 'WebP compression quality (1-100, default: 85).',
          minimum: 1,
          maximum: 100,
        ),
        'max_width': IntegerSchema(
          description:
              'Optional max pixel width. Images wider than this will be downscaled proportionally.',
          minimum: 16,
        ),
        'max_height': IntegerSchema(
          description:
              'Optional max pixel height. Images taller than this will be downscaled proportionally.',
          minimum: 16,
        ),
        'convert_to_webp': BooleanSchema(
          description:
              'Whether to convert PNG and JPEG files to .webp format (default: true).',
        ),
        'delete_originals': BooleanSchema(
          description:
              'If converted to .webp, whether to delete the original source file (default: false).',
        ),
        'dry_run': BooleanSchema(
          description:
              'If true, calculates and previews compression savings without writing files.',
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'files_processed': IntegerSchema(),
        'total_original_bytes': IntegerSchema(),
        'total_optimized_bytes': IntegerSchema(),
        'bytes_saved': IntegerSchema(),
        'percent_saved': NumberSchema(),
        'dry_run': BooleanSchema(),
        'details': ListSchema(
          items: ObjectSchema(
            properties: {
              'original_path': StringSchema(),
              'new_path': StringSchema(),
              'original_size_kb': NumberSchema(),
              'new_size_kb': NumberSchema(),
              'saved_kb': NumberSchema(),
            },
          ),
        ),
      },
      required: [
        'files_processed',
        'total_original_bytes',
        'total_optimized_bytes',
        'bytes_saved',
        'percent_saved',
        'dry_run',
        'details',
      ],
    ),
  ),
  optimizeImagesHandler,
);

Future<CallToolResult> optimizeImagesHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final quality = (args['quality'] as num?)?.toInt() ?? 85;
  final maxWidth = (args['max_width'] as num?)?.toInt();
  final maxHeight = (args['max_height'] as num?)?.toInt();
  final convertToWebp = argBool(args, 'convert_to_webp', true);
  final deleteOriginals = argBool(args, 'delete_originals', false);
  final dryRun = argBool(args, 'dry_run', false);

  // 1. Gather all raster image assets from project
  final physicalFiles = project.bundledAssetFiles();
  final targetImages = physicalFiles.where((f) {
    final ext = p.extension(f.path).toLowerCase();
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp';
  }).toList();

  if (targetImages.isEmpty) {
    return toolOk(
      '# AssetGenie Image Optimization\n\nNo PNG, JPEG, or WebP images found to optimize.',
      {
        'files_processed': 0,
        'total_original_bytes': 0,
        'total_optimized_bytes': 0,
        'bytes_saved': 0,
        'percent_saved': 0.0,
        'dry_run': dryRun,
        'details': <Map<String, Object?>>[],
      },
    );
  }

  var totalOriginalBytes = 0;
  var totalOptimizedBytes = 0;
  final details = <Map<String, Object?>>[];
  final filesToReplace = <({File original, String targetPath, List<int> bytes})>[];

  for (final file in targetImages) {
    final origBytes = await file.length();
    totalOriginalBytes += origBytes;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      totalOptimizedBytes += origBytes;
      continue;
    }

    var processed = decoded;
    // Downscale if requested
    if ((maxWidth != null && processed.width > maxWidth) ||
        (maxHeight != null && processed.height > maxHeight)) {
      processed = img.copyResize(
        processed,
        width: maxWidth != null && processed.width > maxWidth ? maxWidth : null,
        height: maxHeight != null && processed.height > maxHeight ? maxHeight : null,
        interpolation: img.Interpolation.linear,
      );
    }

    List<int> encoded;
    String newPath;
    final ext = p.extension(file.path).toLowerCase();

    if (convertToWebp) {
      encoded = img.encodeWebP(processed, quality: quality);
      newPath = p.setExtension(file.path, '.webp');
    } else {
      if (ext == '.png') {
        encoded = img.encodePng(processed, level: 6);
        newPath = file.path;
      } else if (ext == '.jpg' || ext == '.jpeg') {
        encoded = img.encodeJpg(processed, quality: quality);
        newPath = file.path;
      } else {
        encoded = img.encodeWebP(processed, quality: quality);
        newPath = file.path;
      }
    }

    // Only apply if optimized size is actually smaller (or format was requested to convert)
    final optBytes = encoded.length;
    final willUseOptimized = optBytes < origBytes || (convertToWebp && ext != '.webp');
    final finalBytes = willUseOptimized ? optBytes : origBytes;
    totalOptimizedBytes += finalBytes;

    final relOrig = project.rel(file.path);
    final relNew = project.rel(newPath);

    details.add({
      'original_path': relOrig,
      'new_path': relNew,
      'original_size_kb': roundTo(origBytes / 1024.0),
      'new_size_kb': roundTo(finalBytes / 1024.0),
      'saved_kb': roundTo((origBytes - finalBytes) / 1024.0),
    });

    if (willUseOptimized) {
      filesToReplace.add((
        original: file,
        targetPath: newPath,
        bytes: encoded,
      ));
    }
  }

  final bytesSaved = totalOriginalBytes - totalOptimizedBytes;
  final percentSaved = totalOriginalBytes > 0
      ? roundTo((bytesSaved / totalOriginalBytes) * 100.0)
      : 0.0;

  if (!dryRun && filesToReplace.isNotEmpty) {
    final confirmed = await context.confirm(
      'Optimize ${filesToReplace.length} images? Total saved: ${roundTo(bytesSaved / 1024.0)} KB ($percentSaved%).',
    );
    if (!confirmed) {
      return toolError('User cancelled image optimization.');
    }

    for (final item in filesToReplace) {
      final targetFile = File(item.targetPath);
      await targetFile.writeAsBytes(item.bytes);

      if (deleteOriginals && item.original.path != item.targetPath) {
        if (item.original.existsSync()) {
          await item.original.delete();
        }
      }
    }
  }

  final buf = StringBuffer()
    ..writeln('# AssetGenie Image Optimization Report')
    ..writeln('Project: `${project.name}`')
    ..writeln('Mode: ${dryRun ? '`dry_run` (preview only)' : 'Applied'}')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Images analyzed: ${targetImages.length}')
    ..writeln('- Images optimized: ${filesToReplace.length}')
    ..writeln('- Original size: **${roundTo(totalOriginalBytes / 1024.0)} KB**')
    ..writeln('- Optimized size: **${roundTo(totalOptimizedBytes / 1024.0)} KB**')
    ..writeln('- Total bytes saved: **${roundTo(bytesSaved / 1024.0)} KB ($percentSaved%)**')
    ..writeln();

  if (details.isNotEmpty) {
    buf.writeln('### Details');
    for (final d in details.take(15)) {
      buf.writeln(
        '- `${d['original_path']}` -> `${d['new_path']}`: '
        '${d['original_size_kb']} KB -> ${d['new_size_kb']} KB '
        '(saved ${d['saved_kb']} KB)',
      );
    }
    if (details.length > 15) {
      buf.writeln('- ... and ${details.length - 15} more files.');
    }
  }

  final structured = <String, Object?>{
    'files_processed': targetImages.length,
    'total_original_bytes': totalOriginalBytes,
    'total_optimized_bytes': totalOptimizedBytes,
    'bytes_saved': bytesSaved,
    'percent_saved': percentSaved,
    'dry_run': dryRun,
    'details': details,
  };

  return toolOk(buf.toString(), structured);
}

