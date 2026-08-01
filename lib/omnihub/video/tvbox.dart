/// OmniHub 视频源（TVBox 接口格式）
///
/// 支持 TVBox 配置接口 JSON（sites[] 中 type 0/1/2 的苹果 CMS/maccms 站点）：
/// - 导入：SourceDetect 识别 'tvbox' 后调用 TvboxSourceManager.importConfig
/// - 搜索：GET {api}?ac=videolist&wd=关键词
/// - 分类/首页：GET {api}?ac=videolist&t=分类ID&pg=页码 / ?ac=detail&pg=页码
/// - 详情：GET {api}?ac=detail&ids={vod_id}
/// 播放地址取 vod_play_url（"集名$URL#..." 格式），一般为 m3u8/mp4。
library tvbox;

import 'package:venera/omnihub/sync/user_data_sync.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class TvboxSite {
  final String key;
  final String name;
  final int type;
  final String api;
  final String? group;
  bool enabled;

  TvboxSite({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.group,
    this.enabled = true,
  });

  /// 仅 type 0/1/2（maccms xml/json）可直接解析，3=spider 4=drpy 暂不支持
  bool get supported => type <= 2 && api.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'type': type,
        'api': api,
        'group': group,
        'enabled': enabled,
      };

  factory TvboxSite.fromJson(Map<String, dynamic> j) => TvboxSite(
        key: '${j['key'] ?? j['name'] ?? ''}',
        name: '${j['name'] ?? ''}',
        type: (j['type'] as num?)?.toInt() ?? 0,
        api: '${j['api'] ?? j['url'] ?? ''}',
        group: j['group']?.toString(),
        enabled: j['enabled'] != false,
      );
}

class VideoItem {
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final TvboxSite site;

  const VideoItem({
    required this.id,
    required this.name,
    required this.pic,
    required this.remarks,
    required this.site,
  });
}

class VideoCategory {
  final String id;
  final String name;
  const VideoCategory(this.id, this.name);
}

class VideoDetail {
  final VideoItem item;
  final String intro;
  final List<String> playFrom;

  /// playFrom[i] 对应的剧集列表 [(集名, 播放地址)]
  final List<List<(String, String)>> episodes;

  const VideoDetail({
    required this.item,
    required this.intro,
    required this.playFrom,
    required this.episodes,
  });
}

class TvboxSourceManager {
  TvboxSourceManager._();
  static final TvboxSourceManager instance = TvboxSourceManager._();

  final List<TvboxSite> sites = [];
  bool _loaded = false;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/omnihub_tvbox.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) {
        sites
          ..clear()
          ..addAll(j.map(
              (e) => TvboxSite.fromJson((e as Map).cast<String, dynamic>())));
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode(sites.map((e) => e.toJson()).toList()));
    UserDataSync.scheduleSourcesSync();
  }

  List<TvboxSite> get enabledSources =>
      sites.where((s) => s.enabled && s.supported).toList();

  /// 导入 TVBox 配置 JSON（单个接口或合集），返回 (成功数, 跳过数)
  Future<(int, int)> importConfig(dynamic config) async {
    await load();
    var ok = 0, skip = 0;
    void importOne(dynamic cfg) {
      if (cfg is! Map) return;
      final list = cfg['sites'];
      if (list is! List) return;
      for (final raw in list) {
        if (raw is! Map) continue;
        final site = TvboxSite.fromJson(raw.cast<String, dynamic>());
        if (!site.supported || site.name.isEmpty) {
          skip++;
          continue;
        }
        final idx = sites.indexWhere((s) => s.key == site.key);
        if (idx >= 0) {
          sites[idx] = site;
        } else {
          sites.add(site);
        }
        ok++;
      }
    }

    if (config is List) {
      for (final c in config) {
        importOne(c);
      }
    } else {
      importOne(config);
    }
    await save();
    return (ok, skip);
  }

  Future<void> remove(String key) async {
    sites.removeWhere((s) => s.key == key);
    await save();
  }

  Future<void> setEnabled(String key, bool enabled) async {
    for (final s in sites) {
      if (s.key == key) {
        s.enabled = enabled;
        break;
      }
    }
    await save();
  }
}

/// 苹果 CMS（maccms）JSON API 客户端
class TvboxApi {
  TvboxApi._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));

  static Future<Map<String, dynamic>> _get(
      TvboxSite site, Map<String, dynamic> params) async {
    final res = await _dio.get(site.api, queryParameters: params);
    dynamic data = res.data;
    if (data is String) data = jsonDecode(data);
    return (data as Map).cast<String, dynamic>();
  }

  static List<VideoItem> _parseList(TvboxSite site, Map<String, dynamic> j) {
    final list = j['list'];
    if (list is! List) return [];
    return [
      for (final v in list)
        if (v is Map)
          VideoItem(
            id: '${v['vod_id'] ?? ''}',
            name: '${v['vod_name'] ?? ''}',
            pic: '${v['vod_pic'] ?? ''}',
            remarks: '${v['vod_remarks'] ?? ''}',
            site: site,
          ),
    ];
  }

  /// 搜索
  static Future<List<VideoItem>> search(TvboxSite site, String keyword) async {
    final j = await _get(site, {'ac': 'videolist', 'wd': keyword});
    return _parseList(site, j);
  }

  /// 分类列表
  static Future<List<VideoCategory>> categories(TvboxSite site) async {
    final j = await _get(site, {'ac': 'detail'});
    final cls = j['class'];
    if (cls is! List) return [];
    return [
      for (final c in cls)
        if (c is Map)
          VideoCategory('${c['type_id'] ?? ''}', '${c['type_name'] ?? ''}'),
    ];
  }

  /// 按分类/首页翻页
  static Future<List<VideoItem>> listByCategory(TvboxSite site,
      {String? typeId, int page = 1}) async {
    final params = <String, dynamic>{'ac': 'videolist', 'pg': page};
    if (typeId != null && typeId.isNotEmpty) params['t'] = typeId;
    final j = await _get(site, params);
    return _parseList(site, j);
  }

  /// 详情（含播放地址）
  static Future<VideoDetail> detail(TvboxSite site, VideoItem item) async {
    final j = await _get(site, {'ac': 'detail', 'ids': item.id});
    final list = j['list'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      throw Exception('未获取到视频详情');
    }
    final v = list.first as Map;
    final froms = '${v['vod_play_from'] ?? ''}'.split('\$\$\$');
    final urls = '${v['vod_play_url'] ?? ''}'.split('\$\$\$');
    final episodes = <List<(String, String)>>[];
    for (var i = 0; i < urls.length; i++) {
      final eps = <(String, String)>[];
      for (final seg in urls[i].split('#')) {
        final parts = seg.split('\$');
        if (parts.length == 2 && parts[1].isNotEmpty) {
          eps.add((parts[0], parts[1]));
        } else if (parts.length == 1 && parts[0].startsWith('http')) {
          eps.add(('播放', parts[0]));
        }
      }
      episodes.add(eps);
    }
    while (froms.length < episodes.length) {
      froms.add('线路${froms.length + 1}');
    }
    return VideoDetail(
      item: item,
      intro:
          '${v['vod_content'] ?? ''}'.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
      playFrom: froms.take(episodes.length).toList(),
      episodes: episodes,
    );
  }
}
