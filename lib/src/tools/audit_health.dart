import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:mcp_server/mcp_server.dart';

Future<CallToolResult> auditHealth(Map<String, dynamic> arguments) async {
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

  final maxSizeKb = (arguments['max_size_kb'] as num?)?.toDouble() ?? 500.0;

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

    // 1. Read pubspec.yaml asset declarations
    final pubspecContent = await pubspecFile.readAsString();
    final yaml = loadYaml(pubspecContent);

    final declaredAssets = <String>[];
    final declaredDirectories = <String>[];

    if (yaml is YamlMap && yaml['flutter'] is YamlMap) {
      final flutterMap = yaml['flutter'] as YamlMap;
      if (flutterMap['assets'] is YamlList) {
        final assetsList = flutterMap['assets'] as YamlList;
        for (final assetEntry in assetsList) {
          if (assetEntry is String) {
            if (assetEntry.endsWith('/')) {
              declaredDirectories.add(assetEntry);
            } else {
              declaredAssets.add(assetEntry);
            }
          }
        }
      }
    }

    // 2. Scan physical assets and check references
    final missingReferences = <String>[];
    final missingDirectories = <String>[];
    final physicalFiles = <File>[];

    // Check declared single assets
    for (final asset in declaredAssets) {
      final file = File(p.join(projectPath, asset));
      if (!file.existsSync()) {
        missingReferences.add(asset);
      } else {
        physicalFiles.add(file);
      }
    }

    // Check declared directories and gather files
    for (final dirAsset in declaredDirectories) {
      final dir = Directory(p.join(projectPath, dirAsset));
      if (!dir.existsSync()) {
        missingDirectories.add(dirAsset);
      } else {
        // Flutter includes direct files in the directory (non-recursive)
        try {
          final entities = dir.listSync(recursive: false);
          for (final entity in entities) {
            if (entity is File) {
              physicalFiles.add(entity);
            }
          }
        } catch (e) {
          // Keep going even if directory listing fails
        }
      }
    }

    // Deduplicate physical files
    final seenPaths = <String>{};
    final uniquePhysicalFiles = <File>[];
    for (final file in physicalFiles) {
      final normalized = p.normalize(file.path);
      if (!seenPaths.contains(normalized)) {
        seenPaths.add(normalized);
        uniquePhysicalFiles.add(file);
      }
    }

    // If there's an 'assets' folder, check for files there that might not be declared at all
    final assetsFolder = Directory(p.join(projectPath, 'assets'));
    final undeclaredFiles = <String>[];
    if (assetsFolder.existsSync()) {
      try {
        final allAssetsFiles = assetsFolder.listSync(recursive: true);
        for (final entity in allAssetsFiles) {
          if (entity is File) {
            final relativePath = p
                .relative(entity.path, from: projectPath)
                .replaceAll('\\', '/');

            // Check if this file is covered by declared files or declared directories
            bool isDeclared = declaredAssets
                .any((a) => p.normalize(a) == p.normalize(relativePath));
            if (!isDeclared) {
              isDeclared = declaredDirectories.any((d) {
                // Must be in the same folder and not a subfolder
                final fileDir = p.dirname(relativePath).replaceAll('\\', '/');
                final declaredDirClean =
                    d.endsWith('/') ? d.substring(0, d.length - 1) : d;
                return fileDir == declaredDirClean;
              });
            }

            if (!isDeclared) {
              undeclaredFiles.add(relativePath);
            }
          }
        }
      } catch (e) {
        // Fallback
      }
    }

    // 3. Check for heavy assets
    final heavyAssets = <String, double>{};
    for (final file in uniquePhysicalFiles) {
      final bytes = await file.length();
      final sizeKb = bytes / 1024.0;
      if (sizeKb > maxSizeKb) {
        final relativePath =
            p.relative(file.path, from: projectPath).replaceAll('\\', '/');
        heavyAssets[relativePath] = sizeKb;
      }
    }

    // 4. Check for unused assets in lib/
    final libDir = Directory(p.join(projectPath, 'lib'));
    final unusedAssets = <String>[];
    if (libDir.existsSync() && uniquePhysicalFiles.isNotEmpty) {
      final dartFiles = <File>[];
      try {
        final entities = libDir.listSync(recursive: true);
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.dart')) {
            dartFiles.add(entity);
          }
        }
      } catch (e) {
        // Keep going
      }

      // Load all dart files content
      final dartContents = <String>[];
      for (final file in dartFiles) {
        try {
          final text = await file.readAsString();
          dartContents.add(text);
        } catch (e) {
          // Keep going
        }
      }

      // Check each physical asset
      for (final file in uniquePhysicalFiles) {
        final relativePath =
            p.relative(file.path, from: projectPath).replaceAll('\\', '/');
        final filename = p.basename(file.path);

        bool isUsed = false;
        for (final content in dartContents) {
          if (content.contains(relativePath) || content.contains(filename)) {
            isUsed = true;
            break;
          }
        }

        if (!isUsed) {
          unusedAssets.add(relativePath);
        }
      }
    }

    // 5. Construct Report
    final buffer = StringBuffer();
    buffer.writeln('# AssetGenie Health Audit Report');
    buffer.writeln('Project Path: `$projectPath`');
    buffer.writeln('Threshold Size: `${maxSizeKb.toStringAsFixed(1)} KB`');
    buffer.writeln();

    buffer.writeln('## Summary');
    buffer.writeln('- Total declared files: ${declaredAssets.length}');
    buffer.writeln('- Total declared folders: ${declaredDirectories.length}');
    buffer
        .writeln('- Total physical files found: ${uniquePhysicalFiles.length}');
    buffer.writeln(
        '- Missing references: ${missingReferences.length + missingDirectories.length}');
    buffer.writeln('- Heavy assets flagged: ${heavyAssets.length}');
    buffer.writeln('- Unused physical assets: ${unusedAssets.length}');
    buffer.writeln();

    if (missingReferences.isNotEmpty || missingDirectories.isNotEmpty) {
      buffer.writeln('## ❌ Missing Asset References (Declared but not found)');
      for (final ref in missingReferences) {
        buffer.writeln('- File missing: `$ref`');
      }
      for (final dir in missingDirectories) {
        buffer.writeln('- Directory missing: `$dir`');
      }
      buffer.writeln();
    } else {
      buffer.writeln('## ✅ Asset References');
      buffer.writeln('All declared assets are physically present.');
      buffer.writeln();
    }

    if (heavyAssets.isNotEmpty) {
      buffer.writeln(
          '## ⚠️ Heavy Assets (Exceeds ${maxSizeKb.toStringAsFixed(1)} KB)');
      heavyAssets.forEach((path, size) {
        buffer.writeln('- `$path` - **${size.toStringAsFixed(1)} KB**');
      });
      buffer.writeln();
    } else {
      buffer.writeln('## ✅ Heavy Assets');
      buffer.writeln('No assets exceed the size threshold.');
      buffer.writeln();
    }

    if (unusedAssets.isNotEmpty) {
      buffer.writeln('## 🔍 Unused Assets (Not referenced in lib/ files)');
      for (final asset in unusedAssets) {
        buffer.writeln('- `$asset`');
      }
      buffer.writeln();
    } else {
      buffer.writeln('## ✅ Unused Assets');
      buffer.writeln('All physical assets are referenced in code.');
      buffer.writeln();
    }

    if (undeclaredFiles.isNotEmpty) {
      buffer.writeln(
          '## 📦 Undeclared Assets (Physical files in assets/ not declared in pubspec.yaml)');
      for (final file in undeclaredFiles) {
        buffer.writeln('- `$file`');
      }
      buffer.writeln();
    }

    return CallToolResult([TextContent(text: buffer.toString())]);
  } catch (e) {
    return CallToolResult(
      [TextContent(text: 'Error scanning project assets: ${e.toString()}')],
      isError: true,
    );
  }
}
