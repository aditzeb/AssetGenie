import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../common/context.dart';
import '../common/project.dart';

final ToolSpec auditHealthSpec = ToolSpec(
  Tool(
    name: 'assetgenie_audit_health',
    title: 'Audit project asset health',
    description:
        "Scans the target Flutter project's pubspec.yaml and physical assets "
        'directories to identify unused images, missing file references, '
        'undeclared files, or excessively large files.',
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
        'max_size_kb': NumberSchema(
          description:
              'File size threshold in KB to flag heavy assets (default: 500).',
          minimum: 0,
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'declared_files': IntegerSchema(),
        'declared_folders': IntegerSchema(),
        'physical_files_count': IntegerSchema(),
        'missing_references': ListSchema(items: StringSchema()),
        'missing_directories': ListSchema(items: StringSchema()),
        'heavy_assets': ObjectSchema(
          description: 'Asset path mapped to size in KB.',
        ),
        'unused_assets': ListSchema(items: StringSchema()),
        'undeclared_assets': ListSchema(items: StringSchema()),
      },
      required: [
        'declared_files',
        'declared_folders',
        'physical_files_count',
        'missing_references',
        'missing_directories',
        'heavy_assets',
        'unused_assets',
        'undeclared_assets',
      ],
    ),
  ),
  auditHealthHandler,
);

Future<CallToolResult> auditHealthHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final maxSizeKb = (args['max_size_kb'] as num?)?.toDouble() ?? 500.0;

  // 1. Missing declared single files and directories.
  final missingReferences = <String>[];
  final declaredFiles = <File>[];
  for (final asset in project.declaredAssetFiles) {
    final file = File(project.abs(asset));
    if (!file.existsSync()) {
      missingReferences.add(asset);
    } else {
      declaredFiles.add(file);
    }
  }

  final missingDirectories = <String>[];
  for (final dir in project.declaredAssetDirs) {
    final directory = Directory(project.abs(dir));
    if (!directory.existsSync()) {
      missingDirectories.add(dir);
    }
  }

  // 2. Physical files gathered from declared files and folders.
  final physicalFiles = project.bundledAssetFiles();

  // 3. Undeclared assets: files in assets/ not covered by any declaration.
  final assetsFolder = Directory(p.join(project.root, 'assets'));
  final undeclaredFiles = <String>[];
  if (assetsFolder.existsSync()) {
    try {
      for (final e in assetsFolder.listSync(recursive: true)) {
        if (e is! File) continue;
        final relPath = project.rel(e.path);
        final base = p.basename(relPath).toLowerCase();
        if (base == '.ds_store' || base == 'thumbs.db') continue;

        bool isDeclared = project.declaredAssetFiles
            .any((a) => p.normalize(a) == p.normalize(relPath));
        if (!isDeclared) {
          isDeclared = project.declaredAssetDirs.any((d) {
            final fileDir = p.dirname(relPath).replaceAll('\\', '/');
            final clean = d.endsWith('/') ? d.substring(0, d.length - 1) : d;
            return fileDir == clean;
          });
        }
        if (!isDeclared) {
          undeclaredFiles.add(relPath);
        }
      }
    } catch (_) {}
    undeclaredFiles.sort();
  }

  // 4. Heavy assets.
  final heavyAssets = <String, double>{};
  for (final file in physicalFiles) {
    final bytes = file.lengthSync();
    final sizeKb = bytes / 1024.0;
    if (sizeKb > maxSizeKb) {
      heavyAssets[project.rel(file.path)] = roundTo(sizeKb);
    }
  }

  // 5. Unused assets in lib/
  final unusedAssets = <String>[];
  if (physicalFiles.isNotEmpty) {
    final dartSources = project.readDartSources().values.toList();
    for (final file in physicalFiles) {
      final relPath = project.rel(file.path);
      final filename = p.basename(file.path);
      final isUsed = dartSources.any(
        (src) => src.contains(relPath) || src.contains(filename),
      );
      if (!isUsed) unusedAssets.add(relPath);
    }
    unusedAssets.sort();
  }

  final totalMissing = missingReferences.length + missingDirectories.length;

  final buf = StringBuffer()
    ..writeln('# AssetGenie Health Audit Report')
    ..writeln('Project Path: `${project.root}`')
    ..writeln('Threshold Size: `${maxSizeKb.toStringAsFixed(1)} KB`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Total declared files: ${project.declaredAssetFiles.length}')
    ..writeln('- Total declared folders: ${project.declaredAssetDirs.length}')
    ..writeln('- Total physical files found: ${physicalFiles.length}')
    ..writeln('- Missing references: $totalMissing')
    ..writeln('- Heavy assets flagged: ${heavyAssets.length}')
    ..writeln('- Unused physical assets: ${unusedAssets.length}')
    ..writeln();

  if (totalMissing > 0) {
    buf.writeln('## ❌ Missing Asset References (Declared but not found)');
    for (final ref in missingReferences) {
      buf.writeln('- File missing: `$ref`');
    }
    for (final dir in missingDirectories) {
      buf.writeln('- Directory missing: `$dir`');
    }
    buf.writeln();
  } else {
    buf
      ..writeln('## ✅ Asset References')
      ..writeln('All declared assets are physically present.')
      ..writeln();
  }

  if (heavyAssets.isNotEmpty) {
    buf.writeln(
        '## ⚠️ Heavy Assets (Exceeds ${maxSizeKb.toStringAsFixed(1)} KB)');
    heavyAssets.forEach((path, size) {
      buf.writeln('- `$path` - **${size.toStringAsFixed(1)} KB**');
    });
    buf.writeln();
  } else {
    buf
      ..writeln('## ✅ Heavy Assets')
      ..writeln('No assets exceed the size threshold.')
      ..writeln();
  }

  if (unusedAssets.isNotEmpty) {
    buf.writeln('## 🔍 Unused Assets (Not referenced in lib/ files)');
    for (final asset in unusedAssets) {
      buf.writeln('- `$asset`');
    }
    buf.writeln();
  } else {
    buf
      ..writeln('## ✅ Unused Assets')
      ..writeln('All physical assets are referenced in code.')
      ..writeln();
  }

  if (undeclaredFiles.isNotEmpty) {
    buf.writeln(
        '## 📦 Undeclared Assets (Physical files in assets/ not declared in pubspec.yaml)');
    for (final file in undeclaredFiles) {
      buf.writeln('- `$file`');
    }
    buf.writeln();
  }

  final structured = <String, Object?>{
    'declared_files': project.declaredAssetFiles.length,
    'declared_folders': project.declaredAssetDirs.length,
    'physical_files_count': physicalFiles.length,
    'missing_references': missingReferences,
    'missing_directories': missingDirectories,
    'heavy_assets': heavyAssets,
    'unused_assets': unusedAssets,
    'undeclared_assets': undeclaredFiles,
  };

  return toolOk(buf.toString(), structured);
}
