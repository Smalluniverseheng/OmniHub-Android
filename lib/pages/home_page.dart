/// OmniHub 主页 v1.9 —— 番茄小说书架式
///
/// 顶部 Tab（书架/历史/收藏/圈子，可左右滑动）+ 搜索与三点菜单 +
/// 今日听读打卡条 + 筛选 chips + 书架宫格/列表（长按多选编辑）。
library home_page;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/omnihub/shelf/recycle_bin.dart';
import 'package:venera/omnihub/stats/reading_stats.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/pages/follow_updates_page.dart';
import 'package:venera/pages/novel/novel_pages.dart';
import 'package:venera/pages/search_page.dart';
import 'package:venera/pages/shelf/shelf_subpages.dart';
import 'package:venera/utils/import_comic.dart';
import 'package:venera/utils/translations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _tabIndex = 0;

  /// 书架显示模式：grid / list
  String get _displayMode =>
      appdata.settings['shelfDisplayMode']?.toString() ?? 'grid';
  set _displayMode(String v) {
    appdata.settings['shelfDisplayMode'] = v;
    appdata.saveData();
  }

  /// 顶部筛选 chips
  String _chip = 'all';

  /// 筛选页返回的复合筛选条件
  ShelfFilter _filter = const ShelfFilter();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _tab.addListener(() {
      if (_tab.index != _tabIndex) {
        setState(() => _tabIndex = _tab.index);
      }
    });
    ReadingStats.instance.load();
    ShelfRecycleBin.instance.load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: context.padding.top),
        _buildHeader(),
        if (_tabIndex == 0) ...[
          const _TodayReadBar(),
          _buildChips(),
        ],
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _ShelfTab(
                displayMode: _displayMode,
                chip: _chip,
                filter: _filter,
              ),
              const _HistoryTab(),
              const FavoritesPage(),
              const NovelTab(),
              _buildCommunityPlaceholder(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 15),
              tabs: [
                Tab(text: "书架".tl),
                Tab(text: "History".tl),
                Tab(text: "Favorites".tl),
                Tab(text: "小说".tl),
                Tab(text: "圈子".tl),
              ],
            ),
          ),
          IconButton(
            tooltip: "Search".tl,
            icon: const Icon(Icons.search),
            onPressed: () => context.to(() => const SearchPage()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              _menuItem('updates', Icons.notifications_outlined, "连载更新提醒"),
              _menuItem(
                  'toggle',
                  _displayMode == 'grid'
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                  _displayMode == 'grid' ? "切换为列表" : "切换为宫格"),
              _menuItem('cloud', Icons.cloud_outlined, "云同步管理"),
              _menuItem('import', Icons.download_outlined, "导入图书"),
              _menuItem('display', Icons.tune, "书架展示设置"),
              _menuItem('recycle', Icons.delete_outline, "最近删除"),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(text.tl),
        ],
      ),
    );
  }

  void _onMenu(String v) async {
    switch (v) {
      case 'updates':
        context.to(() => const FollowUpdatesPage());
        break;
      case 'toggle':
        setState(() =>
            _displayMode = _displayMode == 'grid' ? 'list' : 'grid');
        break;
      case 'cloud':
        context.to(() => const CloudSyncManagePage());
        break;
      case 'import':
        showDialog(
          barrierDismissible: false,
          context: App.rootContext,
          builder: (context) => const _ImportComicsWidget(),
        );
        break;
      case 'display':
        context.to(() => const ShelfDisplaySettingsPage()).then((_) {
          if (mounted) setState(() {});
        });
        break;
      case 'recycle':
        context.to(() => const RecentlyDeletedPage());
        break;
    }
  }

  Widget _buildChips() {
    final chips = <(String, String)>[
      ('all', "全部"),
      ('reading', "阅读"),
      ('audio', "听书"),
      ('short', "短剧"),
      ('comicdrama', "漫剧"),
    ];
    final showShort = appdata.settings['shelfShowShort'] != false;
    final showDrama = appdata.settings['shelfShowComicDrama'] != false;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final c in chips)
            if ((c.$1 != 'short' || showShort) &&
                (c.$1 != 'comicdrama' || showDrama))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.$2.tl),
                  selected: _chip == c.$1,
                  onSelected: (_) => setState(() => _chip = c.$1),
                ),
              ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(Icons.filter_list,
                  size: 16,
                  color: _filter.isActive
                      ? context.colorScheme.primary
                      : null),
              label: Text("筛选".tl),
              onPressed: () async {
                final r = await context.to<ShelfFilter>(
                    () => ShelfFilterPage(initial: _filter));
                if (r != null) setState(() => _filter = r);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined,
              size: 64, color: context.colorScheme.outline),
          const SizedBox(height: 12),
          Text("圈子功能筹备中".tl,
              style: TextStyle(color: context.colorScheme.outline)),
        ],
      ),
    );
  }
}

/// 今日听读打卡条
class _TodayReadBar extends StatefulWidget {
  const _TodayReadBar();

  @override
  State<_TodayReadBar> createState() => _TodayReadBarState();
}

class _TodayReadBarState extends State<_TodayReadBar> {
  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ReadingStats.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    ReadingStats.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = ReadingStats.instance.today();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.colorScheme.primaryContainer,
            context.colorScheme.secondaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.to(() => const ReadingStatsPage()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.headphones, color: context.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("今日听读".tl,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      today.seconds > 0
                          ? "已读 @t · 打卡 @c 次".tlParams({
                              't': ReadingStats.fmt(today.seconds),
                              'c': today.sessions,
                            })
                          : "今天还没有阅读记录".tl,
                      style: TextStyle(
                          fontSize: 12, color: context.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 书架 Tab：宫格/列表 + 长按多选编辑
class _ShelfTab extends StatefulWidget {
  final String displayMode;
  final String chip;
  final ShelfFilter filter;

  const _ShelfTab({
    required this.displayMode,
    required this.chip,
    required this.filter,
  });

  @override
  State<_ShelfTab> createState() => _ShelfTabState();
}

class _ShelfTabState extends State<_ShelfTab>
    with AutomaticKeepAliveClientMixin {
  List<FavoriteItemWithFolderInfo> _all = [];
  final Set<FavoriteItem> _selected = {};
  bool _selecting = false;

  @override
  bool get wantKeepAlive => true;

  void _reload() {
    if (mounted) {
      setState(() {
        _all = LocalFavoritesManager().allComics();
        _selected.removeWhere((e) => !_all.contains(e));
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _all = LocalFavoritesManager().allComics();
    LocalFavoritesManager().addListener(_reload);
    ShelfRecycleBin.instance.addListener(_reload);
  }

  @override
  void dispose() {
    LocalFavoritesManager().removeListener(_reload);
    ShelfRecycleBin.instance.removeListener(_reload);
    super.dispose();
  }

  List<FavoriteItemWithFolderInfo> get _items {
    Iterable<FavoriteItemWithFolderInfo> res = _all;
    // 顶部 chips
    switch (widget.chip) {
      case 'reading':
        res = res.where(
            (e) => HistoryManager().find(e.id, e.type) != null);
        break;
      case 'audio':
      case 'short':
      case 'comicdrama':
        return const []; // 听书/短剧/漫剧：后续版本
    }
    // 复合筛选
    final f = widget.filter;
    if (f.folder != null) res = res.where((e) => e.folder == f.folder);
    if (f.downloadedOnly) {
      res = res.where((e) => e.type == ComicType.local);
    }
    if (f.readStatus != 'all') {
      res = res.where((e) {
        final h = HistoryManager().find(e.id, e.type);
        switch (f.readStatus) {
          case 'unread':
            return h == null;
          case 'reading':
            return h != null &&
                !(h.maxPage != null && h.maxPage! > 0 && h.page >= h.maxPage!);
          case 'finished':
            return h != null &&
                h.maxPage != null &&
                h.maxPage! > 0 &&
                h.page >= h.maxPage!;
          default:
            return true;
        }
      });
    }
    if (f.tag != null && f.tag!.isNotEmpty) {
      final t = f.tag!.toLowerCase();
      res = res.where(
          (e) => e.tags.any((tag) => tag.toLowerCase().contains(t)));
    }
    return res.toList();
  }

  String _progressText(FavoriteItem c) {
    final h = HistoryManager().find(c.id, c.type);
    if (h == null) return "未读".tl;
    if (h.maxPage != null && h.maxPage! > 0) {
      final p = (h.page / h.maxPage! * 100).clamp(0, 100).round();
      return "读至 @p%".tlParams({'p': p});
    }
    return "读至第 @e 章".tlParams({'e': h.ep});
  }

  void _openComic(FavoriteItem c) {
    context.to(() => ComicPage(
          id: c.id,
          sourceKey: c.type == ComicType.local
              ? 'local'
              : c.type.comicSource?.key ?? 'Unknown',
          cover: c.cover,
          title: c.title,
        ));
  }

  void _onTapItem(FavoriteItemWithFolderInfo c) {
    if (_selecting) {
      setState(() {
        _selected.contains(c) ? _selected.remove(c) : _selected.add(c);
        if (_selected.isEmpty) _selecting = false;
      });
    } else {
      _openComic(c);
    }
  }

  void _onLongPressItem(FavoriteItemWithFolderInfo c) {
    setState(() {
      _selecting = true;
      _selected.add(c);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    return Column(
      children: [
        if (_selecting) _buildSelectionBar(items),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    widget.chip == 'audio' ||
                            widget.chip == 'short' ||
                            widget.chip == 'comicdrama'
                        ? "该分类将在后续版本开放".tl
                        : "书架空空如也".tl,
                    style: TextStyle(color: context.colorScheme.outline),
                  ),
                )
              : widget.displayMode == 'grid'
                  ? _buildGrid(items)
                  : _buildList(items),
        ),
        if (_selecting) _buildActionBar(),
      ],
    );
  }

  Widget _buildSelectionBar(List<FavoriteItemWithFolderInfo> items) {
    return Container(
      height: 44,
      color: context.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _selecting = false;
              _selected.clear();
            }),
          ),
          Text("已选 @c 项".tlParams({'c': _selected.length})),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == items.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(items);
              }
            }),
            child: Text(
                _selected.length == items.length ? "取消全选".tl : "全选".tl),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<FavoriteItemWithFolderInfo> items) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 0.56,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final c = items[i];
        final selected = _selected.contains(c);
        return GestureDetector(
          onTap: () => _onTapItem(c),
          onLongPress: () => _onLongPressItem(c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SimpleComicTile(comic: c, heroID: c.hashCode),
                    ),
                    if (_selecting)
                      Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? context.colorScheme.primary
                                  .withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(
                                  color: context.colorScheme.primary,
                                  width: 2)
                              : null,
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                _progressText(c),
                style: TextStyle(
                    fontSize: 11, color: context.colorScheme.outline),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<FavoriteItemWithFolderInfo> items) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final c = items[i];
        final selected = _selected.contains(c);
        final h = HistoryManager().find(c.id, c.type);
        return ListTile(
          selected: selected,
          leading: SizedBox(
            width: 44,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SimpleComicTile(comic: c, heroID: c.hashCode),
            ),
          ),
          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              _progressText(c),
              if (h != null)
                "${h.time.year}-${h.time.month.toString().padLeft(2, '0')}-${h.time.day.toString().padLeft(2, '0')} 更新",
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: _selecting
              ? Icon(selected
                  ? Icons.check_circle
                  : Icons.circle_outlined)
              : null,
          onTap: () => _onTapItem(c),
          onLongPress: () => _onLongPressItem(c),
        );
      },
    );
  }

  Widget _buildActionBar() {
    final actions = <(IconData, String, VoidCallback?)>[
      (Icons.find_in_page_outlined, "找相似书", () {
        context.showMessage(message: "该功能将在后续版本上线".tl);
      }),
      (Icons.drive_file_move_outlined, "移动至分组", () => _moveSelected(true)),
      (Icons.playlist_add, "加入书单", () => _moveSelected(false)),
      (Icons.add_to_home_screen_outlined, "加入桌面", () {
        context.showMessage(message: "该功能将在后续版本上线".tl);
      }),
      (Icons.delete_outline, "删除", _deleteSelected),
    ];
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHigh,
        border: Border(
            top: BorderSide(color: context.colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final a in actions)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: a.$3,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.$1, size: 20),
                    const SizedBox(height: 2),
                    Text(a.$2.tl, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _pickFolder() async {
    final mgr = LocalFavoritesManager();
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text("选择分组".tl),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: "新建分组名称".tl,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final name = controller.text.trim();
                          if (name.isNotEmpty) {
                            mgr.createFolder(name, true);
                            setDialog(() {});
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final f in mgr.folderNames)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(f),
                            subtitle:
                                Text("${mgr.folderComics(f)}"),
                            onTap: () => Navigator.of(context).pop(f),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _moveSelected(bool removeFromSource) async {
    if (_selected.isEmpty) return;
    final folder = await _pickFolder();
    if (folder == null) return;
    final mgr = LocalFavoritesManager();
    var moved = 0;
    for (final c in _selected.toList()) {
      final src = _all.firstWhere((e) => e == c);
      if (src.folder == folder) continue;
      final ok = mgr.addComic(folder, c);
      if (ok) {
        moved++;
        if (removeFromSource) {
          mgr.deleteComicWithId(src.folder, c.id, c.type);
        }
      }
    }
    context.showMessage(message: "已处理 @c 本".tlParams({'c': moved}));
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    for (final c in _selected.toList()) {
      final src = _all.firstWhere((e) => e == c);
      await ShelfRecycleBin.instance.delete(src.folder, c);
    }
    context.showMessage(
        message: "已删除 @c 本，可在「最近删除」中恢复".tlParams({'c': count}));
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }
}

/// 历史 Tab
class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab>
    with AutomaticKeepAliveClientMixin {
  List<History> _history = [];

  void _reload() {
    if (mounted) {
      setState(() => _history = HistoryManager().getAll());
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _history = HistoryManager().getAll();
    HistoryManager().addListener(_reload);
  }

  @override
  void dispose() {
    HistoryManager().removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_history.isEmpty) {
      return Center(
        child: Text("暂无阅读历史".tl,
            style: TextStyle(color: context.colorScheme.outline)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _history.length,
      itemBuilder: (context, i) {
        final h = _history[i];
        return ListTile(
          leading: SizedBox(
            width: 44,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SimpleComicTile(comic: h, heroID: h.hashCode),
            ),
          ),
          title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            "第 @e 章 · 第 @p 页".tlParams({'e': h.ep, 'p': h.page}),
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => context.to(() => ComicPage(
                id: h.id,
                sourceKey: h.type.sourceKey,
                cover: h.cover,
                title: h.title,
              )),
        );
      },
    );
  }
}

/// 导入图书对话框
class _ImportComicsWidget extends StatefulWidget {
  const _ImportComicsWidget();

  @override
  State<_ImportComicsWidget> createState() => _ImportComicsWidgetState();
}

class _ImportComicsWidgetState extends State<_ImportComicsWidget> {
  int type = 0;

  bool loading = false;

  var key = GlobalKey();

  var height = 200.0;

  var folders = LocalFavoritesManager().folderNames;

  String? selectedFolder;

  bool copyToLocalFolder = true;

  @override
  Widget build(BuildContext context) {
    String info = [
      "Select a directory which contains the comic files.".tl,
      "Select a directory which contains the comic directories.".tl,
      "Select an archive file (cbz, zip, 7z, cb7)".tl,
      "Select a directory which contains multiple archive files.".tl,
      "Select an EhViewer database and a download folder.".tl,
      "Scan the current local path and restore the local database.".tl,
    ][type];
    List<String> importMethods = [
      "Single Comic".tl,
      "Multiple Comics".tl,
      "An archive file".tl,
      "Multiple archive files".tl,
      "EhViewer downloads".tl,
      "Restore local downloads".tl,
    ];

    return ContentDialog(
      dismissible: !loading,
      title: "Import Comics".tl,
      content: loading
          ? SizedBox(
              width: 600,
              height: height,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          : RadioGroup<int>(
              groupValue: type,
              onChanged: (value) {
                setState(() {
                  type = value ?? type;
                  if (type == 5) {
                    selectedFolder = null;
                  }
                });
              },
              child: Column(
                key: key,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 600),
                  ...List.generate(importMethods.length, (index) {
                    return RadioListTile<int>(
                      title: Text(importMethods[index]),
                      value: index,
                    );
                  }),
                  if (type != 4 && type != 5)
                    ListTile(
                      title: Text("Add to favorites".tl),
                      trailing: Select(
                        current: selectedFolder,
                        values: folders,
                        minWidth: 112,
                        onTap: (v) {
                          setState(() {
                            selectedFolder = folders[v];
                          });
                        },
                      ),
                    ).paddingHorizontal(8),
                  if (!App.isIOS &&
                      !App.isMacOS &&
                      type != 2 &&
                      type != 3 &&
                      type != 5)
                    CheckboxListTile(
                        enabled: true,
                        title: Text("Copy to app local path".tl),
                        value: copyToLocalFolder,
                        onChanged: (v) {
                          setState(() {
                            copyToLocalFolder = !copyToLocalFolder;
                          });
                        }).paddingHorizontal(8),
                  const SizedBox(height: 8),
                  Text(info).paddingHorizontal(24),
                ],
              ),
            ),
      actions: [
        Button.text(
          child: Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 18,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text("help".tl),
            ],
          ),
          onPressed: () {
            launchUrlString(
                "https://github.com/venera-app/venera/blob/master/doc/import_comic.md");
          },
        ).fixWidth(90).paddingRight(8),
        Button.filled(
          isLoading: loading,
          onPressed: selectAndImport,
          child: Text("Select".tl),
        )
      ],
    );
  }

  void selectAndImport() async {
    height = key.currentContext!.size!.height;

    setState(() {
      loading = true;
    });
    var importer = ImportComic(
        selectedFolder: selectedFolder, copyToLocal: copyToLocalFolder);
    var result = switch (type) {
      0 => await importer.directory(true),
      1 => await importer.directory(false),
      2 => await importer.cbz(),
      3 => await importer.multipleCbz(),
      4 => await importer.ehViewer(),
      5 => await importer.localDownloads(),
      int() => true,
    };
    if (result) {
      context.pop();
    } else {
      setState(() {
        loading = false;
      });
    }
  }
}
