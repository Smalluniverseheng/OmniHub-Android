/// OmniHub AI 图像/视频生成请求层
///
/// 图像：OpenAI 兼容 POST /images/generations（OpenAI、火山 ark、硅基流动等
/// 聚合平台均兼容；google 走 generateImage）。
/// 视频：任务制 —— 火山 ark /contents/generations/tasks（Seedance 系列），
/// 其余厂商返回「暂未适配」提示，结构留好方便后续扩展。
library ai_media_api;

import 'dart:async';

import 'package:dio/dio.dart';

import 'ai_api.dart';
import 'ai_providers.dart';

class AiMediaResult {
  /// 图像 url 列表或视频 url
  final List<String> urls;

  /// base64 图像（无 url 时）
  final List<String> b64Images;

  const AiMediaResult({this.urls = const [], this.b64Images = const []});
}

class AiMediaApi {
  AiMediaApi._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 2),
  ));

  static String _base(AiProvider p, String? customBase) =>
      (p.custom && (customBase?.isNotEmpty ?? false)) ? customBase! : p.base;

  // ---------------- 图像生成 ----------------

  /// 返回生成结果；失败抛 AiApiException
  static Future<AiMediaResult> generateImage({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String prompt,
    String? customBase,
    String size = '1024x1024',
  }) async {
    final base = _base(provider, customBase);
    if (base.isEmpty) throw AiApiException('未配置 API 地址');
    try {
      if (provider.format == 'google') {
        return await _googleImage(base, apiKey, model, prompt);
      }
      final res = await _dio.post(
        '$base/v1/images/generations',
        data: {'model': model, 'prompt': prompt, 'n': 1, 'size': size},
        options: Options(headers: provider.headers(apiKey)),
      );
      final data = res.data['data'] as List? ?? [];
      final urls = <String>[];
      final b64 = <String>[];
      for (final item in data) {
        if (item['url'] is String) urls.add(item['url'] as String);
        if (item['b64_json'] is String) b64.add(item['b64_json'] as String);
      }
      if (urls.isEmpty && b64.isEmpty) {
        throw AiApiException('接口未返回图像');
      }
      return AiMediaResult(urls: urls, b64Images: b64);
    } on DioException catch (e) {
      throw AiApiException(_errText(e), statusCode: e.response?.statusCode);
    }
  }

  static Future<AiMediaResult> _googleImage(
      String base, String apiKey, String model, String prompt) async {
    // gemini 图像模型走 generateContent，响应内嵌 inlineData
    final res = await _dio.post(
      '$base/v1beta/models/$model:generateContent?key=$apiKey',
      data: {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {'responseModalities': ['IMAGE']},
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    final b64 = <String>[];
    final candidates = res.data['candidates'] as List? ?? [];
    for (final c in candidates) {
      final parts = c['content']?['parts'] as List? ?? [];
      for (final p in parts) {
        final inline = p['inlineData'] ?? p['inline_data'];
        if (inline is Map && inline['data'] is String) {
          b64.add(inline['data'] as String);
        }
      }
    }
    if (b64.isEmpty) throw AiApiException('接口未返回图像');
    return AiMediaResult(b64Images: b64);
  }

  // ---------------- 视频生成（任务制） ----------------

  /// 提交视频任务，返回任务 id
  static Future<String> createVideoTask({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String prompt,
    String? customBase,
    String ratio = '16:9',
    String duration = '5',
  }) async {
    final base = _base(provider, customBase);
    if (base.isEmpty) throw AiApiException('未配置 API 地址');
    // 火山 ark 内容生成任务（Seedance）
    if (provider.keySlug == 'volcengine' || base.contains('volces.com')) {
      try {
        final res = await _dio.post(
          '$base/contents/generations/tasks',
          data: {
            'model': model,
            'content': [
              {
                'type': 'text',
                'text': '$prompt --ratio $ratio --dur $duration',
              }
            ],
          },
          options: Options(headers: provider.headers(apiKey)),
        );
        final id = res.data['id'] as String?;
        if (id != null && id.isNotEmpty) return id;
        throw AiApiException('未返回任务 id');
      } on DioException catch (e) {
        throw AiApiException(_errText(e), statusCode: e.response?.statusCode);
      }
    }
    throw AiApiException('该厂商的视频生成接口暂未适配，目前支持火山引擎 Seedance 系列');
  }

  /// 轮询视频任务：done 时返回视频 url，pending 返回 null，失败抛异常
  static Future<String?> pollVideoTask({
    required AiProvider provider,
    required String apiKey,
    required String taskId,
    String? customBase,
  }) async {
    final base = _base(provider, customBase);
    try {
      final res = await _dio.get(
        '$base/contents/generations/tasks/$taskId',
        options: Options(headers: provider.headers(apiKey)),
      );
      final status = res.data['status'] as String? ?? '';
      if (status == 'succeeded') {
        final url = res.data['content']?['video_url'] as String?;
        if (url != null && url.isNotEmpty) return url;
        throw AiApiException('任务完成但未返回视频地址');
      }
      if (status == 'failed' || status == 'cancelled') {
        throw AiApiException(
            '视频生成失败：${res.data['error']?['message'] ?? status}');
      }
      return null; // queued / running
    } on DioException catch (e) {
      throw AiApiException(_errText(e), statusCode: e.response?.statusCode);
    }
  }

  static String _errText(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      final err = d['error'];
      if (err is Map && err['message'] != null) return err['message'].toString();
      if (d['message'] != null) return d['message'].toString();
    }
    if (d is String && d.isNotEmpty) {
      return d.length > 200 ? d.substring(0, 200) : d;
    }
    return e.message ?? '网络请求失败';
  }
}

