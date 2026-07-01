import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mcp_server/mcp_server.dart';

class VmServiceClient {
  final String wsUri;
  WebSocket? _ws;
  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};
  StreamSubscription? _subscription;
  int _nextId = 1;
  void Function(String)? onMessage;

  VmServiceClient(this.wsUri);

  Future<void> connect() async {
    _ws = await WebSocket.connect(wsUri).timeout(const Duration(seconds: 5));
    _subscription = _ws!.listen((data) {
      final msg = data as String;
      onMessage?.call(msg);
      try {
        final parsed = jsonDecode(msg) as Map<String, dynamic>;
        final id = parsed['id']?.toString();
        if (id != null && _pendingRequests.containsKey(id)) {
          _pendingRequests[id]!.complete(parsed);
          _pendingRequests.remove(id);
        }
      } catch (_) {
        // Ignore unparseable frames
      }
    });
  }

  Future<Map<String, dynamic>> callMethod(String method,
      [Map<String, dynamic>? params]) async {
    if (_ws == null) throw StateError('Not connected');
    final id = (_nextId++).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final payload = {
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
      'id': id,
    };

    _ws!.add(jsonEncode(payload));
    return completer.future.timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    await _subscription?.cancel();
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      await _ws!.close();
    }
  }
}

String resolveWsUri(String uriStr) {
  var resolved = uriStr.trim();
  if (resolved.startsWith('http://')) {
    resolved = 'ws://${resolved.substring(7)}';
  } else if (resolved.startsWith('https://')) {
    resolved = 'wss://${resolved.substring(8)}';
  }
  if (!resolved.endsWith('/ws') && !resolved.endsWith('/ws/')) {
    if (resolved.endsWith('/')) {
      resolved = '${resolved}ws';
    } else {
      resolved = '$resolved/ws';
    }
  }
  return resolved;
}

Future<CallToolResult> appHarness(Map<String, dynamic> arguments) async {
  final vmServiceUri = arguments['vm_service_uri'] as String?;
  if (vmServiceUri == null || vmServiceUri.isEmpty) {
    return CallToolResult(
      [
        TextContent(
            text: 'Error: "vm_service_uri" is required and cannot be empty.')
      ],
      isError: true,
    );
  }

  final action = arguments['action'] as String?;
  if (action == null || action.isEmpty) {
    return CallToolResult(
      [TextContent(text: 'Error: "action" is required and cannot be empty.')],
      isError: true,
    );
  }

  final wsUri = resolveWsUri(vmServiceUri);
  final client = VmServiceClient(wsUri);

  try {
    await client.connect();

    if (action == 'get_widget_tree') {
      final response = await client.callMethod(
        'ext.flutter.inspector.getRootWidgetSummaryTree',
        {'objectGroup': 'assetgenie_harness'},
      );

      if (response.containsKey('error')) {
        throw Exception(
            response['error']['message'] ?? 'Failed to retrieve widget tree.');
      }

      final result = response['result'];
      Map<String, dynamic> treeData;
      if (result is Map && result.containsKey('result')) {
        final inner = result['result'];
        treeData = inner is String ? jsonDecode(inner) : inner;
      } else if (result is String) {
        treeData = jsonDecode(result);
      } else if (result is Map<String, dynamic>) {
        treeData = result;
      } else {
        throw Exception('Unexpected response payload structure.');
      }

      final encoder = const JsonEncoder.withIndent('  ');
      return CallToolResult([
        TextContent(
          text:
              '# Flutter Widget Summary Tree\n\n```json\n${encoder.convert(treeData)}\n```',
        )
      ]);
    } else if (action == 'capture_screenshot') {
      // 1. Get tree to find root value ID
      final treeResponse = await client.callMethod(
        'ext.flutter.inspector.getRootWidgetSummaryTree',
        {'objectGroup': 'assetgenie_harness'},
      );

      String rootId = 'inspector-0';
      if (!treeResponse.containsKey('error')) {
        final result = treeResponse['result'];
        Map<String, dynamic>? treeData;
        try {
          if (result is Map && result.containsKey('result')) {
            final inner = result['result'];
            treeData = inner is String ? jsonDecode(inner) : inner;
          } else if (result is String) {
            treeData = jsonDecode(result);
          } else if (result is Map<String, dynamic>) {
            treeData = result;
          }
        } catch (_) {}
        if (treeData != null) {
          rootId = treeData['valueId'] as String? ??
              treeData['id'] as String? ??
              'inspector-0';
        }
      }

      // 2. Call screenshot on root widget
      final response = await client.callMethod(
        'ext.flutter.inspector.screenshot',
        {
          'id': rootId,
          'objectGroup': 'assetgenie_harness',
        },
      );

      if (response.containsKey('error')) {
        throw Exception(response['error']['message'] ??
            'Failed to capture app screenshot.');
      }

      final result = response['result'];
      String? base64Data;
      if (result is Map && result.containsKey('result')) {
        base64Data = result['result'] as String?;
      } else if (result is String) {
        base64Data = result;
      } else if (result is Map && result.containsKey('screenshot')) {
        base64Data = result['screenshot'] as String?;
      }

      if (base64Data == null || base64Data.isEmpty) {
        throw Exception('Screenshot result did not contain valid image data.');
      }

      // Clean up base64 whitespace if any
      base64Data = base64Data.trim().replaceAll('\n', '').replaceAll('\r', '');

      return CallToolResult([
        ImageContent.fromBase64(
          base64Data: base64Data,
          mimeType: 'image/png',
        )
      ]);
    } else if (action == 'get_logs') {
      final logBuffer = StringBuffer();

      client.onMessage = (data) {
        try {
          final parsed = jsonDecode(data) as Map<String, dynamic>;
          final method = parsed['method'] as String?;
          if (method == 'streamNotify') {
            final params = parsed['params'] as Map<String, dynamic>?;
            final event = params?['event'] as Map<String, dynamic>?;
            final streamId = params?['streamId'] as String?;
            if (event != null) {
              final timestamp = DateTime.fromMillisecondsSinceEpoch(
                event['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
              );
              final timeStr =
                  "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
              if (streamId == 'Stdout' || streamId == 'Stderr') {
                final bytesBase64 = event['bytes'] as String?;
                if (bytesBase64 != null) {
                  final decoded = utf8.decode(base64.decode(bytesBase64));
                  logBuffer.write('[$timeStr] [$streamId] $decoded');
                }
              } else if (streamId == 'Logging') {
                final logRecord = event['logRecord'] as Map<String, dynamic>?;
                var message =
                    logRecord?['message']?['valueAsString'] as String? ??
                        logRecord?['message'] as String?;
                if (message != null) {
                  logBuffer.writeln('[$timeStr] [Log] $message');
                }
              }
            }
          }
        } catch (_) {}
      };

      // Subscribe to logging streams
      try {
        await client.callMethod('streamListen', {'streamId': 'Stdout'});
      } catch (_) {}
      try {
        await client.callMethod('streamListen', {'streamId': 'Stderr'});
      } catch (_) {}
      try {
        await client.callMethod('streamListen', {'streamId': 'Logging'});
      } catch (_) {}

      // Capture logs for 1.5 seconds
      await Future.delayed(const Duration(milliseconds: 1500));
      client.onMessage = null;

      final logsText = logBuffer.toString();
      return CallToolResult([
        TextContent(
          text: logsText.isEmpty
              ? 'No new runtime logs were intercepted during the capture window.'
              : '# Captured Flutter App Logs\n\n```\n$logsText\n```',
        )
      ]);
    } else {
      return CallToolResult(
        [
          TextContent(
              text:
                  'Error: Unknown action "$action". Supported actions are: "get_widget_tree", "capture_screenshot", "get_logs".')
        ],
        isError: true,
      );
    }
  } catch (e) {
    return CallToolResult(
      [TextContent(text: 'Error interacting with app: ${e.toString()}')],
      isError: true,
    );
  } finally {
    await client.close();
  }
}
