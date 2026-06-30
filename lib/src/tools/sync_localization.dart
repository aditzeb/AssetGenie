import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mcp_server/mcp_server.dart';

Future<CallToolResult> syncLocalization(Map<String, dynamic> arguments) async {
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

  final locale = arguments['locale'] as String?;
  if (locale == null || locale.isEmpty) {
    return CallToolResult(
      [TextContent(text: 'Error: "locale" is required and cannot be empty.')],
      isError: true,
    );
  }

  final kvPairs = arguments['kv_pairs'];
  if (kvPairs == null || kvPairs is! Map) {
    return CallToolResult(
      [
        TextContent(
            text:
                'Error: "kv_pairs" must be a JSON object containing key-value translation pairs.')
      ],
      isError: true,
    );
  }

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

    // 1. Locate the target .arb file
    File? arbFile;

    // Check common paths
    final defaultArbPath1 =
        p.join(projectPath, 'lib', 'l10n', 'app_$locale.arb');
    final defaultArbPath2 = p.join(projectPath, 'lib', 'l10n', '$locale.arb');

    if (File(defaultArbPath1).existsSync()) {
      arbFile = File(defaultArbPath1);
    } else if (File(defaultArbPath2).existsSync()) {
      arbFile = File(defaultArbPath2);
    } else {
      // Search recursively for any file ending with $locale.arb in project
      try {
        final libDir = Directory(p.join(projectPath, 'lib'));
        if (libDir.existsSync()) {
          final entities = libDir.listSync(recursive: true);
          for (final entity in entities) {
            if (entity is File && entity.path.endsWith('.arb')) {
              final filename = p.basename(entity.path);
              if (filename == '$locale.arb' ||
                  filename == 'app_$locale.arb' ||
                  filename.endsWith('_$locale.arb')) {
                arbFile = entity;
                break;
              }
            }
          }
        }
      } catch (e) {
        // Search error, fallback to default
      }
    }

    // If still not found, initialize default
    if (arbFile == null) {
      arbFile = File(defaultArbPath1);
      // Ensure directory exists
      arbFile.parent.createSync(recursive: true);
    }

    // 2. Read existing content
    final existingData = <String, dynamic>{};
    if (arbFile.existsSync()) {
      final content = await arbFile.readAsString();
      if (content.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(content);
          if (parsed is Map<String, dynamic>) {
            existingData.addAll(parsed);
          }
        } catch (e) {
          return CallToolResult(
            [
              TextContent(
                  text:
                      'Error parsing existing ARB file "${arbFile.path}" as JSON: $e')
            ],
            isError: true,
          );
        }
      }
    }

    // Ensure @@locale is set
    if (!existingData.containsKey('@@locale')) {
      existingData['@@locale'] = locale;
    }

    // 3. Merge new key-value pairs
    kvPairs.forEach((key, value) {
      existingData[key.toString()] = value;
    });

    // 4. Alphabetize keys with standard ARB sorting logic
    final sortedKeys = existingData.keys.toList();
    sortedKeys.sort((a, b) {
      // Global metadata starts with @@. Keep it at the top.
      if (a.startsWith('@@') && !b.startsWith('@@')) return -1;
      if (!a.startsWith('@@') && b.startsWith('@@')) return 1;
      if (a.startsWith('@@') && b.startsWith('@@')) return a.compareTo(b);

      // Normalize key by stripping leading @ (but not @@)
      final aNorm = a.startsWith('@') ? a.substring(1) : a;
      final bNorm = b.startsWith('@') ? b.substring(1) : b;

      final comp = aNorm.compareTo(bNorm);
      if (comp != 0) {
        return comp;
      }

      // If normalized names are the same, the one without @ comes first (e.g. title before @title)
      if (a.startsWith('@') && !b.startsWith('@')) return 1;
      if (!a.startsWith('@') && b.startsWith('@')) return -1;

      return a.compareTo(b);
    });

    final sortedData = LinkedHashMap<String, dynamic>();
    for (final key in sortedKeys) {
      sortedData[key] = existingData[key];
    }

    // 5. Write back to disk
    final encoder = JsonEncoder.withIndent('  ');
    final prettyJson = encoder.convert(sortedData);
    await arbFile.writeAsString(prettyJson);

    final actionTaken = arbFile.existsSync() ? 'Updated' : 'Created';
    final relativeArbPath =
        p.relative(arbFile.path, from: projectPath).replaceAll('\\', '/');

    return CallToolResult([
      TextContent(
          text:
              'Success: $actionTaken localization file `$relativeArbPath` for locale `$locale`.\n'
              'Merged ${kvPairs.length} translation keys and sorted the result alphabetically.')
    ]);
  } catch (e) {
    return CallToolResult(
      [TextContent(text: 'Error syncing localization: ${e.toString()}')],
      isError: true,
    );
  }
}
