import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:assetgenie/assetgenie.dart';

void main() async {
  final dummyProjectPath =
      'C:\\Users\\Adit Victus\\.gemini\\antigravity-ide\\brain\\8eef994d-65f9-4c97-96cf-0cc08a05dff1\\scratch\\dummy_project';

  print('========================================');
  print('Running Verification for AssetGenie Tools');
  print('========================================');

  // 1. Verify auditHealth
  print('\n--- 1. Testing assetgenie_audit_health ---');
  final auditResult = await auditHealth({
    'project_path': dummyProjectPath,
    'max_size_kb': 500.0,
  });

  if (auditResult.isError == true) {
    print(
        'FAIL: auditHealth returned error: ${auditResult.content.first.toJson()}');
    exit(1);
  }

  final auditText = (auditResult.content.first.toJson())['text'] as String;
  print(auditText);

  // Check expected output
  if (!auditText.contains('Missing Asset References') ||
      !auditText.contains('assets/images/missing_asset.png') ||
      !auditText.contains('assets/other_folder/') ||
      !auditText.contains('Heavy Assets') ||
      !auditText.contains('assets/images/background.png') ||
      !auditText.contains('Unused Assets') ||
      !auditText.contains('assets/images/background.png')) {
    print('FAIL: auditHealth report did not contain expected warnings/flags.');
    exit(1);
  }
  print('PASS: auditHealth verification successful.');

  // 2. Verify syncLocalization
  print('\n--- 2. Testing assetgenie_sync_localization ---');
  final syncResult = await syncLocalization({
    'project_path': dummyProjectPath,
    'locale': 'en',
    'kv_pairs': {
      'logoutButton': 'Logout',
      'loginButton': 'Sign In', // Merge/overwrite existing key
      'cancelButton': 'Cancel',
    }
  });

  if (syncResult.isError == true) {
    print(
        'FAIL: syncLocalization returned error: ${syncResult.content.first.toJson()}');
    exit(1);
  }

  print((syncResult.content.first.toJson())['text']);

  // Verify arb file content
  final arbFile = File(p.join(dummyProjectPath, 'lib', 'l10n', 'app_en.arb'));
  if (!arbFile.existsSync()) {
    print('FAIL: app_en.arb does not exist.');
    exit(1);
  }

  final arbContent = arbFile.readAsStringSync();
  print('Updated ARB Content:');
  print(arbContent);

  final parsedArb = jsonDecode(arbContent) as Map<String, dynamic>;
  if (parsedArb['logoutButton'] != 'Logout' ||
      parsedArb['loginButton'] != 'Sign In' ||
      parsedArb['cancelButton'] != 'Cancel') {
    print('FAIL: translation keys were not merged correctly.');
    exit(1);
  }

  // Check alphabetization order:
  // Special keys starting with @@ should be first.
  // Standard keys and metadata keys starting with @ should be sorted next to each other.
  final keys = parsedArb.keys.toList();
  print('Keys order: $keys');
  final expectedKeysOrder = [
    '@@locale',
    'appTitle',
    '@appTitle',
    'cancelButton',
    'loginButton',
    'logoutButton'
  ];
  bool matchesOrder = true;
  for (var i = 0; i < expectedKeysOrder.length; i++) {
    if (keys[i] != expectedKeysOrder[i]) {
      matchesOrder = false;
      break;
    }
  }

  if (!matchesOrder) {
    print('FAIL: Keys were not sorted in standard ARB alphabetical order.');
    print('Expected: $expectedKeysOrder');
    print('Actual: $keys');
    exit(1);
  }
  print('PASS: syncLocalization verification successful.');

  // 3. Verify generateConstants
  print('\n--- 3. Testing assetgenie_generate_constants ---');
  final genResult = await generateConstants({
    'project_path': dummyProjectPath,
    'output_filename': 'generated_assets.dart',
  });

  if (genResult.isError == true) {
    print(
        'FAIL: generateConstants returned error: ${genResult.content.first.toJson()}');
    exit(1);
  }

  print((genResult.content.first.toJson())['text']);

  final genFile = File(
      p.join(dummyProjectPath, 'lib', 'generated', 'generated_assets.dart'));
  if (!genFile.existsSync()) {
    print('FAIL: generated_assets.dart was not created.');
    exit(1);
  }

  final genContent = genFile.readAsStringSync();
  print('Generated Constants Content:');
  print(genContent);

  if (!genContent
          .contains('static const String logo = \'assets/images/logo.png\';') ||
      !genContent.contains(
          'static const String background = \'assets/images/background.png\';')) {
    print(
        'FAIL: generated constants class does not contain expected constants.');
    exit(1);
  }
  print('PASS: generateConstants verification successful.');

  // 4. Verify auditLocalization
  print('\n--- 4. Testing assetgenie_audit_localization ---');
  // Inject welcomeMessage with placeholder into app_en.arb
  final appEnFile = File(p.join(dummyProjectPath, 'lib', 'l10n', 'app_en.arb'));
  final appEnData =
      jsonDecode(appEnFile.readAsStringSync()) as Map<String, dynamic>;
  appEnData['welcomeMessage'] = 'Welcome, {name}!';
  appEnFile.writeAsStringSync(jsonEncode(appEnData));

  // Write app_es.arb with missing key, extra key, and placeholder mismatch
  final appEsFile = File(p.join(dummyProjectPath, 'lib', 'l10n', 'app_es.arb'));
  appEsFile.writeAsStringSync(jsonEncode({
    '@@locale': 'es',
    'appTitle': 'Aplicación de demostración',
    'cancelButton': 'Cancelar',
    'loginButton': 'Iniciar sesión',
    'welcomeMessage': '¡Bienvenido, {username}!',
    'extraSpanishKey': 'Hola'
  }));

  final auditLocResult = await auditLocalization({
    'project_path': dummyProjectPath,
    'primary_locale': 'en',
    'unused_keys_check': true,
  });

  // Clean up app_es.arb and restore app_en.arb
  if (appEsFile.existsSync()) {
    appEsFile.deleteSync();
  }
  appEnData.remove('welcomeMessage');
  appEnFile.writeAsStringSync(jsonEncode(appEnData));

  if (auditLocResult.isError == true) {
    print(
        'FAIL: auditLocalization returned error: ${auditLocResult.content.first.toJson()}');
    exit(1);
  }

  final auditLocText =
      (auditLocResult.content.first.toJson())['text'] as String;
  print(auditLocText);

  // Assertions on report content
  if (!auditLocText.contains('Missing Translations') ||
      !auditLocText.contains('logoutButton') ||
      !auditLocText.contains('Extra Translations') ||
      !auditLocText.contains('extraSpanishKey') ||
      !auditLocText.contains('Placeholder Mismatches') ||
      !auditLocText.contains('welcomeMessage') ||
      !auditLocText.contains('Unused Translation Keys')) {
    print(
        'FAIL: auditLocalization report did not contain expected sections or findings.');
    exit(1);
  }
  print('PASS: auditLocalization verification successful.');

  // 5. Verify appHarness (Mock VM Service)
  print('\n--- 5. Testing assetgenie_app_harness ---');
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

          final streamId = parsed['params']?['streamId'] as String?;
          if (streamId == 'Stdout') {
            ws.add(jsonEncode({
              'jsonrpc': '2.0',
              'method': 'streamNotify',
              'params': {
                'streamId': 'Stdout',
                'event': {
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'bytes': base64
                      .encode(utf8.encode('Hello from Flutter Stdout!\n')),
                }
              }
            }));
          }
        }
      });
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  });

  // Test action: get_widget_tree
  final treeResult = await appHarness({
    'vm_service_uri': mockVmServiceUri,
    'action': 'get_widget_tree',
  });

  if (treeResult.isError == true) {
    print(
        'FAIL: appHarness get_widget_tree returned error: ${treeResult.content.first.toJson()}');
    await serverSub.cancel();
    await mockServer.close();
    exit(1);
  }
  final treeText = (treeResult.content.first.toJson())['text'] as String;
  if (!treeText.contains('MyAppRoot') || !treeText.contains('inspector-123')) {
    print(
        'FAIL: appHarness get_widget_tree response did not contain expected root widget.');
    await serverSub.cancel();
    await mockServer.close();
    exit(1);
  }

  // Test action: capture_screenshot
  final screenshotResult = await appHarness({
    'vm_service_uri': mockVmServiceUri,
    'action': 'capture_screenshot',
  });

  if (screenshotResult.isError == true) {
    print(
        'FAIL: appHarness capture_screenshot returned error: ${screenshotResult.content.first.toJson()}');
    await serverSub.cancel();
    await mockServer.close();
    exit(1);
  }
  final screenshotJson = screenshotResult.content.first.toJson();
  if (screenshotJson['type'] != 'image' ||
      screenshotJson['url'] !=
          'data:image/png;base64,mock_base64_png_image_data_here') {
    print(
        'FAIL: appHarness capture_screenshot response did not contain expected ImageContent.');
    await serverSub.cancel();
    await mockServer.close();
    exit(1);
  }

  // Test action: get_logs
  final logsResult = await appHarness({
    'vm_service_uri': mockVmServiceUri,
    'action': 'get_logs',
  });

  if (logsResult.isError == true) {
    print(
        'FAIL: appHarness get_logs returned error: ${logsResult.content.first.toJson()}');
    await serverSub.cancel();
    await mockServer.close();
    exit(1);
  }
  final logsText = (logsResult.content.first.toJson())['text'] as String;
  if (!logsText.contains('Hello from Flutter Stdout!')) {
    print(
        'FAIL: appHarness get_logs response did not contain expected captured logs.');
    await serverSub.cancel();
    await mockServer.close();
    exit(1);
  }

  await serverSub.cancel();
  await mockServer.close();
  print('PASS: appHarness verification successful.');

  print('\n========================================');
  print('ALL VERIFICATIONS PASSED SUCCESSFULLY!');
  print('========================================');
}
