import 'package:dart_mcp/server.dart';

import '../common/context.dart';
import '../common/dart_scan.dart';
import '../common/project.dart';

final ToolSpec auditAccessibilitySpec = ToolSpec(
  Tool(
    name: 'assetgenie_audit_accessibility',
    title: 'Audit asset and icon accessibility (semantic labels & tooltips)',
    description:
        'Scans Flutter Dart files in lib/ to identify Image, SvgPicture, and IconButton '
        'widgets that lack semanticLabel or tooltip properties, ensuring screen reader '
        '(TalkBack / VoiceOver) compliance.',
    annotations: ToolAnnotations(
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: false,
    ),
    inputSchema: ObjectSchema(
      properties: {
        'project_path': StringSchema(
          description: 'Absolute path to the Flutter project root directory.',
        ),
      },
      required: ['project_path'],
    ),
    outputSchema: ObjectSchema(
      properties: {
        'total_widgets_analyzed': IntegerSchema(),
        'unlabelled_count': IntegerSchema(),
        'issues': ListSchema(
          items: ObjectSchema(
            properties: {
              'file': StringSchema(),
              'line': IntegerSchema(),
              'widget_type': StringSchema(),
              'recommendation': StringSchema(),
            },
          ),
        ),
      },
      required: [
        'total_widgets_analyzed',
        'unlabelled_count',
        'issues',
      ],
    ),
  ),
  auditAccessibilityHandler,
);

class _AccessibilityIssue {
  final String file;
  final int line;
  final String widgetType;
  final String recommendation;

  _AccessibilityIssue({
    required this.file,
    required this.line,
    required this.widgetType,
    required this.recommendation,
  });

  Map<String, Object?> toJson() => {
        'file': file,
        'line': line,
        'widget_type': widgetType,
        'recommendation': recommendation,
      };
}

Future<CallToolResult> auditAccessibilityHandler(
  Map<String, Object?> args,
  ToolContext context,
) async {
  final loaded = FlutterProject.load(args['project_path']);
  if (loaded.error != null) return toolError(loaded.error!);
  final project = loaded.project!;

  final dartFiles = project.dartFiles(excludeGenerated: true);
  final issues = <_AccessibilityIssue>[];
  var totalWidgets = 0;

  final widgetPatterns = [
    (
      pattern: RegExp(r'\bImage\.(?:asset|network|file|memory)\s*\('),
      name: 'Image',
      labelProp: 'semanticLabel',
      recom: 'Add `semanticLabel: ...` for screen readers or `excludeFromSemantics: true` if purely decorative.',
    ),
    (
      pattern: RegExp(r'\bSvgPicture\.(?:asset|network|file|string)\s*\('),
      name: 'SvgPicture',
      labelProp: 'semanticsLabel',
      recom: 'Add `semanticsLabel: ...` to describe the SVG vector asset.',
    ),
    (
      pattern: RegExp(r'\bIconButton\s*\('),
      name: 'IconButton',
      labelProp: 'tooltip',
      recom: 'Add `tooltip: ...` for screen reader announcement and hover tooltips.',
    ),
  ];

  for (final file in dartFiles) {
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      continue;
    }

    final mask = codeMask(content);
    final relPath = project.rel(file.path);

    for (final item in widgetPatterns) {
      for (final match in item.pattern.allMatches(content)) {
        if (!mask[match.start]) continue;
        totalWidgets++;

        final openParen = match.end - 1;
        final closeParen = findClosingParen(content, mask, openParen);
        if (closeParen == -1) continue;

        final argsText = topLevelArgs(content, mask, openParen, closeParen);
        final hasLabel = RegExp('\\b${item.labelProp}\\s*:').hasMatch(argsText) ||
            RegExp(r'\bexcludeFromSemantics\s*:\s*true\b').hasMatch(argsText);

        if (!hasLabel) {
          final line = lineOf(content, match.start);
          issues.add(_AccessibilityIssue(
            file: relPath,
            line: line,
            widgetType: item.name,
            recommendation: item.recom,
          ));
        }
      }
    }
  }

  final report = StringBuffer()
    ..writeln('# AssetGenie Accessibility Audit Report')
    ..writeln('Project: `${project.name}`')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Visual / interactive widgets checked: $totalWidgets')
    ..writeln('- Missing semantic labels / tooltips: ${issues.length}')
    ..writeln();

  if (issues.isNotEmpty) {
    report.writeln('### ⚠️ Unlabelled Visual Elements');
    for (final issue in issues.take(20)) {
      report.writeln(
        '- `${issue.file}:${issue.line}`: **${issue.widgetType}** - ${issue.recommendation}',
      );
    }
    if (issues.length > 20) {
      report.writeln('- ... and ${issues.length - 20} more unlabelled widgets.');
    }
    report.writeln();
  } else {
    report.writeln('### ✅ All scanned images and icon buttons specify accessibility labels!\n');
  }

  final structured = <String, Object?>{
    'total_widgets_analyzed': totalWidgets,
    'unlabelled_count': issues.length,
    'issues': issues.map((i) => i.toJson()).toList(),
  };

  return toolOk(report.toString(), structured);
}

