import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/global_state.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/omnihub/novel/book_source.dart';
import 'package:venera/omnihub/novel/legado_engine.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/pages/novel/novel_pages.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/translations.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin<ExplorePage> {
  late TabController controller;

  bool showFB = true;

  double location = 0;

  late List<String> pages;

  /// 小说/书源发现页的内置 tab id（书源含 exploreUrl 时出现）
  static const String novelExploreTabId = '\$novel_explore';

  bool get _hasNovelExplore => BookSourceManager.instance.sources
      .any((s) => s.enabled && (s.exploreUrl ?? '').isNotEmpty);

  void onSettingsChanged() {
    var explorePages = List<String>.from(appdata.settings["explore_pages"]);
    var all = ComicSource.all()
        .map((e) => e.explorePages)
        .expand((e) => e.map((e) => e.title))
        .toList();
    explorePages = explorePages.where((e) => all.contains(e)).toList();
    if (_hasNovelExplore) explorePages.add(novelExploreTabId);
    if (!pages.isEqualTo(explorePages)) {
      setState(() {
        pages = explorePages;
        controller = TabController(
          length: pages.length,
          vsync: this,
        );
      });
    }
  }

  void onNaviItemTapped(int index) {
    if (index == 2) {
      int page = controller.index;
      String currentPageId = pages[page];
      if (currentPageId == novelExploreTabId) return;
      GlobalState.find<_SingleExplorePageState>(currentPageId).toTop();
    }
  }

  void addPage() {
    showPopUpWidget(App.rootContext, setExplorePagesWidget());
  }

  NaviPaneState? naviPane;

  @override
  void initState() {
    pages = List<String>.from(appdata.settings["explore_pages"]);
    var all = ComicSource.all()
        .map((e) => e.explorePages)
        .expand((e) => e.map((e) => e.title))
        .toList();
    pages = pages.where((e) => all.contains(e)).toList();
    if (_hasNovelExplore) pages.add(novelExploreTabId);
    BookSourceManager.instance.load().then((_) {
      if (mounted) onSettingsChanged();
    });
    BookSourceManager.instance.addListener(onSettingsChanged);
    controller = TabController(
      length: pages.length,
      vsync: this,
    );
    appdata.settings.addListener(onSettingsChanged);
    NaviPane.of(context).addNaviItemTapListener(onNaviItemTapped);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    naviPane = NaviPane.of(context);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    controller.dispose();
    appdata.settings.removeListener(onSettingsChanged);
    BookSourceManager.instance.removeListener(onSettingsChanged);
    naviPane?.removeNaviItemTapListener(onNaviItemTapped);
    super.dispose();
  }

  void refresh() {
    int page = controller.index;
    String currentPageId = pages[page];
    if (currentPageId == novelExploreTabId) {
      GlobalState.find<_NovelExploreTabState>(currentPageId).refresh();
      return;
    }
    GlobalState.find<_SingleExplorePageState>(currentPageId).refresh();
  }

  Widget buildFAB() => Material(
        color: Colors.transparent,
        child: FloatingActionButton(
          key: const Key("FAB"),
          onPressed: refresh,
          child: const Icon(Icons.refresh),
        ),
      );

  Tab buildTab(String i) {
    if (i == novelExploreTabId) {
      return Tab(text: "书源发现".tl, key: Key(i));
    }
    var comicSource = ComicSource.all()
        .firstWhere((e) => e.explorePages.any((e) => e.title == i));
    return Tab(text: i.ts(comicSource.key), key: Key(i));
  }

  Widget buildBody(String i) => Material(
        child: i == novelExploreTabId
            ? _NovelExploreTab(key: PageStorageKey(i))
            : _SingleExplorePage(i, key: PageStorageKey(i)),
      );

  Widget buildEmpty() {
    var msg = "No Explore Pages".tl;
    msg += '\n';
    VoidCallback onTap;
    if (ComicSource.isEmpty) {
      msg += "Please add some sources".tl;
      onTap = () {
        context.to(() => ComicSourcePage());
      };
    } else {
      msg += "Please check your settings".tl;
      onTap = addPage;
    }
    return NetworkError(
      message: msg,
      retry: onTap,
      withAppbar: false,
      buttonText: "Manage".tl,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (pages.isEmpty) {
      return buildEmpty();
    }

    Widget tabBar = Material(
      child: AppTabBar(
        key: PageStorageKey(pages.toString()),
        tabs: pages.map((e) => buildTab(e)).toList(),
        controller: controller,
        actionButton: TabActionButton(
          icon: const Icon(Icons.add),
          text: "Add".tl,
          onPressed: addPage,
        ),
      ),
    ).paddingTop(context.padding.top);

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              tabBar,
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notifications) {
                    if (notifications.metrics.axis == Axis.horizontal) {
                      if (!showFB) {
                        setState(() {
                          showFB = true;
                        });
                      }
                      return true;
                    }

                    var current = notifications.metrics.pixels;
                    var overflow = notifications.metrics.outOfRange;
                    if (current > location && current != 0 && showFB) {
                      setState(() {
                        showFB = false;
                      });
                    } else if ((current < location - 50 || current == 0) &&
                        !showFB) {
                      setState(() {
                        showFB = true;
                      });
                    }
                    if ((current > location || current < location - 50) &&
                        !overflow) {
                      location = current;
                    }
                    return false;
                  },
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: TabBarView(
                      controller: controller,
                      children: pages.map((e) => buildBody(e)).toList(),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            reverseDuration: const Duration(milliseconds: 150),
            child: showFB ? buildFAB() : const SizedBox(),
            transitionBuilder: (widget, animation) {
              var tween = Tween<Offset>(
                  begin: const Offset(0, 1), end: const Offset(0, 0));
              return SlideTransition(
                position: tween.animate(animation),
                child: widget,
              );
            },
          ),
        )
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _SingleExplorePage extends StatefulWidget {
  const _SingleExplorePage(this.title, {super.key});

  final String title;

  @override
  State<_SingleExplorePage> createState() => _SingleExplorePageState();
}

class _SingleExplorePageState extends AutomaticGlobalState<_SingleExplorePage>
    with AutomaticKeepAliveClientMixin<_SingleExplorePage> {
  late final ExplorePageData data;

  late final String comicSourceKey;

  bool _wantKeepAlive = true;

  var scrollController = ScrollController();

  VoidCallback? refreshHandler;

  void onSettingsChanged() {
    var explorePages = appdata.settings["explore_pages"];
    if (!explorePages.contains(widget.title)) {
      _wantKeepAlive = false;
      updateKeepAlive();
    }
  }

  @override
  void initState() {
    super.initState();
    for (var source in ComicSource.all()) {
      for (var d in source.explorePages) {
        if (d.title == widget.title) {
          data = d;
          comicSourceKey = source.key;
          return;
        }
      }
    }
    appdata.settings.addListener(onSettingsChanged);
    throw "Explore Page ${widget.title} Not Found!";
  }

  @override
  void dispose() {
    appdata.settings.removeListener(onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (data.loadMultiPart != null) {
      return _MultiPartExplorePage(
        key: const PageStorageKey("comic_list"),
        data: data,
        controller: scrollController,
        comicSourceKey: comicSourceKey,
        refreshHandlerCallback: (c) {
          refreshHandler = c;
        },
      );
    } else if (data.loadPage != null || data.loadNext != null) {
      return ComicList(
        enablePageStorage: true,
        loadPage: data.loadPage,
        loadNext: data.loadNext,
        key: const PageStorageKey("comic_list"),
        controller: scrollController,
        refreshHandlerCallback: (c) {
          refreshHandler = c;
        },
      );
    } else if (data.loadMixed != null) {
      return _MixedExplorePage(
        data,
        comicSourceKey,
        key: const PageStorageKey("comic_list"),
        controller: scrollController,
        refreshHandlerCallback: (c) {
          refreshHandler = c;
        },
      );
    } else {
      return const Center(
        child: Text("Empty Page"),
      );
    }
  }

  @override
  Object? get key => widget.title;

  @override
  void refresh() {
    refreshHandler?.call();
  }

  @override
  bool get wantKeepAlive => _wantKeepAlive;

  void toTop() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }
}

class _MixedExplorePage extends StatefulWidget {
  const _MixedExplorePage(this.data, this.sourceKey,
      {super.key, this.controller, required this.refreshHandlerCallback});

  final ExplorePageData data;

  final String sourceKey;

  final ScrollController? controller;

  final void Function(VoidCallback c) refreshHandlerCallback;

  @override
  State<_MixedExplorePage> createState() => _MixedExplorePageState();
}

class _MixedExplorePageState
    extends MultiPageLoadingState<_MixedExplorePage, Object> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.refreshHandlerCallback(refresh);
  }

  void refresh() {
    reset();
  }

  Iterable<Widget> buildSlivers(BuildContext context, List<Object> data) sync* {
    List<Comic> cache = [];
    for (var part in data) {
      if (part is ExplorePagePart) {
        if (cache.isNotEmpty) {
          yield SliverGridComics(
            comics: (cache),
          );
          yield const SliverToBoxAdapter(child: Divider());
          cache.clear();
        }
        yield* _buildExplorePagePart(part, widget.sourceKey);
        yield const SliverToBoxAdapter(child: Divider());
      } else {
        cache.addAll(part as List<Comic>);
      }
    }
    if (cache.isNotEmpty) {
      yield SliverGridComics(
        comics: (cache),
      );
    }
  }

  @override
  Widget buildContent(BuildContext context, List<Object> data) {
    return SmoothCustomScrollView(
      controller: widget.controller,
      slivers: [
        ...buildSlivers(context, data),
        const SliverListLoadingIndicator(),
      ],
    );
  }

  @override
  Future<Res<List<Object>>> loadData(int page) async {
    var res = await widget.data.loadMixed!(page);
    if (res.error) {
      return res;
    }
    for (var element in res.data) {
      if (element is! ExplorePagePart && element is! List<Comic>) {
        return const Res.error("function loadMixed return invalid data");
      }
    }
    return res;
  }
}

Iterable<Widget> _buildExplorePagePart(
    ExplorePagePart part, String sourceKey) sync* {
  Widget buildTitle(ExplorePagePart part) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
          child: Row(
            children: [
              Text(
                part.title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (part.viewMore != null)
                TextButton(
                  onPressed: () {
                    var context = App.mainNavigatorKey!.currentContext!;
                    part.viewMore!.jump(context);
                  },
                  child: Text("View more".tl),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget buildComics(ExplorePagePart part) {
    return SliverGridComics(comics: part.comics);
  }

  yield buildTitle(part);
  yield buildComics(part);
}

class _MultiPartExplorePage extends StatefulWidget {
  const _MultiPartExplorePage({
    super.key,
    required this.data,
    required this.controller,
    required this.comicSourceKey,
    required this.refreshHandlerCallback,
  });

  final ExplorePageData data;

  final ScrollController controller;

  final String comicSourceKey;

  final void Function(VoidCallback c) refreshHandlerCallback;

  @override
  State<_MultiPartExplorePage> createState() => _MultiPartExplorePageState();
}

class _MultiPartExplorePageState extends State<_MultiPartExplorePage> {
  late final ExplorePageData data;

  List<ExplorePagePart>? parts;

  bool loading = true;

  String? message;

  Map<String, dynamic> get state => {
        "loading": loading,
        "message": message,
        "parts": parts,
      };

  void restoreState(dynamic state) {
    if (state == null) return;
    loading = state["loading"];
    message = state["message"];
    parts = state["parts"];
  }

  void storeState() {
    PageStorage.of(context).writeState(context, state);
  }

  void refresh() {
    setState(() {
      loading = true;
      message = null;
      parts = null;
    });
    storeState();
  }

  @override
  void initState() {
    super.initState();
    data = widget.data;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    restoreState(PageStorage.of(context).readState(context));
    widget.refreshHandlerCallback(refresh);
  }

  void load() async {
    var res = await data.loadMultiPart!();
    loading = false;
    if (mounted) {
      setState(() {
        if (res.error) {
          message = res.errorMessage;
        } else {
          parts = res.data;
        }
      });
      storeState();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      load();
      return const Center(
        child: CircularProgressIndicator(),
      );
    } else if (message != null) {
      return NetworkError(
        message: message!,
        retry: () {
          setState(() {
            loading = true;
            message = null;
          });
        },
        withAppbar: false,
      );
    } else {
      return buildPage();
    }
  }

  Widget buildPage() {
    return SmoothCustomScrollView(
      key: const PageStorageKey('scroll'),
      controller: widget.controller,
      slivers: _buildPage().toList(),
    );
  }

  Iterable<Widget> _buildPage() sync* {
    for (var part in parts!) {
      yield* _buildExplorePagePart(part, widget.comicSourceKey);
    }
  }
}

/// 书源发现 tab：漫画源 + 小说源（legado exploreUrl），统一封面网格
class _NovelExploreTab extends StatefulWidget {
  const _NovelExploreTab({super.key});

  @override
  State<_NovelExploreTab> createState() => _NovelExploreTabState();
}

class _NovelExploreTabState extends AutomaticGlobalState<_NovelExploreTab>
    with AutomaticKeepAliveClientMixin<_NovelExploreTab> {
  BookSource? _source;
  List<(String, String)> _categories = [];
  int _categoryIndex = 0;
  List<NovelBook> _books = [];
  bool _loading = false;
  String? _error;

  @override
  Object? get key => (widget.key as PageStorageKey?)?.value;

  @override
  bool get wantKeepAlive => true;

  List<BookSource> get _exploreSources => BookSourceManager.instance.sources
      .where((s) => s.enabled && (s.exploreUrl ?? '').isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    BookSourceManager.instance.load().then((_) {
      if (!mounted) return;
      final list = _exploreSources;
      if (list.isNotEmpty) {
        _selectSource(list.first);
      } else {
        setState(() {});
      }
    });
  }

  void _selectSource(BookSource s) {
    setState(() {
      _source = s;
      _categories = LegadoEngine.exploreCategories(s);
      _categoryIndex = 0;
      _books = [];
      _error = null;
    });
    if (_categories.isNotEmpty) {
      _loadCategory(0);
    }
  }

  Future<void> _loadCategory(int index) async {
    final s = _source;
    if (s == null || index >= _categories.length) return;
    setState(() {
      _categoryIndex = index;
      _loading = true;
      _error = null;
      _books = [];
    });
    try {
      final res = await LegadoEngine.explore(s, _categories[index].$2);
      if (mounted) {
        setState(() {
          _books = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void refresh() {
    if (_categories.isNotEmpty) {
      _loadCategory(_categoryIndex);
    } else if (_source != null) {
      _selectSource(_source!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sources = _exploreSources;
    if (sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "暂无支持发现功能的书源。\n导入含 exploreUrl 的小说/漫画书源后，这里会展示对应内容。"
                .tl,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colorScheme.outline),
          ),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(
                        s.mediaType == 'comic'
                            ? Icons.image_outlined
                            : Icons.menu_book_outlined,
                        size: 14),
                    label:
                        Text(s.bookSourceName, style: const TextStyle(fontSize: 12)),
                    selected: _source == s,
                    onSelected: (_) => _selectSource(s),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (_categories.isNotEmpty)
                const VerticalDivider(width: 16),
              for (var i = 0; i < _categories.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(_categories[i].$1,
                        style: const TextStyle(fontSize: 12)),
                    selected: _categoryIndex == i,
                    onSelected: (_) => _loadCategory(i),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? NetworkError(
                  message: _error!,
                  retry: refresh,
                  withAppbar: false,
                )
              : _books.isEmpty
                  ? Center(
                      child: Text(
                        _loading ? "加载中…".tl : "暂无内容".tl,
                        style:
                            TextStyle(color: context.colorScheme.outline),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 130,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _books.length,
                      itemBuilder: (_, i) {
                        final b = _books[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () =>
                              context.to(() => NovelBookPage(book: b)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: double.infinity,
                                    color: context.colorScheme
                                        .surfaceContainerHigh,
                                    child: b.cover.isEmpty
                                        ? Icon(
                                            b.mediaType == 'comic'
                                                ? Icons.image_outlined
                                                : Icons.menu_book_outlined,
                                            color: context
                                                .colorScheme.outline)
                                        : Image.network(
                                            b.cover,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Icon(Icons.broken_image_outlined,
                                                    color: context.colorScheme
                                                        .outline),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(b.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                              if (b.author.isNotEmpty)
                                Text(b.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            context.colorScheme.outline)),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
