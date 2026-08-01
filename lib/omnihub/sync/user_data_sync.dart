/// 用户数据云端同步：API 配置与书源
///
/// - 上传方向（防抖 3 秒）：本地变更后整体覆盖云端
///   - user_api_configs：AI 厂商 Key / Base URL / 模型选择
///   - user_sources：小说书源 + 漫画源 + 视频源
/// - 下载方向（登录后调用一次 pullAll）：
///   - 云端有而本地没有的 API Key 自动补齐
///   - 云端有而本地没有的书源自动合并导入
library user_data_sync;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/omnihub/ai/ai_providers.dart' show AiProviders;
import 'package:venera/omnihub/ai/ai_store.dart';
import 'package:venera/omnihub/novel/book_source.dart';
import 'package:venera/omnihub/video/tvbox.dart';

import 'omni_sync.dart';
import 'profile.dart';

class UserDataSync {
  UserDataSync._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static Timer? _srcTimer;
  static Timer? _apiTimer;
  static bool _pushing = false;

  static Map<String, String> _headers(String token) => {
        'apikey': OmniSyncConfig.anonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// 云同步为会员功能：进阶会员(500MB)及以上才开启，普通用户不同步
  static Future<bool> _isMember() async {
    try {
      final p = await OmniProfileService.instance.fetch();
      if (p == null) return false;
      return p.isAdmin ||
          const ['advanced', 'vip', 'svip', 'agent'].contains(p.role);
    } catch (_) {
      return false;
    }
  }

  /* ---------------- 上传：书源 ---------------- */

  /// 本地书源变更后调用（防抖）
  static void scheduleSourcesSync() {
    _srcTimer?.cancel();
    _srcTimer = Timer(const Duration(seconds: 3), pushSources);
  }

  static Future<void> pushSources() async {
    if (_pushing) return;
    final session = OmniSync.instance.session;
    if (session == null) return;
    if (!await _isMember()) return; // 普通用户不同步
    _pushing = true;
    try {
      final rows = <Map<String, dynamic>>[];

      // 1) 小说书源（legado / tauri）
      for (final s in BookSourceManager.instance.sources) {
        rows.add({
          'user_id': session.userId,
          'media_type': s.isTauri ? 'tauri_${s.tauriType}' : 'novel',
          'name': s.bookSourceName,
          'enabled': s.enabled,
          'source_json': s.toJson(),
        });
      }

      // 2) 漫画源（JS 源码随 source_json 一起上传）
      for (final c in ComicSource.all()) {
        String code = '';
        try {
          final f = File(c.filePath);
          if (f.existsSync()) code = f.readAsStringSync();
        } catch (_) {}
        rows.add({
          'user_id': session.userId,
          'media_type': 'comic',
          'name': c.name,
          'enabled': true,
          'source_json': {
            'key': c.key,
            'name': c.name,
            'fileName': c.filePath.split('/').last,
            'js': code,
          },
        });
      }

      // 3) 视频源（TVBox 站点）
      for (final t in TvboxSourceManager.instance.sites) {
        rows.add({
          'user_id': session.userId,
          'media_type': 'video',
          'name': t.name,
          'enabled': true,
          'source_json': t.toJson(),
        });
      }

      final headers = _headers(session.accessToken);
      // 整体覆盖：先清后插（分批发，避免单请求过大）
      await _dio.delete(
        '${OmniSyncConfig.supabaseUrl}/rest/v1/user_sources?user_id=eq.${session.userId}',
        options: Options(headers: headers),
      );
      const batch = 50;
      for (var i = 0; i < rows.length; i += batch) {
        final part = rows.sublist(
            i, i + batch > rows.length ? rows.length : i + batch);
        await _dio.post(
          '${OmniSyncConfig.supabaseUrl}/rest/v1/user_sources',
          data: jsonEncode(part),
          options: Options(
              headers: {...headers, 'Prefer': 'return=minimal'}),
        );
      }
    } catch (_) {
      // 同步失败不影响本地使用
    } finally {
      _pushing = false;
    }
  }

  /* ---------------- 上传：API 配置 ---------------- */

  static void scheduleApiSync() {
    _apiTimer?.cancel();
    _apiTimer = Timer(const Duration(seconds: 3), pushApiConfigs);
  }

  static Future<void> pushApiConfigs() async {
    final session = OmniSync.instance.session;
    if (session == null) return;
    if (!await _isMember()) return; // 普通用户不同步
    try {
      final store = AiStore.instance;
      final rows = <Map<String, dynamic>>[];
      for (final p in AiProviders.providers) {
        final key = store.keys[p.keySlug] ?? '';
        if (key.isEmpty) continue;
        rows.add({
          'user_id': session.userId,
          'provider': p.keySlug,
          'name': p.name,
          'base_url': p.custom ? store.customBase : p.base,
          'api_key': key,
          'models': p.models,
        });
      }
      // 记录当前选择，后台可看到用户在用哪个模型
      rows.add({
        'user_id': session.userId,
        'provider': '__selection__',
        'name': '当前选择',
        'base_url': '',
        'api_key': '',
        'models': [store.selectedProvider, store.selectedModel],
      });

      final headers = _headers(session.accessToken);
      await _dio.delete(
        '${OmniSyncConfig.supabaseUrl}/rest/v1/user_api_configs?user_id=eq.${session.userId}',
        options: Options(headers: headers),
      );
      if (rows.isNotEmpty) {
        await _dio.post(
          '${OmniSyncConfig.supabaseUrl}/rest/v1/user_api_configs',
          data: jsonEncode(rows),
          options: Options(
              headers: {...headers, 'Prefer': 'return=minimal'}),
        );
      }
    } catch (_) {}
  }

  /* ---------------- 下载：登录后补齐 ---------------- */

  static Future<void> pullAll() async {
    final session = OmniSync.instance.session;
    if (session == null) return;
    if (!await _isMember()) return; // 普通用户不同步
    await Future.wait([_pullApiConfigs(session), _pullSources(session)]);
  }

  static Future<void> _pullApiConfigs(dynamic session) async {
    try {
      final res = await _dio.get(
        '${OmniSyncConfig.supabaseUrl}/rest/v1/user_api_configs',
        queryParameters: {
          'user_id': 'eq.${session.userId}',
          'select': 'provider,base_url,api_key',
        },
        options: Options(headers: _headers(session.accessToken)),
      );
      if (res.data is! List) return;
      final store = AiStore.instance;
      var changed = false;
      for (final row in res.data) {
        if (row is! Map) continue;
        final provider = row['provider']?.toString() ?? '';
        final key = row['api_key']?.toString() ?? '';
        final base = row['base_url']?.toString() ?? '';
        if (provider.isEmpty ||
            provider.startsWith('__') ||
            key.isEmpty) {
          continue;
        }
        // 本地已有 Key 不覆盖（本地为准）
        if ((store.keys[provider] ?? '').isEmpty) {
          store.keys[provider] = key;
          if (base.isNotEmpty &&
              AiProviders.providers
                  .any((p) => p.keySlug == provider && p.custom)) {
            store.customBase = base;
          }
          changed = true;
        }
      }
      if (changed) {
        store.save();
      }
    } catch (_) {}
  }

  static Future<void> _pullSources(dynamic session) async {
    try {
      final res = await _dio.get(
        '${OmniSyncConfig.supabaseUrl}/rest/v1/user_sources',
        queryParameters: {
          'user_id': 'eq.${session.userId}',
          'select': 'media_type,name,source_json',
          'limit': '1000',
        },
        options: Options(headers: _headers(session.accessToken)),
      );
      if (res.data is! List) return;
      final mgr = BookSourceManager.instance;
      final novels = <Map<String, dynamic>>[];
      for (final row in res.data) {
        if (row is! Map) continue;
        final type = row['media_type']?.toString() ?? '';
        final sj = row['source_json'];
        if (sj is! Map) continue;
        final j = Map<String, dynamic>.from(sj);
        if (type == 'novel' || type.startsWith('tauri_')) {
          // 已存在（同名同地址）跳过
          final name = (j['bookSourceName'] ?? '').toString();
          final url = (j['bookSourceUrl'] ?? '').toString();
          final exists = mgr.sources.any((s) =>
              s.bookSourceName == name && s.bookSourceUrl == url);
          if (!exists) novels.add(j);
        }
      }
      if (novels.isNotEmpty) {
        await mgr.importJson(jsonEncode(novels));
      }
    } catch (_) {}
  }
}
