import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A declared font family from the `flutter: fonts:` section of pubspec.yaml.
class FontFamily {
  final String family;
  final List<String> assets;

  const FontFamily(this.family, this.assets);
}

/// Configuration of `flutter gen-l10n`, read from `l10n.yaml` (with defaults).
class L10nConfig {
  final String arbDir;
  final String templateArbFile;
  final String outputLocalizationFile;
  final String outputClass;
  final String? outputDir;
  final bool? syntheticPackage;
  final bool nullableGetter;

  const L10nConfig({
    this.arbDir = 'lib/l10n',
    this.templateArbFile = 'app_en.arb',
    this.outputLocalizationFile = 'app_localizations.dart',
    this.outputClass = 'AppLocalizations',
    this.outputDir,
    this.syntheticPackage,
    this.nullableGetter = true,
  });

  /// The locale of the template ARB file, e.g. `app_en.arb` -> `en`.
  String get templateLocale {
    final name = p.basenameWithoutExtension(templateArbFile);
    final idx = name.indexOf('_');
    return idx == -1 ? name : name.substring(idx + 1);
  }

  /// File name prefix used for ARB files, e.g. `app_en.arb` -> `app_`.
  String get arbPrefix {
    final name = p.basenameWithoutExtension(templateArbFile);
    final idx = name.indexOf('_');
    return idx == -1 ? '' : name.substring(0, idx + 1);
  }

  /// The expression used to access localized strings in widget code.
  String get accessor =>
      '$outputClass.of(context)${nullableGetter ? '!' : ''}';

  /// The import statement for the generated localizations class.
  String importFor(String packageName) {
    if (syntheticPackage == true) {
      return "import 'package:flutter_gen/gen_l10n/$outputLocalizationFile';";
    }
    final dir = (outputDir ?? arbDir).replaceAll('\\', '/');
    final relToLib =
        dir.startsWith('lib/') ? dir.substring(4) : (dir == 'lib' ? '' : dir);
    final prefix = relToLib.isEmpty ? '' : '$relToLib/';
    return "import 'package:$packageName/$prefix$outputLocalizationFile';";
  }
}

/// A parsed Flutter project: pubspec metadata, asset declarations and helpers.
class FlutterProject {
  final String root;
  final String name;
  final YamlMap? pubspec;
  final String pubspecText;
  final List<String> declaredAssetFiles;
  final List<String> declaredAssetDirs;

  /// Declared asset directory -> list of transformer packages applied to it.
  final Map<String, List<String>> assetTransformers;
  final List<FontFamily> fonts;
  final L10nConfig l10n;

  FlutterProject._({
    required this.root,
    required this.name,
    required this.pubspec,
    required this.pubspecText,
    required this.declaredAssetFiles,
    required this.declaredAssetDirs,
    required this.assetTransformers,
    required this.fonts,
    required this.l10n,
  });

  /// Loads a project, returning either the project or a human-readable error.
  static ({FlutterProject? project, String? error}) load(Object? rawPath) {
    final projectPath = rawPath is String ? rawPath.trim() : null;
    if (projectPath == null || projectPath.isEmpty) {
      return (
        project: null,
        error: '"project_path" is required and cannot be empty.'
      );
    }
    if (!Directory(projectPath).existsSync()) {
      return (
        project: null,
        error: 'Project directory does not exist at "$projectPath".'
      );
    }
    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return (
        project: null,
        error: 'No "pubspec.yaml" found at "$projectPath". '
            'This does not appear to be a Flutter project.'
      );
    }

    final text = pubspecFile.readAsStringSync();
    YamlMap? yaml;
    try {
      final parsed = loadYaml(text);
      if (parsed is YamlMap) yaml = parsed;
    } catch (e) {
      return (project: null, error: 'Failed to parse pubspec.yaml: $e');
    }

    final files = <String>[];
    final dirs = <String>[];
    final transformers = <String, List<String>>{};
    final fonts = <FontFamily>[];

    final flutter = yaml?['flutter'];
    if (flutter is YamlMap) {
      final assets = flutter['assets'];
      if (assets is YamlList) {
        for (final entry in assets) {
          String? path;
          final packages = <String>[];
          if (entry is String) {
            path = entry;
          } else if (entry is YamlMap && entry['path'] is String) {
            path = entry['path'] as String;
            final t = entry['transformers'];
            if (t is YamlList) {
              for (final tr in t) {
                if (tr is YamlMap && tr['package'] is String) {
                  packages.add(tr['package'] as String);
                }
              }
            }
          }
          if (path == null) continue;
          path = path.replaceAll('\\', '/');
          if (path.endsWith('/')) {
            dirs.add(path);
          } else {
            files.add(path);
          }
          if (packages.isNotEmpty) transformers[path] = packages;
        }
      }

      final fontList = flutter['fonts'];
      if (fontList is YamlList) {
        for (final f in fontList) {
          if (f is! YamlMap || f['family'] is! String) continue;
          final assetsOfFamily = <String>[];
          final fs = f['fonts'];
          if (fs is YamlList) {
            for (final font in fs) {
              if (font is YamlMap && font['asset'] is String) {
                assetsOfFamily.add(font['asset'] as String);
              }
            }
          }
          fonts.add(FontFamily(f['family'] as String, assetsOfFamily));
        }
      }
    }

    return (
      project: FlutterProject._(
        root: projectPath,
        name: (yaml?['name'] as String?) ?? p.basename(projectPath),
        pubspec: yaml,
        pubspecText: text,
        declaredAssetFiles: files,
        declaredAssetDirs: dirs,
        assetTransformers: transformers,
        fonts: fonts,
        l10n: _loadL10n(projectPath),
      ),
      error: null
    );
  }

  static L10nConfig _loadL10n(String root) {
    final file = File(p.join(root, 'l10n.yaml'));
    if (!file.existsSync()) return const L10nConfig();
    try {
      final y = loadYaml(file.readAsStringSync());
      if (y is! YamlMap) return const L10nConfig();
      return L10nConfig(
        arbDir: (y['arb-dir'] as String?) ?? 'lib/l10n',
        templateArbFile: (y['template-arb-file'] as String?) ?? 'app_en.arb',
        outputLocalizationFile: (y['output-localization-file'] as String?) ??
            'app_localizations.dart',
        outputClass: (y['output-class'] as String?) ?? 'AppLocalizations',
        outputDir: y['output-dir'] as String?,
        syntheticPackage: y['synthetic-package'] as bool?,
        nullableGetter: (y['nullable-getter'] as bool?) ?? true,
      );
    } catch (_) {
      return const L10nConfig();
    }
  }

  /// Whether pubspec.yaml lists [package] under dependencies or dev_dependencies.
  bool hasDependency(String package) {
    for (final section in ['dependencies', 'dev_dependencies']) {
      final deps = pubspec?[section];
      if (deps is YamlMap && deps.containsKey(package)) return true;
    }
    return false;
  }

  /// Converts an absolute path into a forward-slash project-relative path.
  String rel(String absolute) =>
      p.relative(absolute, from: root).replaceAll('\\', '/');

  String abs(String relative) => p.normalize(p.join(root, relative));

  /// All Dart source files under `lib/`.
  ///
  /// When [excludeGenerated] is true, files in `lib/generated/`, files ending in
  /// `.g.dart` / `.freezed.dart`, and generated localization files are skipped.
  List<File> dartFiles({bool excludeGenerated = false}) {
    final libDir = Directory(p.join(root, 'lib'));
    if (!libDir.existsSync()) return [];
    final result = <File>[];
    try {
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (excludeGenerated && isGeneratedDart(rel(entity.path))) continue;
        result.add(entity);
      }
    } catch (_) {
      // Ignore unreadable directories.
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  bool isGeneratedDart(String relativePath) {
    final base = p.basename(relativePath);
    if (relativePath.startsWith('lib/generated/')) return true;
    if (base.endsWith('.g.dart') || base.endsWith('.freezed.dart')) {
      return true;
    }
    final l10nOut = (l10n.outputDir ?? l10n.arbDir).replaceAll('\\', '/');
    final outBase = p.basenameWithoutExtension(l10n.outputLocalizationFile);
    if (relativePath.startsWith('$l10nOut/') && base.startsWith(outBase)) {
      return true;
    }
    return false;
  }

  /// Reads the contents of all Dart files in `lib/`, keyed by relative path.
  Map<String, String> readDartSources({bool excludeGenerated = false}) {
    final out = <String, String>{};
    for (final f in dartFiles(excludeGenerated: excludeGenerated)) {
      try {
        out[rel(f.path)] = f.readAsStringSync();
      } catch (_) {
        // Skip unreadable files.
      }
    }
    return out;
  }

  /// Files directly inside a declared asset directory (Flutter asset
  /// directories are not recursive).
  List<File> filesInDeclaredDir(String dir) {
    final d = Directory(abs(dir));
    if (!d.existsSync()) return [];
    try {
      return d.listSync().whereType<File>().where((f) {
        final base = p.basename(f.path).toLowerCase();
        return base != '.ds_store' && base != 'thumbs.db';
      }).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    } catch (_) {
      return [];
    }
  }

  /// All physical files that are bundled according to pubspec declarations.
  List<File> bundledAssetFiles() {
    final seen = <String>{};
    final out = <File>[];
    void add(File f) {
      if (seen.add(p.normalize(f.absolute.path))) out.add(f);
    }

    for (final asset in declaredAssetFiles) {
      final f = File(abs(asset));
      if (f.existsSync()) add(f);
    }
    for (final dir in declaredAssetDirs) {
      filesInDeclaredDir(dir).forEach(add);
    }
    return out;
  }
}

const imageExtensions = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};

/// Matches a resolution variant directory name such as `2.0x` or `3x`.
final variantDirPattern = RegExp(r'^\d+(\.\d+)?x$');

