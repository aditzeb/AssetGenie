import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';

import '../common/context.dart';
import '../prompts/project_prompts.dart';
import '../resources/project_resources.dart';
import '../tools/app_harness.dart';
import '../tools/audit_accessibility.dart';
import '../tools/audit_health.dart';
import '../tools/audit_localization.dart';
import '../tools/audit_variants.dart';
import '../tools/extract_strings.dart';
import '../tools/generate_constants.dart';
import '../tools/optimize_images.dart';
import '../tools/sync_localization.dart';
import '../tools/translate_localization.dart';

/// The AssetGenie Model Context Protocol (MCP) server.
base class AssetGenieServer extends MCPServer
    with
        LoggingSupport,
        RootsTrackingSupport,
        ElicitationRequestSupport,
        ResourcesSupport,
        PromptsSupport,
        ToolsSupport
    implements ToolContext {
  AssetGenieServer.fromStreamChannel(
    super.channel, {
    super.protocolLogSink,
  }) : super.fromStreamChannel(
          implementation: Implementation(
            name: 'AssetGenie',
            version: '1.1.0',
            title: 'AssetGenie - Flutter Asset & Localization Engine',
          ),
          instructions:
              'AssetGenie provides expert-grade tools, resources, and workflows to audit, '
              'compress, localize, and inspect assets and translation files for Flutter projects.',
        );

  /// Resolves the primary active Flutter project directory:
  /// uses the first client root if available, or falls back to Directory.current.path.
  String get activeProjectPath {
    try {
      final r = _currentRoots;
      if (r != null && r.isNotEmpty) {
        final uri = Uri.parse(r.first.uri);
        if (uri.hasScheme && uri.scheme == 'file') {
          return uri.toFilePath();
        }
        return r.first.uri;
      }
    } catch (_) {}
    return Directory.current.path;
  }

  List<Root>? _currentRoots;

  @override
  Future<void> updateRoots() async {
    await super.updateRoots();
    try {
      _currentRoots = await roots;
    } catch (_) {}
  }

  // --- ToolContext implementation ---

  @override
  bool get canElicit => supportsElicitation;

  @override
  bool get canSample => clientCapabilities.sampling != null;

  @override
  Future<bool> confirm(String message) async {
    if (!canElicit) return true;
    try {
      final result = await elicit(
        ElicitRequest.form(
          message: message,
          requestedSchema: ObjectSchema(
            properties: {
              'confirm': BooleanSchema(
                description: 'Accept (true) or decline (false) this action.',
              ),
            },
            required: ['confirm'],
          ),
        ),
      );
      if (result.action != ElicitationAction.accept) return false;
      final val = result.content?['confirm'];
      return val is bool ? val : true;
    } catch (e) {
      toolLog('Elicitation failed: $e');
      return true;
    }
  }

  @override
  Future<String?> sample({
    required String systemPrompt,
    required String prompt,
    int maxTokens = 4096,
  }) async {
    if (!canSample) return null;
    try {
      final result = await createMessage(
        CreateMessageRequest(
          systemPrompt: systemPrompt,
          messages: [
            SamplingMessage(
              role: Role.user,
              content: TextContent(text: prompt),
            ),
          ],
          maxTokens: maxTokens,
        ),
      );
      final c = result.content;
      if (c.isText) return (c as TextContent).text;
    } catch (e) {
      toolLog('Sampling request failed: $e');
    }
    return null;
  }

  @override
  void toolLog(String message) {
    try {
      log(LoggingLevel.info, message);
    } catch (_) {
      stderr.writeln('[AssetGenie] $message');
    }
  }

  /// Registers all AssetGenie tools, resources, and prompt workflows.
  void registerAll() {
    final allTools = <ToolSpec>[
      auditHealthSpec,
      auditLocalizationSpec,
      syncLocalizationSpec,
      generateConstantsSpec,
      optimizeImagesSpec,
      extractStringsSpec,
      auditVariantsSpec,
      auditAccessibilitySpec,
      translateLocalizationSpec,
      appHarnessSpec,
    ];

    for (final spec in allTools) {
      registerTool(
        spec.tool,
        (CallToolRequest req) async {
          final args = req.arguments ?? const <String, Object?>{};
          // If project_path was omitted, default to activeProjectPath
          final effectiveArgs = Map<String, Object?>.from(args);
          if (!effectiveArgs.containsKey('project_path') ||
              effectiveArgs['project_path'] == null ||
              (effectiveArgs['project_path'] is String &&
                  (effectiveArgs['project_path'] as String).isEmpty)) {
            effectiveArgs['project_path'] = activeProjectPath;
          }
          return await spec.handler(effectiveArgs, this);
        },
        validateArguments: false,
      );
    }

    // Register Resources
    registerProjectResources(this, getActiveProjectPath: () => activeProjectPath);

    // Register Prompts
    registerProjectPrompts(this);
  }

  /// Starts an AssetGenie MCP server instance over standard I/O (stdio).
  static AssetGenieServer startStdio() {
    final channel = stdioChannel(input: stdin, output: stdout);
    final server = AssetGenieServer.fromStreamChannel(channel);
    server.registerAll();
    return server;
  }
}
