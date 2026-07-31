/// OmniHub AI 请求层
///
/// App 端用 dio 直连用户自己的 API（BYOK），支持三种格式的流式输出：
/// openai（SSE）、anthropic（SSE）、google（streamGenerateContent SSE）。
library ai_api;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'ai_providers.dart';

class AiMessage {
  final String role; // system | user | assistant
  final String content;

  const AiMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory AiMessage.fromJson(Map<String, dynamic> j) =>
      AiMessage(j['role'] as String? ?? 'user', j['content'] as String? ?? '');
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
  }) async {
    final base =
        (provider.custom && (customBase?.isNotEmpty ?? false))
            ? customBase!
            : provider.base;
    if (base.isEmpty) {
      throw AiApiException('未配置 API 地址（自定义厂商需填写 Base URL）');
    }
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
      final res = await _dio.post<ResponseBody>(
        p.chatUrl(model, apiKey),
        data: {
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': true,
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
    await for (final chunk in stream.transform(utf8.decoder)) {
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
        final body = await data.stream.transform(utf8.decoder).join();
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
