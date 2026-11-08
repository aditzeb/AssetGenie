import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'project.dart';

/// A parsed ARB file.
class ArbFile {
  final File file;
  final String locale;
  final Map<String, dynamic> data;

  ArbFile(this.file, this.locale, this.data);

  /// Translatable message keys (excluding `@` metadata keys).
  Iterable<String> get messageKeys => data.keys.where((k) => !k.startsWith('@'));
}

/// Finds every `.arb` file under `lib/` and the configured `arb-dir`.
List<File> findArbFiles(FlutterProject project) {
  final dirs = {
    p.normalize(p.join(project.root, 'lib')),
    p.normalize(p.join(project.root, project.l10n.arbDir)),
  };
  final seen = <String>{};
  final out = <File>[];
  for (final dir in dirs) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    try {
      for (final e in d.listSync(recursive: true)) {
        if (e is File &&
            e.path.endsWith('.arb') &&
            seen.add(p.normalize(e.path))) {
          out.add(e);
        }
      }
    } catch (_) {
      // Skip unreadable directories.
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Derives the locale of an ARB file from `@@locale` or its file name.
String localeOf(File file, Map<String, dynamic> data) {
  final explicit = data['@@locale'];
  if (explicit is String && explicit.isNotEmpty) return explicit;
  final name = p.basenameWithoutExtension(file.path);
  if (name.startsWith('app_')) return name.substring(4);
  if (name.contains('_')) return name.split('_').last;
  return name;
}

/// Loads and parses all ARB files. Unparseable files are skipped.
Map<String, ArbFile> loadArbFiles(FlutterProject project) {
  final out = <String, ArbFile>{};
  for (final file in findArbFiles(project)) {
    try {
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) continue;
      final parsed = jsonDecode(content);
      if (parsed is! Map<String, dynamic>) continue;
      final locale = localeOf(file, parsed);
      out[locale] = ArbFile(file, locale, parsed);
    } catch (_) {
      // Ignore invalid JSON.
    }
  }
  return out;
}

/// Locates the ARB file for [locale], or returns the path where it should be
/// created (following the project's naming convention).
File locateArbFile(FlutterProject project, String locale) {
  final l10n = project.l10n;
  final candidates = [
    p.join(project.root, l10n.arbDir, '${l10n.arbPrefix}$locale.arb'),
    p.join(project.root, 'lib', 'l10n', 'app_$locale.arb'),
    p.join(project.root, 'lib', 'l10n', '$locale.arb'),
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c);
  }
  for (final f in findArbFiles(project)) {
    final name = p.basename(f.path);
    if (name == '$locale.arb' || name.endsWith('_$locale.arb')) return f;
  }
  return File(candidates.first);
}

/// Reads an ARB file into a map (empty if missing). Throws [FormatException]
/// on invalid JSON.
Map<String, dynamic> readArb(File file) {
  if (!file.existsSync()) return <String, dynamic>{};
  final content = file.readAsStringSync();
  if (content.trim().isEmpty) return <String, dynamic>{};
  final parsed = jsonDecode(content);
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('ARB root is not a JSON object: ${file.path}');
  }
  return parsed;
}

/// Sorts ARB keys: `@@` globals first, then alphabetical with each `@key`
/// metadata entry placed directly after its message.
LinkedHashMap<String, dynamic> sortArb(Map<String, dynamic> data) {
  final keys = data.keys.toList()
    ..sort((a, b) {
      final aGlobal = a.startsWith('@@'), bGlobal = b.startsWith('@@');
      if (aGlobal && !bGlobal) return -1;
      if (!aGlobal && bGlobal) return 1;
      if (aGlobal && bGlobal) return a.compareTo(b);
      final aNorm = a.startsWith('@') ? a.substring(1) : a;
      final bNorm = b.startsWith('@') ? b.substring(1) : b;
      final cmp = aNorm.compareTo(bNorm);
      if (cmp != 0) return cmp;
      if (a.startsWith('@') && !b.startsWith('@')) return 1;
      if (!a.startsWith('@') && b.startsWith('@')) return -1;
      return a.compareTo(b);
    });
  return LinkedHashMap.fromEntries(keys.map((k) => MapEntry(k, data[k])));
}

String encodeArb(Map<String, dynamic> data) =>
    const JsonEncoder.withIndent('  ').convert(sortArb(data));

/// Writes [data] (sorted) to [file], creating parent directories.
void writeArb(File file, Map<String, dynamic> data) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(encodeArb(data));
}

/// Extracts placeholder names from an ARB message, understanding ICU
/// `plural` / `select` syntax so branch text such as `other{items}` is not
/// mistaken for a placeholder.
Set<String> placeholdersOf(String message) {
  final result = <String>{};
  try {
    _IcuParser(message, result).parseMessage(0, topLevel: true);
  } catch (_) {
    // Fall back to a simple scan on malformed ICU.
    for (final m in RegExp(r'\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,}]')
        .allMatches(message)) {
      result.add(m.group(1)!);
    }
  }
  return result;
}

class _IcuParser {
  final String s;
  final Set<String> out;

  _IcuParser(this.s, this.out);

  static const _branchingTypes = {'plural', 'select', 'selectordinal'};

  /// Parses literal text until an unmatched `}` (or end of input).
  /// Returns the index of the closing `}` (or `s.length`).
  int parseMessage(int i, {bool topLevel = false}) {
    while (i < s.length) {
      final c = s[i];
      if (c == '{') {
        i = _parseArgument(i + 1);
      } else if (c == '}') {
        if (topLevel) throw const FormatException('Unbalanced }');
        return i;
      } else {
        i++;
      }
    }
    if (!topLevel) throw const FormatException('Unterminated {');
    return i;
  }

  int _skipWs(int i) {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  String _readToken(int start, Set<String> stops) {
    var i = start;
    while (i < s.length && !stops.contains(s[i]) && s[i].trim().isNotEmpty) {
      i++;
    }
    return s.substring(start, i);
  }

  /// Parses `name}` / `name, type}` / `name, type, branches}` after a `{`.
  /// Returns the index after the closing `}`.
  int _parseArgument(int i) {
    i = _skipWs(i);
    final name = _readToken(i, const {',', '}', '{'});
    if (name.isEmpty || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      throw const FormatException('Invalid argument name');
    }
    out.add(name);
    i = _skipWs(i + name.length);
    if (i >= s.length) throw const FormatException('Unterminated argument');
    if (s[i] == '}') return i + 1;
    if (s[i] != ',') throw const FormatException('Expected , or }');
    i = _skipWs(i + 1);
    final type = _readToken(i, const {',', '}', '{'});
    i = _skipWs(i + type.length);
    if (i < s.length && s[i] == '}') return i + 1;
    if (i >= s.length || s[i] != ',') {
      throw const FormatException('Expected , after type');
    }
    i++;
    if (!_branchingTypes.contains(type)) {
      // Format style such as `{n, number, compact}`: skip to closing brace.
      final end = s.indexOf('}', i);
      if (end == -1) throw const FormatException('Unterminated argument');
      return end + 1;
    }
    // Branches: selector{message} ...
    while (true) {
      i = _skipWs(i);
      if (i >= s.length) throw const FormatException('Unterminated branches');
      if (s[i] == '}') return i + 1;
      final selector = _readToken(i, const {'{', '}'});
      i = _skipWs(i + selector.length);
      if (i >= s.length || s[i] != '{') {
        throw const FormatException('Expected { after selector');
      }
      i = parseMessage(i + 1) + 1;
    }
  }
}

