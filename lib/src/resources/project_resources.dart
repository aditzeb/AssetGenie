import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../common/arb.dart';
import '../common/project.dart';

void registerProjectResources(
  MCPServer server, {
  required String Function() getActiveProjectPath,
}) {
  if (server is! ResourcesSupport) return;
  final resources = server;

  // 1. assetgenie://project/pubspec
  resources.addResource(
    Resource(
      uri: 'assetgenie://project/pubspec',
      name: 'Flutter Project pubspec.yaml',
      description: "Direct content of the active Flutter project's pubspec.yaml.",
      mimeType: 'text/yaml',
    ),
    (request) {
      final path = getActiveProjectPath();
      final file = File(p.join(path, 'pubspec.yaml'));
      if (!file.existsSync()) {
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: request.uri,
              text: '# No pubspec.yaml found at "$path"',
              mimeType: 'text/yaml',
            ),
          ],
        );
      }
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: request.uri,
            text: file.readAsStringSync(),
            mimeType: 'text/yaml',
          ),
        ],
      );
    },
  );

  // 2. assetgenie://project/assets
  resources.addResource(
    Resource(
      uri: 'assetgenie://project/assets',
      name: 'Flutter Project Assets Summary',
      description: 'JSON list of bundled physical asset paths, extensions, and file sizes.',
      mimeType: 'application/json',
    ),
    (request) {
      final path = getActiveProjectPath();
      final loaded = FlutterProject.load(path);
      if (loaded.project == null) {
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: request.uri,
              text: jsonEncode({'error': loaded.error}),
              mimeType: 'application/json',
            ),
          ],
        );
      }
      final project = loaded.project!;
      final files = project.bundledAssetFiles();
      final items = files.map((f) => {
            'path': project.rel(f.path),
            'size_bytes': f.lengthSync(),
            'extension': p.extension(f.path).toLowerCase(),
          }).toList();

      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: request.uri,
            text: const JsonEncoder.withIndent('  ').convert(items),
            mimeType: 'application/json',
          ),
        ],
      );
    },
  );

  // 3. Resource Template: assetgenie://project/arb/{locale}
  resources.addResourceTemplate(
    ResourceTemplate(
      uriTemplate: 'assetgenie://project/arb/{locale}',
      name: 'Flutter ARB Localization File',
      description: 'Reads the ARB JSON localization file for a given locale code.',
      mimeType: 'application/json',
    ),
    (request) {
      final uri = Uri.parse(request.uri);
      if (uri.scheme != 'assetgenie' || uri.host != 'project' || !uri.path.startsWith('/arb/')) {
        return null;
      }
      final locale = uri.path.substring(5).trim();
      if (locale.isEmpty) return null;

      final path = getActiveProjectPath();
      final loaded = FlutterProject.load(path);
      if (loaded.project == null) return null;

      final file = locateArbFile(loaded.project!, locale);
      if (!file.existsSync()) {
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: request.uri,
              text: jsonEncode({
                'error': 'ARB file not found for locale "$locale"',
                'expected_path': loaded.project!.rel(file.path),
              }),
              mimeType: 'application/json',
            ),
          ],
        );
      }

      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: request.uri,
            text: file.readAsStringSync(),
            mimeType: 'application/json',
          ),
        ],
      );
    },
  );
}

