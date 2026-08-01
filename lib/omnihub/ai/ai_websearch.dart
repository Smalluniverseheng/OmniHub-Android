/// OmniHub 独立联网搜索 API
///
/// 支持 Tavily / Brave / Serper 三家主流搜索 API。
/// 在 + 面板「联网搜索」里配置 provider + Key 后，
/// 对话发送前自动检索并把结果注入上下文（替代厂商内置搜索）。
library ai_websearch;

import 'package:dio/dio.dart';
import 'package:venera/foundation/appdata.dart';

class AiWebSearchResult {
  final String title;
  final String url;
  final String snippet;
  const AiWebSearchResult(this.title, this.url, this.snippet);
}

class AiWebSearch {
  AiWebSearch._();

  /// 支持的搜索 API：slug → (名称, Key 申请地址)
  static const providers = <String, (String, String)>{
    'tavily': ('Tavily', 'https://app.tavily.com/home'),
    'brave': ('Brave Search', 'https://brave.com/search/api/'),
    'serper': ('Serper (Google)', 'https://serper.dev/'),
  };

  static String get provider =>
      appdata.settings['aiSearchProvider']?.toString() ?? 'builtin';

  static String get apiKey =>
      appdata.settings['aiSearchKey']?.toString() ?? '';

  /// 是否配置了独立搜索 API
  static bool get configured => provider != 'builtin' && apiKey.isNotEmpty;

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// 执行搜索，返回结果列表；失败返回空表
  static Future<List<AiWebSearchResult>> search(String query,
      {int maxResults = 5}) async {
    if (!configured || query.trim().isEmpty) return const [];
    try {
      switch (provider) {
        case 'tavily':
          final res = await _dio.post(
            'https://api.tavily.com/search',
            data: {
              'api_key': apiKey,
              'query': query,
              'max_results': maxResults,
            },
          );
          return ((res.data['results'] as List?) ?? [])
              .map((e) => AiWebSearchResult(
                    (e['title'] ?? '').toString(),
                    (e['url'] ?? '').toString(),
                    (e['content'] ?? '').toString(),
                  ))
              .toList();
        case 'brave':
          final res = await _dio.get(
            'https://api.search.brave.com/res/v1/web/search',
            queryParameters: {'q': query, 'count': maxResults},
            options: Options(headers: {
              'Accept': 'application/json',
              'X-Subscription-Token': apiKey,
            }),
          );
          return ((res.data['web']?['results'] as List?) ?? [])
              .map((e) => AiWebSearchResult(
                    (e['title'] ?? '').toString(),
                    (e['url'] ?? '').toString(),
                    (e['description'] ?? '').toString(),
                  ))
              .toList();
        case 'serper':
          final res = await _dio.post(
            'https://google.serper.dev/search',
            data: {'q': query, 'num': maxResults},
            options: Options(headers: {'X-API-KEY': apiKey}),
          );
          return ((res.data['organic'] as List?) ?? [])
              .map((e) => AiWebSearchResult(
                    (e['title'] ?? '').toString(),
                    (e['link'] ?? '').toString(),
                    (e['snippet'] ?? '').toString(),
                  ))
              .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 把搜索结果整理成注入上下文的文本
  static String digest(List<AiWebSearchResult> results) {
    final buf = StringBuffer('以下是联网搜索到的最新资料，请结合回答：\n');
    var i = 1;
    for (final r in results) {
      buf.writeln('[$i] ${r.title}\n${r.snippet}\n来源: ${r.url}\n');
      i++;
    }
    return buf.toString();
  }
}
