import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mcp_server/mcp_server.dart';

Future<CallToolResult> generateConstants(Map<String, dynamic> arguments) async {
  final projectPath = arguments['project_path'] as String?;
  if (projectPath == null || projectPath.isEmpty) {
    return CallToolResult(
      [
        TextContent(
            text: 'Error: "project_path" is required and cannot be empty.')
      ],
      isError: true,
    );
  }

  final outputFilename =
      arguments['output_filename'] as String? ?? 'generated_assets.dart';

  try {
    final projectDir = Directory(projectPath);
    if (!projectDir.existsSync()) {
      return CallToolResult(
        [
          TextContent(
              text:
                  'Error: Project directory does not exist at "$projectPath".')
        ],
        isError: true,
      );
    }

    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return CallToolResult(
        [
          TextContent(
              text:
                  'Error: No "pubspec.yaml" found at "$projectPath". This does not appear to be a Flutter project.')
        ],
        isError: true,
      );
    }

    // 1. Gather all assets directories
    final assetsDirs = <Directory>[];

    // Check main assets directory first
    final mainAssetsDir = Directory(p.join(projectPath, 'assets'));
    if (mainAssetsDir.existsSync()) {
      assetsDirs.add(mainAssetsDir);
    }

    // Also scan pubspec.yaml to find other declared directories
    try {
      final pubspecContent = await pubspecFile.readAsString();
      // Simple regex/parsing of assets block
      final lines = pubspecContent.split('\n');
      bool inAssets = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed == 'assets:') {
          inAssets = true;
          continue;
        }
        if (inAssets) {
          // If indentation drops back, we left assets block
          if (line.isNotEmpty &&
              !line.startsWith(' ') &&
              !line.startsWith('-')) {
            inAssets = false;
            continue;
          }
          if (trimmed.startsWith('-')) {
            final pathEntry = trimmed.substring(1).trim();
            if (pathEntry.endsWith('/')) {
              final customDir = Directory(p.join(projectPath, pathEntry));
              if (customDir.existsSync() &&
                  !assetsDirs.any((d) =>
                      p.normalize(d.path) == p.normalize(customDir.path))) {
                assetsDirs.add(customDir);
              }
            }
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors
    }

    if (assetsDirs.isEmpty) {
      return CallToolResult([
        TextContent(
            text:
                'Warning: No physical "assets" folder or declared asset directories found in the project.\n'
                'No constants were generated.')
      ]);
    }

    // 2. Scan for physical asset files
    final assetFiles = <File>[];
    final excludedExtensions = {
      '.dart',
      '.arb',
      '.yaml',
      '.lock',
      '.gitkeep',
      '.ds_store'
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
      } catch (e) {
        // Continue
      }
    }

    // Deduplicate files by absolute path
    final uniqueFiles = <File>[];
    final seenFilePaths = <String>{};
    for (final file in assetFiles) {
      final normalized = p.normalize(file.path);
      if (!seenFilePaths.contains(normalized)) {
        seenFilePaths.add(normalized);
        uniqueFiles.add(file);
      }
    }

    if (uniqueFiles.isEmpty) {
      return CallToolResult([
        TextContent(
            text:
                'Warning: No asset files were found in the scanned directories. No constants generated.')
      ]);
    }

    // Sort files by path for deterministic output
    uniqueFiles.sort((a, b) => a.path.compareTo(b.path));

    // 3. Generate camelCase identifiers & resolve collisions
    final constants = <String, String>{}; // identifier -> relativePath
    final reservedWords = {
      'abstract',
      'as',
      'assert',
      'async',
      'await',
      'break',
      'case',
      'catch',
      'class',
      'const',
      'continue',
      'covariant',
      'default',
      'deferred',
      'do',
      'dynamic',
      'else',
      'enum',
      'export',
      'extends',
      'extension',
      'external',
      'factory',
      'false',
      'final',
      'finally',
      'for',
      'Function',
      'get',
      'hide',
      'if',
      'implements',
      'import',
      'in',
      'interface',
      'is',
      'late',
      'library',
      'mixin',
      'new',
      'null',
      'on',
      'operator',
      'part',
      'required',
      'rethrow',
      'return',
      'set',
      'show',
      'static',
      'super',
      'switch',
      'sync',
      'this',
      'throw',
      'true',
      'try',
      'typedef',
      'var',
      'void',
      'when',
      'while',
      'with',
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
      final relativePath =
          p.relative(file.path, from: projectPath).replaceAll('\\', '/');
      final nameWithoutExt = p.basenameWithoutExtension(file.path);

      var identifier = toCamelCase(nameWithoutExt);

      // Resolve collisions
      if (constants.containsKey(identifier)) {
        // Try prepending the parent directory name
        final parentDir = p.basename(p.dirname(file.path));
        identifier = toCamelCase('${parentDir}_$nameWithoutExt');

        // If still colliding, append a counter
        if (constants.containsKey(identifier)) {
          var counter = 2;
          while (constants.containsKey('${identifier}$counter')) {
            counter++;
          }
          identifier = '${identifier}$counter';
        }
      }

      constants[identifier] = relativePath;
    }

    // 4. Construct Dart class
    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln();
    buffer.writeln('class Assets {');
    buffer.writeln('  Assets._();');
    buffer.writeln();

    // Sort constants alphabetically by identifier
    final sortedIdentifiers = constants.keys.toList()..sort();
    for (final id in sortedIdentifiers) {
      final path = constants[id];
      buffer.writeln("  static const String $id = '$path';");
    }

    buffer.writeln('}');

    // 5. Write to target file inside lib/generated/
    final outputDir = Directory(p.join(projectPath, 'lib', 'generated'));
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final outputFile = File(p.join(outputDir.path, outputFilename));
    await outputFile.writeAsString(buffer.toString());

    final relativeOutputPath =
        p.relative(outputFile.path, from: projectPath).replaceAll('\\', '/');

    return CallToolResult([
      TextContent(
          text:
              'Success: Generated asset constants class `Assets` inside `$relativeOutputPath`.\n'
              'Added ${constants.length} string constants representing physical assets.')
    ]);
  } catch (e) {
    return CallToolResult(
      [TextContent(text: 'Error generating constants: ${e.toString()}')],
      isError: true,
    );
  }
}
