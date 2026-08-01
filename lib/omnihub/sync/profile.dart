/// OmniHub 会员资料与云端额度
///
/// 与网页版 js/modules/profile.js 的规划表完全对齐：
/// - profiles 表列：nickname, role, plan, plan_expires_at, is_admin,
///   balance, storage_used_mb, storage_quota_mb
/// - 套餐：basic 普通会员 1GB / advanced 高级会员 5GB / vip 顶级会员 10GB
/// - 额度优先级：storage_quota_mb（管理员单独调整）> 按 role/plan 匹配套餐 > 0（免费）
library omni_profile;

import 'package:dio/dio.dart';

import 'package:venera/foundation/appdata.dart';

import 'omni_sync.dart';

class OmniPlanCard {
  final String key;
  final String name;
  final int quotaMb;
  final List<String> roles;

  const OmniPlanCard(this.key, this.name, this.quotaMb, this.roles);
}

/// 会员等级 → 云同步存储空间（用户 2026-08 新规）：
/// 普通 5MB / 进阶 500MB / 会员 1GB / 高级会员 5GB
const List<OmniPlanCard> kOmniPlanCards = [
  OmniPlanCard('user', '普通', 5, ['user', 'guest']),
  OmniPlanCard('advanced', '进阶', 500, ['advanced']),
  OmniPlanCard('vip', '会员', 1024, ['vip']),
  OmniPlanCard('svip', '高级会员', 5120, ['svip', 'agent', 'admin']),
];

class OmniProfile {
  final String nickname;
  final String avatarUrl;
  final String role;
  final String plan;
  final DateTime? planExpiresAt;
  final bool isAdmin;
  final double balance;
  final int storageUsedMb;
  final int storageQuotaMb;

  const OmniProfile({
    this.nickname = '',
    this.avatarUrl = '',
    this.role = '',
    this.plan = '',
    this.planExpiresAt,
    this.isAdmin = false,
    this.balance = 0,
    this.storageUsedMb = 0,
    this.storageQuotaMb = 0,
  });

  factory OmniProfile.fromJson(Map<String, dynamic> j) {
    DateTime? expires;
    final raw = j['plan_expires_at']?.toString();
    if (raw != null && raw.isNotEmpty) {
      expires = DateTime.tryParse(raw);
    }
    return OmniProfile(
      nickname: (j['nickname'] ?? '').toString(),
      avatarUrl: (j['avatar_url'] ?? '').toString(),
      role: (j['role'] ?? '').toString(),
      plan: (j['plan'] ?? '').toString(),
      planExpiresAt: expires,
      isAdmin: j['is_admin'] == true,
      balance: (j['balance'] as num?)?.toDouble() ?? 0,
      storageUsedMb: (j['storage_used_mb'] as num?)?.toInt() ?? 0,
      storageQuotaMb: (j['storage_quota_mb'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isPlanExpired =>
      planExpiresAt != null && planExpiresAt!.isBefore(DateTime.now());

  /// 当前生效套餐（过期视为无套餐）
  OmniPlanCard? get planCard {
    if (isPlanExpired) return null;
    for (final card in kOmniPlanCards) {
      if (card.roles.contains(role) || card.key == plan) return card;
    }
    return null;
  }

  /// 有效云端额度（MB）：管理员单独配额 > 套餐 > 0（免费用户）
  int get effectiveQuotaMb {
    if (storageQuotaMb > 0) return storageQuotaMb;
    return planCard?.quotaMb ?? 0;
  }

  /// 会员展示名（未登录用户返回 null）
  String? get membershipLabel {
    if (isAdmin) return '管理员';
    return planCard?.name;
  }

  static String fmtMb(int mb) {
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb == gb.roundToDouble() ? gb.toInt() : gb.toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}

class OmniProfileService {
  OmniProfileService._();
  static final OmniProfileService instance = OmniProfileService._();

  static const String gateway =
      'https://ai-gateway.1829487897.workers.dev';

  OmniProfile? _cached;
  OmniProfile? get cached => _cached;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: OmniSyncConfig.supabaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  void invalidate() => _cached = null;

  /// 拉取会员资料：优先走网关（与网页版一致），失败回退直查 profiles 表
  Future<OmniProfile?> fetch({bool force = false}) async {
    final session = OmniSync.instance.session;
    if (session == null) {
      _cached = null;
      return null;
    }
    if (_cached != null && !force) return _cached;

    // 1) AI 网关 /api/v1/membership（与网页版 applyMembership 同一通道）
    try {
      final res = await _dio.get(
        '$gateway/api/v1/membership',
        options: Options(headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        }),
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final raw = data['profile'] is Map<String, dynamic>
            ? data['profile'] as Map<String, dynamic>
            : data;
        if (raw['role'] != null || raw['plan'] != null) {
          _cached = OmniProfile.fromJson(raw);
          _persistLocal(_cached!);
          return _cached;
        }
      }
    } catch (_) {
      // 网关不可用 → 直查
    }

    // 2) 直查 profiles 表
    try {
      final res = await _dio.get(
        '/rest/v1/profiles',
        queryParameters: {
          'select':
              'nickname,avatar_url,role,plan,plan_expires_at,is_admin,balance,storage_used_mb,storage_quota_mb',
          'id': 'eq.${session.userId}',
        },
        options: Options(headers: {
          'apikey': OmniSyncConfig.anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
        }),
      );
      final rows = res.data;
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        _cached =
            OmniProfile.fromJson((rows.first as Map).cast<String, dynamic>());
        _persistLocal(_cached!);
        return _cached;
      }
    } catch (_) {
      // 无 profiles 行或网络失败
    }
    return _cached;
  }

  /// 云端资料回写本地缓存：网络慢/失败时设置页仍能显示昵称与头像
  void _persistLocal(OmniProfile p) {
    try {
      final s = appdata.settings;
      if (p.nickname.isNotEmpty) {
        s['profileNickname'] = p.nickname;
      }
      if (p.avatarUrl.isNotEmpty) {
        s['profileAvatarUrl'] = p.avatarUrl;
      }
      appdata.saveData();
    } catch (_) {}
  }
}
