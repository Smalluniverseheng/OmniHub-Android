/// 书架相关子页面：筛选 / 展示设置 / 云同步管理 / 阅读统计 / 最近删除
library shelf_subpages;

import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/omnihub/shelf/recycle_bin.dart';
import 'package:venera/omnihub/stats/reading_stats.dart';
import 'package:venera/omnihub/sync/bookshelf_sync.dart';
import 'package:venera/omnihub/sync/omni_sync.dart';
import 'package:venera/omnihub/sync/profile.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/translations.dart';

import 'import_export_pages.dart';

/// 书架复合筛选条件
class ShelfFilter {
  final String? folder;
  final String readStatus; // all / unread / reading / finished
  final bool downloadedOnly;
  final String? tag;

  const ShelfFilter({
    this.folder,
    this.readStatus = 'all',
    this.downloadedOnly = false,
    this.tag,
  });

  bool get isActive =>
      folder != null ||
      readStatus != 'all' ||
      downloadedOnly ||
      (tag != null && tag!.isNotEmpty);

  ShelfFilter copyWith({
    String? Function()? folder,
    String? readStatus,
    bool? downloadedOnly,
    String? Function()? tag,
  }) {
    return ShelfFilter(
      folder: folder != null ? folder() : this.folder,
      readStatus: readStatus ?? this.readStatus,
      downloadedOnly: downloadedOnly ?? this.downloadedOnly,
      tag: tag != null ? tag() : this.tag,
    );
  }
}

/// 筛选页（多维：分组 / 阅读状态 / 已下载 / 标签）
class ShelfFilterPage extends StatefulWidget {
  final ShelfFilter initial;
  const ShelfFilterPage({super.key, required this.initial});

  @override
  State<ShelfFilterPage> createState() => _ShelfFilterPageState();
}

class _ShelfFilterPageState extends State<ShelfFilterPage> {
  late ShelfFilter _f;
  late final TextEditingController _tagController;

  @override
  void initState() {
    super.initState();
    _f = widget.initial;
    _tagController = TextEditingController(text: _f.tag ?? '');
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  static const _readStatuses = {
    'all': '全部',
    'unread': '未读',
    'reading': '在读',
    'finished': '读完',
  };

  @override
  Widget build(BuildContext context) {
    final folders = LocalFavoritesManager().folderNames;
    return Scaffold(
      appBar: AppBar(
        title: Text("筛选".tl),
        actions: [
          TextButton(
            onPressed: () => context.pop(const ShelfFilter()),
            child: Text("重置".tl),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle("分组"),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text("全部".tl),
                selected: _f.folder == null,
                onSelected: (_) =>
                    setState(() => _f = _f.copyWith(folder: () => null)),
              ),
              for (final f in folders)
                ChoiceChip(
                  label: Text(f),
                  selected: _f.folder == f,
                  onSelected: (_) =>
                      setState(() => _f = _f.copyWith(folder: () => f)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle("阅读状态"),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _readStatuses.entries)
                ChoiceChip(
                  label: Text(e.value.tl),
                  selected: _f.readStatus == e.key,
                  onSelected: (_) => setState(
                      () => _f = _f.copyWith(readStatus: e.key)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle("其他"),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("仅已下载".tl),
            value: _f.downloadedOnly,
            onChanged: (v) =>
                setState(() => _f = _f.copyWith(downloadedOnly: v)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tagController,
            decoration: InputDecoration(
              labelText: "标签".tl,
              hintText: "输入标签关键字".tl,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _f = _f.copyWith(tag: () => v.trim()),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.pop(_f),
            child: Text("应用筛选".tl),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t.tl,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: context.colorScheme.primary)),
    );
  }
}

/// 书架展示设置
class ShelfDisplaySettingsPage extends StatefulWidget {
  const ShelfDisplaySettingsPage({super.key});

  @override
  State<ShelfDisplaySettingsPage> createState() =>
      _ShelfDisplaySettingsPageState();
}

class _ShelfDisplaySettingsPageState extends State<ShelfDisplaySettingsPage> {
  static const _refreshModes = {
    'pull': '下拉刷新',
    'auto': '打开时自动刷新',
    'manual': '手动刷新',
  };

  bool _get(String key) => appdata.settings[key] != false;
  void _set(String key, bool v) {
    appdata.settings[key] = v;
    appdata.saveData();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final refresh = appdata.settings['shelfRefreshMode']?.toString() ?? 'pull';
    return Scaffold(
      appBar: AppBar(title: Text("书架展示设置".tl)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text("显示分类".tl,
                style: TextStyle(color: context.colorScheme.primary)),
          ),
          SwitchListTile(
            title: Text("显示「短剧」".tl),
            subtitle: Text("后续版本将接入短剧内容".tl,
                style: const TextStyle(fontSize: 12)),
            value: _get('shelfShowShort'),
            onChanged: (v) => _set('shelfShowShort', v),
          ),
          SwitchListTile(
            title: Text("显示「漫剧」".tl),
            subtitle: Text("后续版本将接入漫剧视频".tl,
                style: const TextStyle(fontSize: 12)),
            value: _get('shelfShowComicDrama'),
            onChanged: (v) => _set('shelfShowComicDrama', v),
          ),
          SwitchListTile(
            title: Text("显示「互动」".tl),
            value: _get('shelfShowInteractive'),
            onChanged: (v) => _set('shelfShowInteractive', v),
          ),
          const Divider(height: 24),
          SwitchListTile(
            title: Text("展示推荐内容".tl),
            subtitle: Text("在书架底部展示为你推荐".tl,
                style: const TextStyle(fontSize: 12)),
            value: _get('shelfShowRecommend'),
            onChanged: (v) => _set('shelfShowRecommend', v),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text("书架刷新方式".tl,
                style: TextStyle(color: context.colorScheme.primary)),
          ),
          for (final e in _refreshModes.entries)
            RadioListTile<String>(
              title: Text(e.value.tl),
              value: e.key,
              groupValue: refresh,
              onChanged: (v) {
                appdata.settings['shelfRefreshMode'] = v;
                appdata.saveData();
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}

/// 云同步管理
class CloudSyncManagePage extends StatefulWidget {
  const CloudSyncManagePage({super.key});

  @override
  State<CloudSyncManagePage> createState() => _CloudSyncManagePageState();
}

class _CloudSyncManagePageState extends State<CloudSyncManagePage> {
  OmniProfile? _profile;
  bool _loadingProfile = false;
  bool _syncing = false;

  bool get _enabled => appdata.settings['omniShelfCloudSync'] != false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!OmniSync.instance.isLoggedIn) return;
    setState(() => _loadingProfile = true);
    final p = await OmniProfileService.instance.fetch(force: true);
    if (mounted) {
      setState(() {
        _profile = p;
        _loadingProfile = false;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final r = await BookshelfSync.instance.sync();
    if (mounted) {
      setState(() => _syncing = false);
      context.showMessage(
          message: r.ok ? "同步完成".tl : "同步失败：${r.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = OmniSync.instance.isLoggedIn;
    // 额度按规划表：storage_quota_mb 优先，否则套餐（普通1GB/高级5GB/顶级10GB），免费0
    final quotaMb = _profile?.effectiveQuotaMb ?? 0;
    final usedMb = _profile?.storageUsedMb ?? 0;
    final membershipLabel = _profile?.membershipLabel;
    return Scaffold(
      appBar: AppBar(title: Text("云同步管理".tl)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!loggedIn)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text("未登录".tl),
                subtitle: Text("登录后可使用云同步".tl),
                trailing: FilledButton.tonal(
                  onPressed: () => context
                      .to(() => const SettingsPage(initialPage: 7)),
                  child: Text("去登录".tl),
                ),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("本地书云同步".tl),
            subtitle: Text("将书架、阅读进度同步到云端".tl,
                style: const TextStyle(fontSize: 12)),
            value: _enabled,
            onChanged: (v) {
              appdata.settings['omniShelfCloudSync'] = v;
              appdata.saveData();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text("云端额度".tl,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_loadingProfile)
                        const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                      else if (loggedIn)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: membershipLabel != null
                                ? const LinearGradient(colors: [
                                    Color(0xFF6366F1),
                                    Color(0xFF8B5CF6)
                                  ])
                                : null,
                            color: membershipLabel == null
                                ? context.colorScheme.secondaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            membershipLabel ?? "免费用户".tl,
                            style: TextStyle(
                              fontSize: 12,
                              color: membershipLabel != null
                                  ? Colors.white
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: quotaMb > 0
                        ? (usedMb / quotaMb).clamp(0.0, 1.0)
                        : 0,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${OmniProfile.fmtMb(usedMb)} / ${OmniProfile.fmtMb(quotaMb)}",
                    style: TextStyle(
                        fontSize: 12, color: context.colorScheme.outline),
                  ),
                  if (loggedIn && quotaMb <= 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      "免费用户暂无云端额度，升级会员开启更大空间（普通 1GB / 高级 5GB / 顶级 10GB）"
                          .tl,
                      style: TextStyle(
                          fontSize: 12, color: context.colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !loggedIn || !_enabled || _syncing
                ? null
                : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: Text("立即同步".tl),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.to(() => const WifiTransferPage()),
                  icon: const Icon(Icons.computer, size: 18),
                  label: Text("从电脑导入".tl),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => importBooksFromDevice(context),
                  icon: const Icon(Icons.phone_android, size: 18),
                  label: Text("从本机导入".tl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "「从电脑导入」通过局域网 WiFi 传书；「从本机导入」支持 txt/epub 小说与 cbz/zip 漫画。"
                .tl,
            style: TextStyle(fontSize: 12, color: context.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 阅读统计页
class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  bool _syncing = false;

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ReadingStats.instance.addListener(_onChange);
    ReadingStats.instance.load();
  }

  @override
  void dispose() {
    ReadingStats.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ReadingStats.instance;
    final week = s.last7Days();
    final maxSecs =
        week.fold<int>(1, (m, e) => e.$2.seconds > m ? e.$2.seconds : m);
    const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
    return Scaffold(
      appBar: AppBar(
        title: Text("阅读统计".tl),
        actions: [
          IconButton(
            tooltip: "Sync".tl,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: _syncing
                ? null
                : () async {
                    if (!OmniSync.instance.isLoggedIn) {
                      context.showMessage(message: "请先登录云同步账号".tl);
                      return;
                    }
                    setState(() => _syncing = true);
                    try {
                      await ReadingStats.instance.sync();
                      if (mounted) {
                        context.showMessage(message: "同步完成".tl);
                      }
                    } catch (e) {
                      if (mounted) {
                        context.showMessage(message: "同步失败：$e");
                      }
                    } finally {
                      if (mounted) setState(() => _syncing = false);
                    }
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: [
              _statCard("总阅读时长", ReadingStats.fmt(s.totalSeconds),
                  Icons.schedule),
              _statCard("阅读次数", "${s.totalSessions}", Icons.menu_book),
              _statCard(
                  "日均阅读",
                  ReadingStats.fmt(s.avgPerDay.round()),
                  Icons.today),
              _statCard("书籍数量", "${LocalFavoritesManager().totalComics}",
                  Icons.library_books),
              _statCard("最长单次", ReadingStats.fmt(s.longestSession),
                  Icons.timer),
              _statCard("今日", ReadingStats.fmt(s.today().seconds),
                  Icons.wb_sunny_outlined),
            ],
          ),
          const SizedBox(height: 20),
          Text("本周趋势".tl,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          week[i].$2.seconds > 0
                              ? ReadingStats.fmt(week[i].$2.seconds)
                              : '',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 22,
                          height: 4 +
                              100 *
                                  (week[i].$2.seconds / maxSecs)
                                      .clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            color: i == 6
                                ? context.colorScheme.primary
                                : context.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          weekNames[
                              (DateTime.now()
                                          .subtract(Duration(days: 6 - i))
                                          .weekday -
                                      1) %
                                  7],
                          style: TextStyle(
                              fontSize: 12,
                              color: context.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "统计数据保存在本机，登录后点右上角同步到云端。".tl,
            style: TextStyle(fontSize: 12, color: context.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: context.colorScheme.primary),
                const SizedBox(width: 6),
                Text(label.tl,
                    style: TextStyle(
                        fontSize: 12, color: context.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// 最近删除
class RecentlyDeletedPage extends StatefulWidget {
  const RecentlyDeletedPage({super.key});

  @override
  State<RecentlyDeletedPage> createState() => _RecentlyDeletedPageState();
}

class _RecentlyDeletedPageState extends State<RecentlyDeletedPage> {
  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ShelfRecycleBin.instance.addListener(_onChange);
    ShelfRecycleBin.instance.load().then((_) => _onChange());
  }

  @override
  void dispose() {
    ShelfRecycleBin.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ShelfRecycleBin.instance.items;
    return Scaffold(
      appBar: AppBar(title: Text("最近删除".tl)),
      body: items.isEmpty
          ? Center(
              child: Text("回收站是空的".tl,
                  style: TextStyle(color: context.colorScheme.outline)),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final r = items[i];
                final daysLeft = 30 -
                    DateTime.now()
                        .difference(DateTime.fromMillisecondsSinceEpoch(
                            r.deletedAt))
                        .inDays;
                return ListTile(
                  leading: const Icon(Icons.book_outlined),
                  title: Text(r.item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      "${r.folder} · @d 天后彻底删除".tlParams({'d': daysLeft})),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await ShelfRecycleBin.instance.restore(r);
                          if (context.mounted) {
                            context.showMessage(message: "已恢复".tl);
                          }
                        },
                        child: Text("恢复".tl),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_outlined),
                        onPressed: () =>
                            ShelfRecycleBin.instance.removeForever(r),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
