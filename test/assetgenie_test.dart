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

  print('\n========================================');
  print('ALL VERIFICATIONS PASSED SUCCESSFULLY!');
  print('========================================');
}
