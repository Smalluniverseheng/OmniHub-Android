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
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'user_data_sync.dart';

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

class OmniSync extends ChangeNotifier {
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

  /// 服务端错误 → 友好中文（移植自网页版 supabase.js errMsg）
  static String friendlyAuthError(Object e) {
    String m = '';
    int? status;
    if (e is DioException) {
      status = e.response?.statusCode;
      final d = e.response?.data;
      if (d is Map) {
        m = '${d['error_code'] ?? ''} ${d['msg'] ?? d['message'] ?? d['error_description'] ?? d['error'] ?? ''}'
            .trim();
      }
      if (m.isEmpty) m = e.message ?? '';
    } else {
      m = e.toString();
    }
    if (m.contains('Invalid login credentials') ||
        m.contains('invalid_credentials')) return '邮箱或密码错误';
    if (RegExp(r'User already registered|already|duplicate|exists',
            caseSensitive: false)
        .hasMatch(m)) return '该邮箱已注册，请直接登录';
    if (m.contains('Email not confirmed')) return '邮箱未验证，请先查收验证邮件';
    if (m.contains('at least 6 characters')) return '密码至少 6 位';
    if (RegExp(r'email_address_invalid|invalid email|validate email',
            caseSensitive: false)
        .hasMatch(m)) return '该邮箱暂不支持注册，请更换邮箱（推荐 QQ/163/Gmail）';
    if (m.contains('over_email_send_rate_limit') ||
        m.contains('rate limit')) return '注册邮件发送过于频繁，请稍后再试';
    if (RegExp(r'Failed to fetch|NetworkError|Network request failed|SocketException|Connection',
            caseSensitive: false)
        .hasMatch(m)) return '网络异常，请稍后重试';
    if (m.contains('row-level security') || m.contains('permission denied')) {
      return '权限不足';
    }
    if ((status != null && status >= 500) || m.isEmpty || m == '{}') {
      return '服务器异常，请稍后重试';
    }
    return m;
  }

  /// 邮箱注册
  ///
  /// 走服务端 RPC `omnihub_signup`（绕过邮箱域名校验与发信限流）。
  /// 返回 'ok' = 已登录；返回 'verify' = 需要输入邮箱验证码（验证码已发送）。
  /// RPC 不可用时回退官方 /auth/v1/signup。所有错误统一翻译成中文抛出。
  Future<String> signUp(String email, String password, {String name = ''}) async {
    // 1) RPC 管理员通道
    try {
      final res = await _dio.post(
        '/rest/v1/rpc/omnihub_signup',
        data: {'p_email': email, 'p_password': password, 'p_name': name},
        options: Options(headers: {
          'apikey': OmniSyncConfig.anonKey,
          'Authorization': 'Bearer ${OmniSyncConfig.anonKey}',
          'Content-Type': 'application/json',
        }),
      );
      final j = res.data;
      if (j is Map && j['ok'] == true) {
        if (j['need_verification'] == true) {
          // 触发验证码邮件（失败不阻塞，用户可在验证页点"重发"）
          try {
            await sendVerificationEmail(email);
          } catch (_) {}
          return 'verify';
        }
        await signIn(email, password);
        return 'ok';
      }
      final err = (j is Map ? j['error'] : null)?.toString() ?? '注册失败';
      throw Exception(err);
    } on DioException {
      // RPC 不存在或网络异常 → 回退官方通道
    }
    // 2) 官方注册通道（兜底）
    try {
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
        notifyListeners();
      }
    } on DioException catch (e) {
      throw Exception(friendlyAuthError(e));
    }
    return 'ok';
  }

  /// 调用 Edge Function 发送验证码邮件
  Future<void> sendVerificationEmail(String email) async {
    final res = await _dio.post(
      '/functions/v1/send-verification-email',
      data: {'email': email},
      options: Options(headers: {
        'apikey': OmniSyncConfig.anonKey,
        'Authorization': 'Bearer ${OmniSyncConfig.anonKey}',
        'Content-Type': 'application/json',
      }),
    );
    final j = res.data;
    if (j is Map && j['ok'] != true) {
      throw Exception((j['error'] ?? '邮件发送失败').toString());
    }
  }

  /// 重发验证码（60 秒频率限制由服务端控制）
  Future<void> resendVerificationCode(String email) async {
    final res = await _dio.post(
      '/rest/v1/rpc/omnihub_resend_code',
      data: {'p_email': email},
      options: Options(headers: {
        'apikey': OmniSyncConfig.anonKey,
        'Authorization': 'Bearer ${OmniSyncConfig.anonKey}',
        'Content-Type': 'application/json',
      }),
    );
    final j = res.data;
    if (j is Map && j['ok'] != true) {
      throw Exception((j['error'] ?? '发送失败').toString());
    }
    await sendVerificationEmail(email);
  }

  /// 校验验证码，通过后自动登录
  Future<void> verifyEmailAndSignIn(
      String email, String code, String password) async {
    final res = await _dio.post(
      '/rest/v1/rpc/omnihub_verify_email',
      data: {'p_email': email, 'p_code': code},
      options: Options(headers: {
        'apikey': OmniSyncConfig.anonKey,
        'Authorization': 'Bearer ${OmniSyncConfig.anonKey}',
        'Content-Type': 'application/json',
      }),
    );
    final j = res.data;
    if (j is Map && j['ok'] != true) {
      throw Exception((j['error'] ?? '验证失败').toString());
    }
    await signIn(email, password);
  }

  /// 邮箱登录
  Future<void> signIn(String email, String password) async {
    try {
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
      notifyListeners();
      // 登录后从云端补齐 API 配置与书源
      UserDataSync.pullAll();
    } on DioException catch (e) {
      // 已注册但未验证邮箱 → 抛特殊标记，UI 弹验证码框
      final d = e.response?.data;
      final m = d is Map
          ? '${d['error_code'] ?? ''} ${d['msg'] ?? d['message'] ?? ''}'
          : '';
      if (m.contains('email_not_confirmed') || m.contains('Email not confirmed')) {
        // 顺便补发一封验证码
        try {
          await resendVerificationCode(email);
        } catch (_) {}
        throw Exception('NEED_VERIFICATION');
      }
      throw Exception(friendlyAuthError(e));
    }
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
    notifyListeners();
  }

  /// 外部触发一次登录态/资料广播（如修改昵称后让设置页刷新）
  void refresh() => notifyListeners();

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
