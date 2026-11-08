import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../common/context.dart';
import '../common/project.dart';

final ToolSpec generateConstantsSpec = ToolSpec(
  Tool(
    name: 'assetgenie_generate_constants',
    title: 'Generate Dart asset and font constants',
    description:
        'Scans physical asset directories and declared fonts in pubspec.yaml '
        'to auto-generate clean, type-safe Dart constants inside lib/generated/. '
        'Resolves collisions, formats identifiers in camelCase, and handles reserved keywords.',
    annotations: ToolAnnotations(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
        'output_filename': StringSchema(
          description:
              "Target filename for the generated class (default: 'generated_assets.dart').",
        ),
        'class_name': StringSchema(
          description:
              "Name of the generated class (default: 'Assets').",
        ),
        'dry_run': BooleanSchema(
          description:
              'If true, previews the generated constants without writing to disk.',
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'output_file': StringSchema(),
        'asset_count': IntegerSchema(),
        'font_family_count': IntegerSchema(),
        'dry_run': BooleanSchema(),
        'constants': ObjectSchema(
          description: 'Identifier mapped to asset path.',
        ),
      },
      required: [
        'output_file',
        'asset_count',
        'font_family_count',
        'dry_run',
        'constants',
      ],
    ),
  ),
  generateConstantsHandler,
);

Future<CallToolResult> generateConstantsHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final outputFilename =
      args['output_filename'] as String? ?? 'generated_assets.dart';
  final className = args['class_name'] as String? ?? 'Assets';
  final dryRun = argBool(args, 'dry_run', false);

  // 1. Gather all assets directories
  final assetsDirs = <Directory>[];
  final mainAssetsDir = Directory(p.join(project.root, 'assets'));
  if (mainAssetsDir.existsSync()) {
    assetsDirs.add(mainAssetsDir);
  }

  for (final dirAsset in project.declaredAssetDirs) {
    final customDir = Directory(project.abs(dirAsset));
    if (customDir.existsSync() &&
        !assetsDirs.any((d) => p.normalize(d.path) == p.normalize(customDir.path))) {
      assetsDirs.add(customDir);
    }
  }

  // 2. Scan for physical asset files
  final assetFiles = <File>[];
  final excludedExtensions = {
    '.dart',
    '.arb',
    '.yaml',
    '.lock',
    '.gitkeep',
    '.ds_store',
  };

  for (final dir in assetsDirs) {
    try {
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          final basename = p.basename(entity.path).toLowerCase();
          if (!excludedExtensions.contains(ext) &&
              basename != '.ds_store' &&
              basename != 'thumbs.db') {
            assetFiles.add(entity);
          }
        }
      }
    } catch (_) {}
  }

  // Also include singly-declared files
  for (final singleAsset in project.declaredAssetFiles) {
    final file = File(project.abs(singleAsset));
    if (file.existsSync()) {
      assetFiles.add(file);
    }
  }

  // Deduplicate files by normalized path
  final uniqueFiles = <File>[];
  final seenFilePaths = <String>{};
  for (final file in assetFiles) {
    final normalized = p.normalize(file.path);
    if (seenFilePaths.add(normalized)) {
      uniqueFiles.add(file);
    }
  }

  uniqueFiles.sort((a, b) => a.path.compareTo(b.path));

  // 3. Generate camelCase identifiers & resolve collisions
  final constants = <String, String>{};
  final reservedWords = {
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
    'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
    'factory', 'false', 'final', 'finally', 'for', 'Function', 'get', 'hide',
    'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
    'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
    'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
    'throw', 'true', 'try', 'typedef', 'var', 'void', 'when', 'while', 'with',
    'yield'
  };

  String toCamelCase(String text) {
    final sanitized = text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ').trim();
    if (sanitized.isEmpty) return 'asset';

    final words = sanitized.split(RegExp(r'\s+'));
    final buffer = StringBuffer(words[0].toLowerCase());
    for (var i = 1; i < words.length; i++) {
      final word = words[i];
      if (word.isNotEmpty) {
        buffer.write(word[0].toUpperCase() + word.substring(1).toLowerCase());
      }
    }

    var result = buffer.toString();
    if (RegExp(r'^[0-9]').hasMatch(result)) {
      result = 'val$result';
    }
    if (reservedWords.contains(result)) {
      result = 'asset${result[0].toUpperCase()}${result.substring(1)}';
    }
    return result;
  }

  for (final file in uniqueFiles) {
    final relativePath = project.rel(file.path);
    final nameWithoutExt = p.basenameWithoutExtension(file.path);

    var identifier = toCamelCase(nameWithoutExt);

    if (constants.containsKey(identifier)) {
      final parentDir = p.basename(p.dirname(file.path));
      identifier = toCamelCase('${parentDir}_$nameWithoutExt');

      if (constants.containsKey(identifier)) {
        var counter = 2;
        while (constants.containsKey('$identifier$counter')) {
          counter++;
        }
        identifier = '$identifier$counter';
      }
    }

    constants[identifier] = relativePath;
  }

  // 4. Construct Dart class
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// Generated by AssetGenie')
    ..writeln()
    ..writeln('class $className {')
    ..writeln('  $className._();')
    ..writeln();

  final sortedIdentifiers = constants.keys.toList()..sort();
  for (final id in sortedIdentifiers) {
    final path = constants[id];
    buffer.writeln("  static const String $id = '$path';");
  }

  // Also include fonts if declared in pubspec.yaml
  if (project.fonts.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('  // Font Families');
    for (final font in project.fonts) {
      final fontId = toCamelCase('${font.family}_font');
      buffer.writeln("  static const String $fontId = '${font.family}';");
    }
  }

  buffer.writeln('}');

  final outputDir = Directory(p.join(project.root, 'lib', 'generated'));
  final outputFile = File(p.join(outputDir.path, outputFilename));
  final relOutputPath = project.rel(outputFile.path);

  if (!dryRun) {
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }
    await outputFile.writeAsString(buffer.toString());
  }

  final report = StringBuffer()
    ..writeln('# AssetGenie Constants Generator Report')
    ..writeln('Project: `${project.name}`')
    ..writeln('Target Output: `$relOutputPath`')
    ..writeln('Class Name: `$className`')
    ..writeln('Mode: ${dryRun ? '`dry_run` (preview only)' : 'Generated and written'}')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Asset constants generated: ${constants.length}')
    ..writeln('- Font family constants: ${project.fonts.length}')
    ..writeln();

  if (constants.isNotEmpty) {
    report.writeln('### Sample Generated Constants');
    final previewKeys = sortedIdentifiers.take(10);
    for (final k in previewKeys) {
      report.writeln('- `$className.$k` -> `${constants[k]}`');
    }
    if (sortedIdentifiers.length > 10) {
      report.writeln('- ... and ${sortedIdentifiers.length - 10} more.');
    }
  }

  final structured = <String, Object?>{
    'output_file': relOutputPath,
    'asset_count': constants.length,
    'font_family_count': project.fonts.length,
    'dry_run': dryRun,
    'constants': constants,
  };

  return toolOk(report.toString(), structured);
}
