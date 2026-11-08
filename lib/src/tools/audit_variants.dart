import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../common/context.dart';
import '../common/project.dart';

final ToolSpec auditVariantsSpec = ToolSpec(
  Tool(
    name: 'assetgenie_audit_variants',
    title: 'Audit image resolution variants (2.0x/3.0x) and vector graphics',
    description:
        'Audits Flutter asset folders for missing high-DPI resolution variants '
        '(2.0x, 3.0x), orphaned variant files without base assets, and checks '
        'whether SVGs are precompiled with vector_graphics asset transformers.',
    annotations: ToolAnnotations(
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'base_images_count': IntegerSchema(),
        'missing_variants': ObjectSchema(
          description: 'Base image mapped to missing variant scales.',
        ),
        'orphaned_variants': ListSchema(items: StringSchema()),
        'uncompiled_svgs': ListSchema(items: StringSchema()),
      },
      required: [
        'base_images_count',
        'missing_variants',
        'orphaned_variants',
        'uncompiled_svgs',
      ],
    ),
  ),
  auditVariantsHandler,
);

Future<CallToolResult> auditVariantsHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final bundledFiles = project.bundledAssetFiles();
  final missingVariants = <String, List<String>>{};
  final orphanedVariants = <String>[];
  final uncompiledSvgs = <String>[];

  // 1. Check SVGs for vector_graphics compilation
  final hasVectorGraphics = project.hasDependency('vector_graphics');
  for (final file in bundledFiles) {
    if (p.extension(file.path).toLowerCase() == '.svg') {
      final rel = project.rel(file.path);
      final dir = '${p.dirname(rel).replaceAll('\\', '/')}/';
      final hasTransformer = project.assetTransformers.containsKey(dir) ||
          project.assetTransformers.containsKey(rel);
      if (!hasTransformer || !hasVectorGraphics) {
        uncompiledSvgs.add(rel);
      }
    }
  }

  // 2. Map resolution variants: scan directories
  final rasterImages = bundledFiles.where((f) {
    final ext = p.extension(f.path).toLowerCase();
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp';
  }).toList();

  for (final file in rasterImages) {
    final parentDir = file.parent;
    final parentName = p.basename(parentDir.path);

    // Is this file inside a variant directory like 2.0x, 3.0x?
    if (variantDirPattern.hasMatch(parentName)) {
      final baseDir = parentDir.parent;
      final baseFile = File(p.join(baseDir.path, p.basename(file.path)));
      if (!baseFile.existsSync()) {
        orphanedVariants.add(project.rel(file.path));
      }
    } else {
      // It's a base image. Check if 2.0x and 3.0x subfolders exist
      final missing = <String>[];
      for (final scale in ['2.0x', '3.0x']) {
        final variantFile = File(p.join(parentDir.path, scale, p.basename(file.path)));
        if (!variantFile.existsSync()) {
          missing.add(scale);
        }
      }
      if (missing.isNotEmpty) {
        missingVariants[project.rel(file.path)] = missing;
      }
    }
  }

  final report = StringBuffer()
    ..writeln('# AssetGenie Image Variants & Vector Graphics Audit')
    ..writeln('Project: `${project.name}`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Base raster images analyzed: ${rasterImages.length}')
    ..writeln('- Images missing 2.0x or 3.0x variants: ${missingVariants.length}')
    ..writeln('- Orphaned variant files: ${orphanedVariants.length}')
    ..writeln('- SVGs not using vector_graphics compiler: ${uncompiledSvgs.length}')
    ..writeln();

  if (missingVariants.isNotEmpty) {
    report.writeln('### ⚠️ Missing High-DPI Resolution Variants (2.0x, 3.0x)');
    missingVariants.forEach((basePath, scales) {
      report.writeln('- `$basePath` (missing ${scales.map((s) => '`$s`').join(', ')})');
    });
    report.writeln();
  } else {
    report.writeln('### ✅ All base images have full 2.0x and 3.0x variant coverage.\n');
  }

  if (orphanedVariants.isNotEmpty) {
    report.writeln('### ⚠️ Orphaned Variant Files (Variant exists but base asset missing)');
    for (final orphan in orphanedVariants) {
      report.writeln('- `$orphan`');
    }
    report.writeln();
  }

  if (uncompiledSvgs.isNotEmpty) {
    report.writeln('### 💡 Vector Graphics Optimization Recommendation');
    report.writeln(
      'The following SVG assets are not configured with Flutter asset transformers '
      '(`vector_graphics_compiler`). Adding them improves app launch performance and eliminates runtime SVG parsing jank:\n',
    );
    for (final svg in uncompiledSvgs) {
      report.writeln('- `$svg`');
    }
    report.writeln();
  }

  final structured = <String, Object?>{
    'base_images_count': rasterImages.length,
    'missing_variants': missingVariants,
    'orphaned_variants': orphanedVariants,
    'uncompiled_svgs': uncompiledSvgs,
  };

  return toolOk(report.toString(), structured);
}

