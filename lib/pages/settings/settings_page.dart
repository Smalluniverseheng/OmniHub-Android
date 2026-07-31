import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/omnihub/ai/ai_api.dart';
import 'package:venera/omnihub/ai/ai_providers.dart';
import 'package:venera/omnihub/ai/ai_store.dart';
import 'package:venera/omnihub/sync/omni_sync.dart';
import 'package:venera/omnihub/sync/profile.dart';
import 'package:venera/omnihub/sync/bookshelf_sync.dart';
import 'package:venera/pages/ai_chat_page.dart';
import 'package:venera/pages/ai_models_page.dart';
import 'package:venera/pages/history_page.dart';
import 'package:venera/pages/novel/novel_pages.dart';
import 'package:venera/utils/data.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';
import 'package:yaml/yaml.dart';

part 'reader.dart';
part 'explore_settings.dart';
part 'setting_components.dart';
part 'appearance.dart';
part 'local_favorites.dart';
part 'app.dart';
part 'about.dart';
part 'network.dart';
part 'omni_sync.dart';
part 'ai.dart';
part 'debug.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage = -1, super.key});

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int currentPage = -1;

  ColorScheme get colors => Theme.of(context).colorScheme;

  bool get enableTwoViews => context.width > 720;

  final categories = <String>[
    "Explore",
    "Reading",
    "Appearance",
    "Local Favorites",
    "APP",
    "Network",
    "AI",
    "Cloud Sync",
    "About",
    "Debug"
  ];

  final icons = <IconData>[
    Icons.explore,
    Icons.book,
    Icons.color_lens,
    Icons.collections_bookmark_rounded,
    Icons.apps,
    Icons.public,
    Icons.smart_toy,
    Icons.sync,
    Icons.info,
    Icons.bug_report,
  ];

  OmniProfile? _profile;

  @override
  void initState() {
    currentPage = widget.initialPage;
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await OmniProfileService.instance.fetch();
    if (mounted) setState(() => _profile = p);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: buildBody(),
    );
  }

  Widget buildBody() {
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(
            width: 280,
            height: double.infinity,
            child: buildLeft(),
          ),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return LayoutBuilder(
                  builder: (context, constrains) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        var width = constrains.maxWidth;
                        var value = animation.isForwardOrCompleted
                            ? 1 - animation.value
                            : 1;
                        var left = width * value;
                        return Stack(
                          children: [
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: width,
                              child: child,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              child: buildRight(),
            ),
          )
        ],
      );
    } else {
      return buildLeft();
    }
  }

  Widget buildLeft() {
    return Material(
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).padding.top,
          ),
          const SizedBox(height: 8),
          // 顶部用户信息卡（番茄「我的」样式）
          _buildUserCard(),
          // 快捷入口栏：只保留浏览历史
          _buildQuickBar(),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: buildCategories(),
          )
        ],
      ),
    );
  }

  Widget _buildUserCard() {
    final session = OmniSync.instance.session;
    final nickname = _profile?.nickname.isNotEmpty == true
        ? _profile!.nickname
        : (session?.email ?? '');
    final membership = _profile?.membershipLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // 点卡片 → 云同步（账号）页
          if (enableTwoViews) {
            setState(() => currentPage = 7);
          } else {
            context.to(() => const _SettingsDetailPage(pageIndex: 7));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colors.primaryContainer,
                child: session == null
                    ? Icon(Icons.person_outline,
                        size: 30, color: colors.onPrimaryContainer)
                    : Text(
                        nickname.isNotEmpty
                            ? nickname.characters.first.toUpperCase()
                            : 'U',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colors.onPrimaryContainer),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session == null ? "未登录".tl : nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (membership != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              membership,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session == null
                          ? "登录后可同步书架与数据".tl
                          : (_profile != null
                              ? "云端额度 @q".tlParams({
                                  'q': OmniProfile.fmtMb(
                                      _profile!.effectiveQuotaMb),
                                })
                              : "点击管理账号与同步".tl),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.to(() => const HistoryPage()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.history, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text("浏览历史".tl, style: ts.s16),
                ),
                Icon(Icons.chevron_right, color: colors.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCategories() {
    Widget buildItem(String name, int id) {
      final bool selected = id == currentPage;

      Widget content = AnimatedContainer(
        key: ValueKey(id),
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 46,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer.toOpacity(0.36) : null,
          border: Border(
            left: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(children: [
          Icon(icons[id]),
          const SizedBox(width: 16),
          Text(
            name,
            style: ts.s16,
          ),
          const Spacer(),
          if (selected) const Icon(Icons.arrow_right)
        ]),
      );

      return Padding(
        padding: enableTwoViews
            ? const EdgeInsets.fromLTRB(8, 0, 8, 0)
            : EdgeInsets.zero,
        child: InkWell(
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(() => _SettingsDetailPage(pageIndex: id));
            }
          },
          child: content,
        ).paddingVertical(4),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: categories.length + 1,
      itemBuilder: (context, index) {
        // 首位：书源管理（Legado 书源）
        if (index == 0) {
          return InkWell(
            onTap: () => context.to(() => const NovelSourcesPage()),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: Row(children: [
                const SizedBox(width: 12),
                const Icon(Icons.dns_outlined),
                const SizedBox(width: 16),
                Text(
                  "书源管理".tl,
                  style: ts.s16,
                ),
                const Spacer(),
                Icon(Icons.chevron_right,
                    size: 20, color: colors.outline),
                const SizedBox(width: 12),
              ]),
            ),
          );
        }
        return buildItem(categories[index - 1].tl, index - 1);
      },
    );
  }

  Widget buildRight() {
    if (currentPage == -1) {
      return const SizedBox();
    }
    return Navigator(
      onGenerateRoute: (settings) {
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return _buildSettingsContent(currentPage);
          },
          transitionDuration: Duration.zero,
        );
      },
    );
  }

  Widget _buildSettingsContent(int pageIndex) {
    return switch (pageIndex) {
      0 => const ExploreSettings(),
      1 => const ReaderSettings(),
      2 => const AppearanceSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const AppSettings(),
      5 => const NetworkSettings(),
      6 => const AiSettings(),
      7 => const OmniSyncSettings(),
      8 => const AboutSettings(),
      9 => const DebugPage(),
      _ => throw UnimplementedError()
    };
  }

}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: _buildPage(),
    );
  }

  Widget _buildPage() {
    return switch (pageIndex) {
      0 => const ExploreSettings(),
      1 => const ReaderSettings(),
      2 => const AppearanceSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const AppSettings(),
      5 => const NetworkSettings(),
      6 => const AiSettings(),
      7 => const OmniSyncSettings(),
      8 => const AboutSettings(),
      9 => const DebugPage(),
      _ => throw UnimplementedError()
    };
  }
}
