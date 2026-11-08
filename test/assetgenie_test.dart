import 'dart:convert';
import 'dart:io';

import 'package:assetgenie/assetgenie.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String projectPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('assetgenie_suite_');
    projectPath = tempDir.path;

    // 1. Create pubspec.yaml
    File(p.join(projectPath, 'pubspec.yaml')).writeAsStringSync('''
name: demo_flutter_app
description: A sample Flutter application.
version: 1.0.0
environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/images/logo.png
    - assets/images/missing_asset.png
    - assets/other_folder/
  fonts:
    - family: RobotoCustom
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
''');

    // 2. Create assets folders and sample files
    final imgDir = Directory(p.join(projectPath, 'assets', 'images'))..createSync(recursive: true);
    Directory(p.join(projectPath, 'assets', 'fonts'))..createSync(recursive: true);

    // Create a valid test PNG image (100x100 solid blue)
    final sampleImg = img.Image(width: 100, height: 100);
    img.fill(sampleImg, color: img.ColorRgb8(0, 100, 255));
    File(p.join(imgDir.path, 'logo.png')).writeAsStringSync('png_data_mock');
    File(p.join(imgDir.path, 'background.png')).writeAsBytesSync(img.encodePng(sampleImg));

    // Create an uncompressed heavy asset mock (> 500 KB)
    final largeBytes = List<int>.filled(550 * 1024, 65);
    File(p.join(imgDir.path, 'heavy_photo.jpg')).writeAsBytesSync(largeBytes);

    // 3. Create lib/ source code
    final libDir = Directory(p.join(projectPath, 'lib'))..createSync(recursive: true);
    File(p.join(libDir.path, 'main.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Welcome to MyApp')),
        body: Column(
          children: [
            Image.asset('assets/images/logo.png'),
            Text('Hardcoded title string'),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}
''');

    // 4. Create ARB localization files
    final l10nDir = Directory(p.join(projectPath, 'lib', 'l10n'))..createSync(recursive: true);
    File(p.join(l10nDir.path, 'app_en.arb')).writeAsStringSync(jsonEncode({
      '@@locale': 'en',
      'appTitle': 'Demo App',
      '@appTitle': {'description': 'Main app title'},
      'loginButton': 'Sign In',
      'logoutButton': 'Sign Out',
      'welcomeUser': 'Welcome, {name}!',
    }));

    File(p.join(l10nDir.path, 'app_es.arb')).writeAsStringSync(jsonEncode({
      '@@locale': 'es',
      'appTitle': 'Aplicación de demostración',
      'loginButton': 'Iniciar sesión',
      'welcomeUser': '¡Bienvenido, {username}!', // intentional placeholder mismatch
      'extraKeyEs': 'Solo en español',
    }));
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('assetgenie_audit_health flags missing, heavy, and unused assets', () async {
    final result = await auditHealth({
      'project_path': projectPath,
      'max_size_kb': 500.0,
    });

    expect(result.isError, isNot(true));
    final text = resultText(result);
    expect(text, contains('Missing Asset References'));
    expect(text, contains('missing_asset.png'));
    expect(text, contains('Heavy Assets'));
    expect(text, contains('heavy_photo.jpg'));
    expect(text, contains('Unused Assets'));
    expect(result.structuredContent, isNotNull);
    expect(result.structuredContent!['physical_files_count'], greaterThan(0));
  });

  test('assetgenie_sync_localization merges and alphabetizes keys', () async {
    final result = await syncLocalization({
      'project_path': projectPath,
      'locale': 'en',
      'kv_pairs': {
        'cancelButton': 'Cancel',
        'confirmButton': 'Confirm',
      },
      'dry_run': false,
    });

    expect(result.isError, isNot(true));
    final arbFile = File(p.join(projectPath, 'lib', 'l10n', 'app_en.arb'));
    final parsed = jsonDecode(arbFile.readAsStringSync()) as Map<String, dynamic>;
    expect(parsed['cancelButton'], equals('Cancel'));
    expect(parsed['confirmButton'], equals('Confirm'));

    final keys = parsed.keys.toList();
    expect(keys.first, equals('@@locale'));
  });

  test('assetgenie_generate_constants creates type-safe Dart class with fonts', () async {
    final result = await generateConstants({
      'project_path': projectPath,
      'output_filename': 'generated_assets.dart',
      'dry_run': false,
    });

    expect(result.isError, isNot(true));
    final genFile = File(p.join(projectPath, 'lib', 'generated', 'generated_assets.dart'));
    expect(genFile.existsSync(), isTrue);

    final code = genFile.readAsStringSync();
    expect(code, contains('class Assets {'));
    expect(code, contains('static const String logo ='));
    expect(code, contains('RobotoCustom'));
  });

  test('assetgenie_audit_localization detects missing keys, extra keys & ICU mismatches', () async {
    final result = await auditLocalization({
      'project_path': projectPath,
      'primary_locale': 'en',
      'unused_keys_check': true,
    });

    expect(result.isError, isNot(true));
    final text = resultText(result);
    expect(text, contains('Missing Translations'));
    expect(text, contains('logoutButton'));
    expect(text, contains('Extra Translations'));
    expect(text, contains('extraKeyEs'));
    expect(text, contains('Placeholder Mismatches'));
    expect(text, contains('welcomeUser'));
  });

  test('assetgenie_optimize_images processes and compresses raster images', () async {
    final result = await optimizeImages({
      'project_path': projectPath,
      'quality': 80,
      'convert_to_webp': true,
      'dry_run': true,
    });

    expect(result.isError, isNot(true));
    final structured = result.structuredContent!;
    expect(structured['files_processed'], greaterThan(0));
    expect(structured['dry_run'], isTrue);
  });

  test('assetgenie_extract_strings discovers hardcoded Text() widgets', () async {
    final result = await extractStrings({
      'project_path': projectPath,
      'dry_run': true,
    });

    expect(result.isError, isNot(true));
    final text = resultText(result);
    expect(text, contains('Summary'));
    final structured = result.structuredContent!;
    expect(structured['strings_found'], greaterThan(0));
    final keys = structured['extracted_keys'] as Map;
    expect(keys.values.any((v) => v.toString().contains('Welcome to MyApp')), isTrue);
  });

  test('assetgenie_audit_variants identifies missing 2.0x/3.0x variants', () async {
    final result = await auditVariants({
      'project_path': projectPath,
    });

    expect(result.isError, isNot(true));
    final structured = result.structuredContent!;
    expect(structured['missing_variants'], isNotNull);
  });

  test('assetgenie_audit_accessibility flags unlabelled Image and IconButton widgets', () async {
    final result = await auditAccessibility({
      'project_path': projectPath,
    });

    expect(result.isError, isNot(true));
    final structured = result.structuredContent!;
    expect(structured['unlabelled_count'], greaterThan(0));
    final issues = (structured['issues'] as List).cast<Map>();
    expect(issues.any((i) => i['widget_type'] == 'Image'), isTrue);
    expect(issues.any((i) => i['widget_type'] == 'IconButton'), isTrue);
  });

  test('assetgenie_translate_localization identifies untranslated keys', () async {
    final result = await translateLocalization({
      'project_path': projectPath,
      'target_locale': 'es',
      'dry_run': true,
    });

    expect(result.isError, isNot(true));
    final structured = result.structuredContent!;
    expect(structured['target_locale'], equals('es'));
    final translations = structured['translations'] as Map;
    expect(translations.containsKey('logoutButton'), isTrue);
  });

  test('assetgenie_app_harness connects to mock VM Service', () async {
    final mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mockPort = mockServer.port;
    final mockVmServiceUri = 'http://127.0.0.1:$mockPort/mock_token/';

    final serverSub = mockServer.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen((data) {
          final parsed = jsonDecode(data as String) as Map<String, dynamic>;
          final id = parsed['id'];
          final method = parsed['method'] as String;

          if (method == 'ext.flutter.inspector.getRootWidgetSummaryTree') {
            ws.add(jsonEncode({
              'jsonrpc': '2.0',
              'result': {
                'result': {
                  'valueId': 'inspector-123',
                  'description': 'MyAppRoot',
                }
              },
              'id': id,
            }));
          } else if (method == 'ext.flutter.inspector.screenshot') {
            ws.add(jsonEncode({
              'jsonrpc': '2.0',
              'result': {
                'result': 'mock_base64_png_image_data_here',
              },
              'id': id,
            }));
          } else if (method == 'streamListen') {
            ws.add(jsonEncode({
              'jsonrpc': '2.0',
              'result': {'status': 'success'},
              'id': id,
            }));
          }
        });
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    try {
      final treeResult = await appHarness({
        'vm_service_uri': mockVmServiceUri,
        'action': 'get_widget_tree',
      });
      expect(treeResult.isError, isNot(true));
      expect(resultText(treeResult), contains('MyAppRoot'));

      final shotResult = await appHarness({
        'vm_service_uri': mockVmServiceUri,
        'action': 'capture_screenshot',
      });
      expect(shotResult.isError, isNot(true));
      expect(shotResult.content.first.isImage, isTrue);
    } finally {
      await serverSub.cancel();
      await mockServer.close();
    }
  });
}
