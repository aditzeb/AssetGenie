import 'dart:async';

import 'package:dart_mcp/server.dart';

/// Capabilities a tool can use from the connected MCP client.
///
/// Tools receive this instead of the server itself, so they can be unit
/// tested with [HeadlessToolContext] or a fake.
abstract interface class ToolContext {
  /// Whether the client supports elicitation (asking the user for input).
  bool get canElicit;

  /// Whether the client supports sampling (running an LLM completion).
  bool get canSample;

  /// Asks the user to confirm a change before it is applied.
  ///
  /// Returns `true` if the user accepted, or if the client does not support
  /// elicitation (the tool call itself was already approved by the client).
  Future<bool> confirm(String message);

  /// Requests an LLM completion from the client. Returns `null` when
  /// sampling is unavailable or fails.
  Future<String?> sample({
    required String systemPrompt,
    required String prompt,
    int maxTokens = 4096,
  });

  /// Sends a log message to the client.
  void toolLog(String message);
}

/// A [ToolContext] for headless use (tests, scripts): no elicitation or
/// sampling, confirmations are auto-accepted.
class HeadlessToolContext implements ToolContext {
  const HeadlessToolContext();

  @override
  bool get canElicit => false;

  @override
  bool get canSample => false;

  @override
  Future<bool> confirm(String message) async => true;

  @override
  Future<String?> sample({
    required String systemPrompt,
    required String prompt,
    int maxTokens = 4096,
  }) async =>
      null;

  @override
  void toolLog(String message) {}
}

/// Builds a successful tool result with a markdown report for the model and
/// a machine-readable [structuredContent] payload matching the tool's
/// `outputSchema`.
CallToolResult toolOk(
  String markdown,
  Map<String, Object?> structuredContent, {
  List<Content> extraContent = const [],
}) =>
    CallToolResult(
      content: [TextContent(text: markdown), ...extraContent],
      structuredContent: structuredContent,
    );

/// Builds an error tool result.
CallToolResult toolError(String message) => CallToolResult(
      content: [TextContent(text: 'Error: $message')],
      isError: true,
    );

/// Returns the text of the first [TextContent] in [result].
String resultText(CallToolResult result) {
  for (final c in result.content) {
    if (c.isText) return (c as TextContent).text;
  }
  return '';
}

/// Signature shared by every AssetGenie tool implementation.
typedef ToolHandler = Future<CallToolResult> Function(
    Map<String, Object?> args, ToolContext context);

/// A tool definition paired with its implementation.
class ToolSpec {
  final Tool tool;
  final ToolHandler handler;

  const ToolSpec(this.tool, this.handler);
}

double roundTo(double value, [int places = 1]) =>
    double.parse(value.toStringAsFixed(places));

bool argBool(Map<String, Object?> args, String key, bool fallback) {
  final v = args[key];
  return v is bool ? v : fallback;
}

List<String>? argStringList(Map<String, Object?> args, String key) {
  final v = args[key];
  if (v is List) return v.whereType<String>().toList();
  if (v is String && v.isNotEmpty) return [v];
  return null;
}

