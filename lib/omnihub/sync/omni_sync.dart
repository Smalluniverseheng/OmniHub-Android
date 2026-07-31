/// OmniHub 云端同步服务（M2 骨架）
///
/// 与网页版 OmniHub 共用同一 Supabase 项目，实现「数据互通」：
/// - 认证：Supabase Auth（邮箱+密码），会话持久化到本地文件
/// - 设置：`user_settings` 表（jsonb，last-write-wins）
/// - 数据：`user_data` 表（module/key/value，按 updated_at 增量同步）
///
/// 表结构详见 doc/omnihub/SYNC_SCHEMA.md。
/// 仅依赖项目已有的 dio / path_provider，不新增第三方包。
library omni_sync;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class OmniSyncConfig {
  static const String supabaseUrl = 'https://mxvxlgjzeboktufumxbp.supabase.co';
  // 与网页版相同的 publishable key（公开密钥，安全性由 RLS 保证）
  // 注：Supabase 已轮换密钥，旧的 JWT anon key 失效（注册/登录返回 401）
  static const String anonKey =
      'sb_publishable_WzUzAQK5cOEsn7QwFB2cAw_ubIkG7RJ';
}

class OmniSession {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String email;
  final int expiresAt; // 秒级时间戳

  OmniSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    required this.expiresAt,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiresAt - 60;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'user_id': userId,
        'email': email,
        'expires_at': expiresAt,
      };

  factory OmniSession.fromJson(Map<String, dynamic> j) => OmniSession(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        userId: j['user_id'] as String,
        email: (j['email'] ?? '') as String,
        expiresAt: (j['expires_at'] as num).toInt(),
      );
}

class OmniSync {
  OmniSync._();
  static final OmniSync instance = OmniSync._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: OmniSyncConfig.supabaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  OmniSession? _session;
  OmniSession? get session => _session;
  bool get isLoggedIn => _session != null;

  File? _sessionFile;

  Future<File> _getSessionFile() async {
    if (_sessionFile != null) return _sessionFile!;
    final dir = await getApplicationDocumentsDirectory();
    _sessionFile = File('${dir.path}/omnihub_sync_session.json');
    return _sessionFile!;
  }

  Map<String, String> get _authHeaders => {
        'apikey': OmniSyncConfig.anonKey,
        'Authorization': 'Bearer ${_session?.accessToken ?? OmniSyncConfig.anonKey}',
        'Content-Type': 'application/json',
      };

  /// 启动时恢复本地会话
  Future<void> restore() async {
    try {
      final f = await _getSessionFile();
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _session = OmniSession.fromJson(j);
      if (_session!.isExpired) {
        await _refresh();
      }
    } catch (_) {
      _session = null;
    }
  }

  Future<void> _saveSession() async {
    final f = await _getSessionFile();
    if (_session == null) {
      if (f.existsSync()) await f.delete();
    } else {
      await f.writeAsString(jsonEncode(_session!.toJson()));
    }
  }

  OmniSession _parseAuthResponse(Map<String, dynamic> j) {
    final user = (j['user'] ?? const {}) as Map<String, dynamic>;
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return OmniSession(
      accessToken: j['access_token'] as String,
      refreshToken: (j['refresh_token'] ?? '') as String,
      userId: (user['id'] ?? '') as String,
      email: (user['email'] ?? '') as String,
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn,
    );
  }

  /// 邮箱注册
  Future<void> signUp(String email, String password) async {
    final res = await _dio.post(
      '/auth/v1/signup',
      data: {'email': email, 'password': password},
      options: Options(headers: {
        'apikey': OmniSyncConfig.anonKey,
        'Content-Type': 'application/json',
      }),
    );
    final j = res.data as Map<String, dynamic>;
    if (j['access_token'] != null) {
      _session = _parseAuthResponse(j);
      await _saveSession();
    }
  }

  /// 邮箱登录
  Future<void> signIn(String email, String password) async {
    final res = await _dio.post(
      '/auth/v1/token?grant_type=password',
      data: {'email': email, 'password': password},
      options: Options(headers: {
        'apikey': OmniSyncConfig.anonKey,
        'Content-Type': 'application/json',
      }),
    );
    _session = _parseAuthResponse(res.data as Map<String, dynamic>);
    await _saveSession();
  }

  Future<void> _refresh() async {
    if (_session == null || _session!.refreshToken.isEmpty) return;
    try {
      final res = await _dio.post(
        '/auth/v1/token?grant_type=refresh_token',
        data: {'refresh_token': _session!.refreshToken},
        options: Options(headers: {
          'apikey': OmniSyncConfig.anonKey,
          'Content-Type': 'application/json',
        }),
      );
      _session = _parseAuthResponse(res.data as Map<String, dynamic>);
      await _saveSession();
    } catch (_) {
      await signOut();
    }
  }

  Future<void> signOut() async {
    _session = null;
    await _saveSession();
  }

  Future<void> _ensureFresh() async {
    if (_session != null && _session!.isExpired) await _refresh();
  }

  // ---------------- user_settings ----------------

  /// 拉取云端设置（不存在返回 null）
  Future<Map<String, dynamic>?> pullSettings() async {
    await _ensureFresh();
    if (_session == null) return null;
    final res = await _dio.get(
      '/rest/v1/user_settings',
      queryParameters: {'user_id': 'eq.${_session!.userId}', 'select': 'settings,updated_at'},
      options: Options(headers: _authHeaders),
    );
    final list = res.data as List;
    if (list.isEmpty) return null;
    return {
      'settings': list.first['settings'],
      'updated_at': list.first['updated_at'],
    };
  }

  /// 上传设置（整体覆盖，last-write-wins）
  Future<void> pushSettings(Map<String, dynamic> settings) async {
    await _ensureFresh();
    if (_session == null) return;
    await _dio.post(
      '/rest/v1/user_settings',
      data: {
        'user_id': _session!.userId,
        'settings': settings,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      options: Options(headers: {
        ..._authHeaders,
        'Prefer': 'resolution=merge-duplicates',
      }),
    );
  }

  // ---------------- user_data ----------------

  /// 拉取某模块自 [since] 以来的增量（since 为 null 则全量）
  Future<List<Map<String, dynamic>>> pullModule(String module,
      {DateTime? since}) async {
    await _ensureFresh();
    if (_session == null) return [];
    final params = <String, dynamic>{
      'user_id': 'eq.${_session!.userId}',
      'module': 'eq.$module',
      'select': 'key,value,updated_at',
    };
    if (since != null) {
      params['updated_at'] = 'gt.${since.toUtc().toIso8601String()}';
    }
    final res = await _dio.get(
      '/rest/v1/user_data',
      queryParameters: params,
      options: Options(headers: _authHeaders),
    );
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// 上行一批记录（upsert；删除传 value={'_deleted': true} 墓碑）
  Future<void> pushRecords(
      String module, Map<String, Map<String, dynamic>> records) async {
    await _ensureFresh();
    if (_session == null || records.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = records.entries
        .map((e) => {
              'user_id': _session!.userId,
              'module': module,
              'key': e.key,
              'value': e.value,
              'updated_at': now,
            })
        .toList();
    await _dio.post(
      '/rest/v1/user_data',
      data: rows,
      options: Options(headers: {
        ..._authHeaders,
        'Prefer': 'resolution=merge-duplicates',
      }),
    );
  }
}
