/// Lightweight lexical helpers for scanning Dart source without a full parser.
library;

/// Computes, for each character offset in [src], whether it is "code" (i.e.
/// not inside a comment or string literal). String delimiters themselves are
/// marked as non-code. Interpolated expressions inside strings are treated
/// as non-code (they are part of the string).
List<bool> codeMask(String src) {
  final mask = List<bool>.filled(src.length, true);
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        mask[i++] = false;
      }
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      var depth = 0;
      while (i < src.length) {
        if (src.startsWith('/*', i)) {
          depth++;
          mask[i] = mask[i + 1] = false;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          mask[i] = mask[i + 1] = false;
          i += 2;
          if (depth == 0) break;
        } else {
          mask[i++] = false;
        }
      }
    } else if (c == '"' || c == "'") {
      final lit = parseStringLiteral(src, i);
      final end = lit?.end ?? src.length;
      for (var j = i; j < end; j++) {
        mask[j] = false;
      }
      i = end;
    } else if (c == 'r' &&
        i + 1 < src.length &&
        (src[i + 1] == '"' || src[i + 1] == "'") &&
        (i == 0 || !_isIdentChar(src[i - 1]))) {
      final lit = parseStringLiteral(src, i);
      final end = lit?.end ?? src.length;
      for (var j = i; j < end; j++) {
        mask[j] = false;
      }
      i = end;
    } else {
      i++;
    }
  }
  return mask;
}

bool _isIdentChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

/// One part of a Dart string literal: either literal text or an
/// interpolated expression.
class StringPart {
  final String? text;
  final String? expression;

  const StringPart.text(this.text) : expression = null;
  const StringPart.expr(this.expression) : text = null;

  bool get isExpression => expression != null;
}

/// A parsed Dart string literal.
class StringLiteral {
  final int start;
  final int end;
  final bool raw;
  final List<StringPart> parts;

  StringLiteral(this.start, this.end, this.raw, this.parts);

  bool get hasInterpolation => parts.any((p) => p.isExpression);

  /// The literal value with interpolations left out.
  String get plainText =>
      parts.where((p) => !p.isExpression).map((p) => p.text).join();
}

/// Parses a Dart string literal starting at [start] (at the quote, or at an
/// `r` prefix). Returns `null` if [start] is not the beginning of a string.
StringLiteral? parseStringLiteral(String src, int start) {
  var i = start;
  var raw = false;
  if (i < src.length && src[i] == 'r') {
    raw = true;
    i++;
  }
  if (i >= src.length || (src[i] != '"' && src[i] != "'")) return null;
  final quote = src[i];
  final triple = src.startsWith(quote * 3, i);
  final delim = triple ? quote * 3 : quote;
  i += delim.length;

  final parts = <StringPart>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      parts.add(StringPart.text(buf.toString()));
      buf.clear();
    }
  }

  while (i < src.length) {
    if (src.startsWith(delim, i)) {
      flush();
      return StringLiteral(start, i + delim.length, raw, parts);
    }
    final c = src[i];
    if (!triple && c == '\n') return null; // Unterminated single-line string.
    if (!raw && c == '\\' && i + 1 < src.length) {
      final n = src[i + 1];
      const escapes = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f'};
      buf.write(escapes[n] ?? n);
      i += 2;
      continue;
    }
    if (!raw && c == r'$' && i + 1 < src.length) {
      if (src[i + 1] == '{') {
        final close = _matchBraceInInterpolation(src, i + 1);
        if (close == -1) return null;
        flush();
        parts.add(StringPart.expr(src.substring(i + 2, close).trim()));
        i = close + 1;
        continue;
      }
      final m = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(src, i + 1);
      if (m != null) {
        flush();
        parts.add(StringPart.expr(m.group(0)));
        i = m.end;
        continue;
      }
    }
    buf.write(c);
    i++;
  }
  return null;
}

int _matchBraceInInterpolation(String src, int openIdx) {
  var depth = 0;
  var i = openIdx;
  while (i < src.length) {
    final c = src[i];
    if (c == '"' || c == "'") {
      final lit = parseStringLiteral(src, i);
      if (lit == null) return -1;
      i = lit.end;
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

/// Finds the index of the `)` matching the `(` at [openIdx], using [mask] to
/// skip strings and comments. Returns -1 if unbalanced.
int findClosingParen(String src, List<bool> mask, int openIdx) {
  var depth = 0;
  for (var i = openIdx; i < src.length; i++) {
    if (!mask[i]) continue;
    final c = src[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return c == ')' ? i : -1;
    }
  }
  return -1;
}

/// 1-based line number of [offset] in [src].
int lineOf(String src, int offset) {
  var line = 1;
  final end = offset.clamp(0, src.length);
  for (var i = 0; i < end; i++) {
    if (src.codeUnitAt(i) == 10) line++;
  }
  return line;
}

/// Returns the code within the top-level argument list of a call, i.e. the
/// text between `(` at [openIdx] and its matching `)`, with nested calls
/// replaced by spaces, so that only the call's own named arguments remain.
String topLevelArgs(String src, List<bool> mask, int openIdx, int closeIdx) {
  final buf = StringBuffer();
  var depth = 0;
  for (var i = openIdx + 1; i < closeIdx; i++) {
    final c = src[i];
    if (mask[i] && (c == '(' || c == '[' || c == '{')) depth++;
    buf.write(depth == 0 ? (mask[i] ? c : ' ') : ' ');
    if (mask[i] && (c == ')' || c == ']' || c == '}')) depth--;
  }
  return buf.toString();
}

/// Walks outward from [offset] and returns the ranges of `const` keywords
/// on enclosing constructor calls / collection literals, which must be
/// removed when a non-constant expression is inserted at [offset].
List<(int, int)> enclosingConstKeywords(
    String src, List<bool> mask, int offset) {
  final out = <(int, int)>[];
  var depth = 0;
  final constBefore = RegExp(
      r'\bconst\s+(?:[A-Za-z_][\w.]*\s*)?(?:<[^<>()]*>)?\s*$|\bconst\s*(?:<[^<>()]*>)?\s*$');
  for (var i = offset - 1; i >= 0; i--) {
    if (!mask[i]) continue;
    final c = src[i];
    if (c == ')' || c == ']' || c == '}') {
      depth++;
    } else if (c == '(' || c == '[' || c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      // An unmatched opener encloses [offset].
      final windowStart = i - 120 < 0 ? 0 : i - 120;
      final before = src.substring(windowStart, i);
      final m = constBefore.firstMatch(before);
      if (m != null) {
        final kwStart = windowStart + m.start;
        out.add((kwStart, kwStart + 5));
      }
      if (c == '{') {
        // Function bodies / blocks end const contexts.
        final prefix = src.substring(windowStart, i).trimRight();
        if (prefix.endsWith(')') ||
            prefix.endsWith('=>') ||
            prefix.endsWith('async') ||
            prefix.endsWith('else') ||
            prefix.endsWith('try')) {
          break;
        }
      }
    } else if (c == ';') {
      break;
    }
  }
  return out;
}
