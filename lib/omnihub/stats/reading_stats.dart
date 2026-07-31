/// OmniHub 阅读统计
///
/// 记录每次阅读时长（阅读器打开到关闭为一个 session），按天聚合。
/// 本地 JSON 存储 + 登录后可通过 OmniSync 同步（module: stats）。
library reading_stats;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../sync/omni_sync.dart';

class DayStat {
  int seconds;
  int sessions;
  int longest; // 最长单次秒数
  int updatedAt; // 毫秒时间戳，用于合并

  DayStat(
      {this.seconds = 0,
      this.sessions = 0,
      this.longest = 0,
      this.updatedAt = 0});

  Map<String, dynamic> toJson() => {
        'seconds': seconds,
        'sessions': sessions,
        'longest': longest,
        'updatedAt': updatedAt,
      };

  factory DayStat.fromJson(Map<String, dynamic> j) => DayStat(
        seconds: (j['seconds'] ?? 0) as int,
        sessions: (j['sessions'] ?? 0) as int,
        longest: (j['longest'] ?? 0) as int,
        updatedAt: (j['updatedAt'] ?? 0) as int,
      );
}

class ReadingStats extends ChangeNotifier {
  ReadingStats._();
  static final ReadingStats instance = ReadingStats._();

  final Map<String, DayStat> days = {}; // key: yyyy-MM-dd
  File? _file;
  DateTime? _sessionStart;
  bool _loaded = false;

  static String keyOf(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/omnihub_reading_stats.json');
    return _file!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        j.forEach((k, v) => days[k] = DayStat.fromJson(v));
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final f = await _ensureFile();
    await f.writeAsString(
        jsonEncode(days.map((k, v) => MapEntry(k, v.toJson()))));
  }

  /// 阅读器打开时调用
  void startSession() {
    _sessionStart = DateTime.now();
  }

  /// 阅读器关闭时调用
  void endSession() {
    final start = _sessionStart;
    _sessionStart = null;
    if (start == null) return;
    var secs = DateTime.now().difference(start).inSeconds;
    if (secs < 5) return; // 误触不计
    if (secs > 4 * 3600) secs = 4 * 3600; // 挂机兜底
    final key = keyOf(start);
    final d = days.putIfAbsent(key, () => DayStat());
    d.seconds += secs;
    d.sessions += 1;
    if (secs > d.longest) d.longest = secs;
    d.updatedAt = DateTime.now().millisecondsSinceEpoch;
    save();
    notifyListeners();
  }

  DayStat today() => days[keyOf(DateTime.now())] ?? DayStat();

  int get totalSeconds => days.values.fold(0, (sum, d) => sum + d.seconds);
  int get totalSessions => days.values.fold(0, (sum, d) => sum + d.sessions);
  int get longestSession =>
      days.values.fold(0, (m, d) => d.longest > m ? d.longest : m);

  double get avgPerDay {
    if (days.isEmpty) return 0;
    return totalSeconds / days.length;
  }

  /// 最近 7 天（含今天）
  List<(String, DayStat)> last7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final t = now.subtract(Duration(days: 6 - i));
      final k = keyOf(t);
      return (k, days[k] ?? DayStat());
    });
  }

  static String fmt(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    if (m < 60) return '${m}min';
    return '${m ~/ 60}h ${m % 60}min';
  }

  /// 同步（需登录）：推送本地全部 + 拉取合并（按天取 updatedAt 较新者）
  Future<void> sync() async {
    if (!OmniSync.instance.isLoggedIn) return;
    final records = days.map((k, v) => MapEntry(k, {
          ...v.toJson(),
          'date': k,
        }));
    await OmniSync.instance.pushRecords('stats', records);
    final remote = await OmniSync.instance.pullModule('stats');
    remote.forEach((k, v) {
      if (v is Map && v['_deleted'] == true) return;
      final r = DayStat.fromJson(Map<String, dynamic>.from(v as Map));
      final local = days[k];
      if (local == null || r.updatedAt > local.updatedAt) {
        days[k] = r;
      }
    });
    await save();
    notifyListeners();
  }
}
