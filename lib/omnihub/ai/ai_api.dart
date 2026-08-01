/// OmniHub AI 请求层
///
/// App 端用 dio 直连用户自己的 API（BYOK），支持三种格式的流式输出：
/// openai（SSE）、anthropic（SSE）、google（streamGenerateContent SSE）。
library ai_api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'ai_providers.dart';

class AiMessage {
  final String role; // system | user | assistant
  final String content;

  /// 附件：[{type: image|file, name, path}]，path 为本地绝对路径
  final List<Map<String, String>> attachments;

  /// 内容类型：text（默认）| image（AI 生图结果）| video（AI 生视频结果）
  final String kind;

  const AiMessage(this.role, this.content,
      {this.attachments = const [], this.kind = 'text'});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (attachments.isNotEmpty) 'attachments': attachments,
        if (kind != 'text') 'kind': kind,
      };

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        j['role'] as String? ?? 'user',
        j['content'] as String? ?? '',
        attachments: ((j['attachments'] as List?) ?? [])
            .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
            .toList(),
        kind: j['kind'] as String? ?? 'text',
      );
}

class AiApiException implements Exception {
  final String message;
  final int? statusCode;

  AiApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode != null ? 'HTTP $statusCode: $message' : message;
}

class AiApi {
  AiApi._();

  static bool _webSearchEnabled = false;

  /// 把消息转换为 OpenAI 兼容的 content（有图片附件时为多模态数组）
  static Future<Map<String, dynamic>> toOpenAiPayload(AiMessage m,
      {int maxImageBytes = 4 * 1024 * 1024}) async {
    final images = m.attachments.where((a) => a['type'] == 'image').toList();
    final files = m.attachments.where((a) => a['type'] == 'file').toList();
    if (images.isEmpty && files.isEmpty) return m.toJson();
    final parts = <Map<String, dynamic>>[];
    var text = m.content;
    for (final f in files) {
      try {
        final content = await File(f['path']!).readAsString();
        final name = f['name'] ?? 'file';
        text += '\n\n[附件 $name]\n$content';
      } catch (_) {
        text += '\n\n[附件 ${f['name'] ?? 'file'} 读取失败]';
      }
    }
    if (images.isEmpty) {
      return {'role': m.role, 'content': text};
    }
    if (text.isNotEmpty) parts.add({'type': 'text', 'text': text});
    for (final img in images) {
      try {
        final bytes = await File(img['path']!).readAsBytes();
        if (bytes.length > maxImageBytes) {
          parts.add({
            'type': 'text',
            'text': '[图片 ${img['name'] ?? ''} 超过大小限制，未上传]'
          });
          continue;
        }
        final ext = (img['name'] ?? 'jpg').split('.').last.toLowerCase();
        final mime = ext == 'png'
            ? 'image/png'
            : ext == 'gif'
                ? 'image/gif'
                : ext == 'webp'
                    ? 'image/webp'
                    : 'image/jpeg';
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:$mime;base64,${base64Encode(bytes)}'
          },
        });
      } catch (_) {}
    }
    return {'role': m.role, 'content': parts};
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 3),
  ));

  /// 流式对话。每收到一个 token 调用 [onToken]；出错抛 [AiApiException]。
  static Future<void> chatStream({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required List<AiMessage> messages,
    required void Function(String token) onToken,
    String? customBase,
    CancelToken? cancelToken,

    /// 开启厂商联网搜索（目前适配 openai 兼容格式的 enable_search 字段）
    bool webSearch = false,
  }) async {
    final base =
        (provider.custom && (customBase?.isNotEmpty ?? false))
            ? customBase!
            : provider.base;
    if (base.isEmpty) {
      throw AiApiException('未配置 API 地址（自定义厂商需填写 Base URL）');
    }
    _webSearchEnabled = webSearch;
    final effective = AiProvider(
      name: provider.name,
      format: provider.format,
      base: base,
      keySlug: provider.keySlug,
      color: provider.color,
      models: provider.models,
      custom: provider.custom,
    );
    switch (provider.format) {
      case 'anthropic':
        await _anthropicStream(effective, apiKey, model, messages, onToken,
            cancelToken);
        break;
      case 'google':
        await _googleStream(
            effective, apiKey, model, messages, onToken, cancelToken);
        break;
      default:
        await _openaiStream(
            effective, apiKey, model, messages, onToken, cancelToken);
    }
  }

  /// 测试连接：拉取模型列表。返回可用模型（最多前 20 个）。
  /// anthropic 无公开 models 端点，发一条极短消息验证。
  static Future<List<String>> validateKey(
      AiProvider provider, String apiKey,
      {String? customBase}) async {
    final base =
        (provider.custom && (customBase?.isNotEmpty ?? false))
            ? customBase!
            : provider.base;
    if (base.isEmpty) throw AiApiException('未配置 API 地址');
    try {
      if (provider.format == 'anthropic') {
        await _dio.post(
          '$base/v1/messages',
          data: {
            'model': provider.models.isNotEmpty
                ? provider.models.first
                : 'claude-haiku-4-5',
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ],
          },
          options: Options(headers: provider.headers(apiKey)),
        );
        return provider.models;
      }
      if (provider.format == 'google') {
        final res = await _dio.get(
          '$base/v1beta/models',
          queryParameters: {'key': apiKey, 'pageSize': 20},
        );
        final list = (res.data['models'] as List? ?? [])
            .map((e) => (e['name'] as String? ?? '').replaceFirst('models/', ''))
            .where((e) => e.isNotEmpty)
            .toList();
        return list;
      }
      final res = await _dio.get(
        '$base/v1/models',
        options: Options(headers: provider.headers(apiKey)),
      );
      final list = (res.data['data'] as List? ?? [])
          .map((e) => e['id'] as String? ?? '')
          .where((e) => e.isNotEmpty)
          .take(20)
          .toList();
      return list;
    } on DioException catch (e) {
      throw AiApiException(_dioErrorText(e), statusCode: e.response?.statusCode);
    }
  }

  // ---------------- openai 兼容 ----------------

  static Future<void> _openaiStream(
    AiProvider p,
    String apiKey,
    String model,
    List<AiMessage> messages,
    void Function(String) onToken,
    CancelToken? cancelToken,
  ) async {
    try {
      final payload = <Map<String, dynamic>>[];
      for (final m in messages) {
        payload.add(await toOpenAiPayload(m));
      }
      final res = await _dio.post<ResponseBody>(
        p.chatUrl(model, apiKey),
        data: {
          'model': model,
          'messages': payload,
          'stream': true,
          // 联网搜索：通义/智谱/DeepSeek 等 openai 兼容厂商识别此字段
          if (_webSearchEnabled) 'enable_search': true,
          if (_webSearchEnabled) 'web_search_options': {'search_context_size': 'medium'},
        },
        options: Options(
          headers: p.headers(apiKey),
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      await _consumeSse(res.data!.stream, (data) {
        if (data == '[DONE]') return;
        try {
          final j = jsonDecode(data);
          final choices = j['choices'] as List?;
          if (choices == null || choices.isEmpty) return;
          final delta = choices[0]['delta'];
          final content = delta?['content'];
          if (content is String && content.isNotEmpty) onToken(content);
        } catch (_) {}
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw AiApiException(await _sseErrorText(e),
          statusCode: e.response?.statusCode);
    }
  }

  // ---------------- anthropic ----------------

  static Future<void> _anthropicStream(
    AiProvider p,
    String apiKey,
    String model,
    List<AiMessage> messages,
    void Function(String) onToken,
    CancelToken? cancelToken,
  ) async {
    // anthropic：system 单独成字段
    String? system;
    final msgs = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.role == 'system') {
        system = (system == null) ? m.content : '$system\n${m.content}';
      } else {
        msgs.add(m.toJson());
      }
    }
    try {
      final res = await _dio.post<ResponseBody>(
        p.chatUrl(model, apiKey),
        data: {
          'model': model,
          'max_tokens': 4096,
          if (system != null) 'system': system,
          'messages': msgs,
          'stream': true,
        },
        options: Options(
          headers: p.headers(apiKey),
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      await _consumeSse(res.data!.stream, (data) {
        try {
          final j = jsonDecode(data);
          if (j['type'] == 'content_block_delta') {
            final text = j['delta']?['text'];
            if (text is String && text.isNotEmpty) onToken(text);
          }
        } catch (_) {}
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw AiApiException(await _sseErrorText(e),
          statusCode: e.response?.statusCode);
    }
  }

  // ---------------- google ----------------

  static Future<void> _googleStream(
    AiProvider p,
    String apiKey,
    String model,
    List<AiMessage> messages,
    void Function(String) onToken,
    CancelToken? cancelToken,
  ) async {
    String? system;
    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.role == 'system') {
        system = (system == null) ? m.content : '$system\n${m.content}';
      } else {
        contents.add({
          'role': m.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': m.content}
          ],
        });
      }
    }
    try {
      final res = await _dio.post<ResponseBody>(
        p.chatUrl(model, apiKey),
        data: {
          if (system != null)
            'systemInstruction': {
              'parts': [
                {'text': system}
              ]
            },
          'contents': contents,
        },
        options: Options(
          headers: p.headers(apiKey),
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      await _consumeSse(res.data!.stream, (data) {
        try {
          final j = jsonDecode(data);
          final candidates = j['candidates'] as List?;
          if (candidates == null || candidates.isEmpty) return;
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts == null) return;
          for (final part in parts) {
            final text = part['text'];
            if (text is String && text.isNotEmpty) onToken(text);
          }
        } catch (_) {}
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw AiApiException(await _sseErrorText(e),
          statusCode: e.response?.statusCode);
    }
  }

  // ---------------- SSE 工具 ----------------

  /// 逐行读取 SSE 流，回调每个 data: 载荷
  static Future<void> _consumeSse(
    Stream<List<int>> stream,
    void Function(String data) onData,
  ) async {
    final buffer = StringBuffer();
    // utf8.decoder 泛型是 List<int>，Stream<Uint8List> 需先 cast 才能 transform
    await for (final chunk in stream.cast<List<int>>().transform(utf8.decoder)) {
      buffer.write(chunk);
      buffer.write(chunk);
      final text = buffer.toString();
      // SSE 事件以空行分隔；按行处理，保留未完成行
      var lastEnd = 0;
      while (true) {
        final idx = text.indexOf('\n', lastEnd);
        if (idx == -1) break;
        final line = text.substring(lastEnd, idx).trim();
        lastEnd = idx + 1;
        if (line.startsWith('data:')) {
          onData(line.substring(5).trim());
        }
      }
      final remaining = text.substring(lastEnd);
      buffer
        ..clear()
        ..write(remaining);
    }
  }

  static String _dioErrorText(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] != null) return err['message'].toString();
      if (data['message'] != null) return data['message'].toString();
    }
    return e.message ?? '网络请求失败';
  }

  /// 流式请求的错误响应体是 stream，需要读出来
  static Future<String> _sseErrorText(DioException e) async {
    try {
      final data = e.response?.data;
      if (data is ResponseBody) {
        final body =
            await utf8.decoder.bind(data.stream.cast<List<int>>()).join();
        final j = jsonDecode(body);
        final err = j['error'];
        if (err is Map && err['message'] != null) {
          return err['message'].toString();
        }
        return body.length > 200 ? body.substring(0, 200) : body;
      }
    } catch (_) {}
    return _dioErrorText(e);
  }
}
