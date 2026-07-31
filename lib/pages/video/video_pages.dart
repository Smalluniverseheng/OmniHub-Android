/// OmniHub 影视模块页面
///
/// 视频源 = TVBox 接口（苹果 CMS）。包含：
/// - VideoHomePage：搜索 + 源管理
/// - VideoDetailPage：简介 + 线路 + 选集
/// - VideoPlayerPage：m3u8/mp4 播放（video_player）
library video_pages;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/omnihub/novel/source_detect.dart';
import 'package:venera/omnihub/video/tvbox.dart';
import 'package:venera/utils/translations.dart';

class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  final _searchController = TextEditingController();
  List<VideoItem> _results = [];
  bool _searching = false;
  String? _error;
  String _filterSource = ''; // 空 = 全部源

  @override
  void initState() {
    super.initState();
    TvboxSourceManager.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _searchController.text.trim();
    if (kw.isEmpty) return;
    var sources = TvboxSourceManager.instance.enabledSources;
    if (_filterSource.isNotEmpty) {
      sources = sources.where((s) => s.key == _filterSource).toList();
    }
    if (sources.isEmpty) {
      setState(() {
        _error = 'no-sources';
        _results = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    await Future.wait(sources.map((s) async {
      try {
        final res = await TvboxApi.search(s, kw);
        if (mounted && res.isNotEmpty) {
          setState(() => _results = [..._results, ...res]);
        }
      } catch (_) {}
    }));
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final mgr = TvboxSourceManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text("影视".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: "视频源管理".tl,
            onPressed: () => context
                .to(() => const VideoSourcesPage())
                .then((_) => setState(() {})),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "搜索影片…".tl,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (mgr.enabledSources.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text("全部".tl),
                      selected: _filterSource.isEmpty,
                      onSelected: (_) => setState(() => _filterSource = ''),
                    ),
                  ),
                  for (final s in mgr.enabledSources)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(s.name),
                        selected: _filterSource == s.key,
                        onSelected: (_) =>
                            setState(() => _filterSource = s.key),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _buildBody(mgr)),
        ],
      ),
    );
  }

  Widget _buildBody(TvboxSourceManager mgr) {
    if (mgr.sites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("还没有视频源".tl, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text("支持 TVBox 接口（苹果 CMS），粘贴接口 JSON 即可导入".tl,
                style: TextStyle(
                    color: context.colorScheme.outline, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context
                  .to(() => const VideoSourcesPage())
                  .then((_) => setState(() {})),
              icon: const Icon(Icons.add),
              label: Text("导入视频源".tl),
            ),
          ],
        ),
      );
    }
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error == 'no-sources') {
      return Center(child: Text("没有可用的视频源".tl));
    }
    if (_results.isEmpty) {
      return Center(
          child: Text("输入关键词搜索全网影视".tl,
              style: TextStyle(color: context.colorScheme.outline)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.58,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final v = _results[i];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.to(() => VideoDetailPage(item: v)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: v.pic.isNotEmpty
                      ? Image.network(
                          v.pic,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _picFallback(v),
                        )
                      : _picFallback(v),
                ),
              ),
              const SizedBox(height: 4),
              Text(v.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              Text('${v.site.name} ${v.remarks}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: context.colorScheme.outline)),
            ],
          ),
        );
      },
    );
  }

  Widget _picFallback(VideoItem v) => Container(
        color: context.colorScheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: Text(v.name.isEmpty ? '🎬' : v.name[0],
            style: const TextStyle(fontSize: 28)),
      );
}

/// 视频源管理页：列表 + 导入（粘贴 / URL 自动识别）
class VideoSourcesPage extends StatefulWidget {
  const VideoSourcesPage({super.key});

  @override
  State<VideoSourcesPage> createState() => _VideoSourcesPageState();
}

class _VideoSourcesPageState extends State<VideoSourcesPage> {
  final _mgr = TvboxSourceManager.instance;
  bool _importing = false;

  Future<void> _importText(String text) async {
    final detect = SourceDetect.detect(text);
    if (detect.type != SourceDetectType.tvbox) {
      context.showMessage(message: "不是 TVBox 视频源接口".tl);
      return;
    }
    final (ok, skip) = await _mgr.importConfig(detect.sources.first);
    setState(() {});
    context.showMessage(
        message: "导入 @ok 个视频源@skip"
            .tlParams({'ok': ok, 'skip': skip > 0 ? '，跳过 $skip 个不支持的源' : ''}));
  }

  Future<void> _importFromUrl(String url) async {
    setState(() => _importing = true);
    try {
      final candidates = SourceUrlResolver.candidates(url);
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20)));
      Object? lastError;
      for (final c in candidates.isEmpty ? [url] : candidates) {
        try {
          final res = await dio.get(c);
          final text = res.data is String ? res.data : '$res.data';
          final detect = SourceDetect.detect(text);
          if (detect.type == SourceDetectType.tvbox) {
            final (ok, skip) = await _mgr.importConfig(detect.sources.first);
            setState(() {});
            context.showMessage(
                message: "导入 @ok 个视频源@skip".tlParams(
                    {'ok': ok, 'skip': skip > 0 ? '，跳过 $skip 个' : ''}));
            return;
          }
        } catch (e) {
          lastError = e;
        }
      }
      context.showMessage(
          message: "未找到可用的 TVBox 接口@e"
              .tlParams({'e': lastError != null ? '：$lastError' : ''}));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("导入视频源".tl),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: "粘贴 TVBox 接口 JSON 或配置地址…".tl,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("取消".tl),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              if (text.startsWith('{') || text.startsWith('[')) {
                _importText(text);
              } else {
                _importFromUrl(text);
              }
            },
            child: Text("导入".tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("视频源管理".tl)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _showImportDialog,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text("导入".tl),
      ),
      body: _mgr.sites.isEmpty
          ? Center(child: Text("还没有视频源，点右下角导入".tl))
          : ListView.builder(
              itemCount: _mgr.sites.length,
              itemBuilder: (context, i) {
                final s = _mgr.sites[i];
                return ListTile(
                  leading:
                      Icon(s.supported ? Icons.movie_outlined : Icons.block),
                  title: Text(s.name),
                  subtitle: Text(
                    s.supported ? s.api : "该源需要爬虫支持，暂不可用".tl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: s.enabled && s.supported,
                        onChanged: s.supported
                            ? (v) async {
                                await _mgr.setEnabled(s.key, v);
                                setState(() {});
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _mgr.remove(s.key);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// 视频详情页：简介 + 线路 + 选集
class VideoDetailPage extends StatefulWidget {
  final VideoItem item;
  const VideoDetailPage({super.key, required this.item});

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  VideoDetail? _detail;
  String? _error;
  int _line = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await TvboxApi.detail(widget.item.site, widget.item);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: _error != null
          ? Center(child: Text("加载失败：$_error"))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 110,
                            height: 150,
                            child: widget.item.pic.isNotEmpty
                                ? Image.network(widget.item.pic,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.movie, size: 48))
                                : const Icon(Icons.movie, size: 48),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.item.name,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(
                                  "${widget.item.site.name} · ${widget.item.remarks}",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.colorScheme.outline)),
                              const SizedBox(height: 8),
                              Text(
                                d.intro,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (d.playFrom.length > 1)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (var i = 0; i < d.playFrom.length; i++)
                            ChoiceChip(
                              label: Text(d.playFrom[i]),
                              selected: _line == i,
                              onSelected: (_) => setState(() => _line = i),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (d.episodes.isEmpty)
                      Text("该源未返回播放地址".tl)
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 110,
                          childAspectRatio: 2.4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: d.episodes[_line].length,
                        itemBuilder: (context, i) {
                          final (name, url) = d.episodes[_line][i];
                          return FilledButton.tonal(
                            style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                textStyle: const TextStyle(fontSize: 12)),
                            onPressed: () => context.to(() =>
                                VideoPlayerPage(title: name, url: url)),
                            child: Text(name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        },
                      ),
                  ],
                ),
    );
  }
}

/// 播放器页（video_player，支持 m3u8/mp4）
class VideoPlayerPage extends StatefulWidget {
  final String title;
  final String url;
  const VideoPlayerPage({super.key, required this.title, required this.url});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.play();
      if (mounted) setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text("播放失败：$_error",
                        style: const TextStyle(color: Colors.white70)),
                  )
                : c == null
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
          ),
          Positioned(
            top: context.padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            top: context.padding.top + 8,
            left: 56,
            right: 16,
            child: Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          if (c != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PlayerControls(controller: c),
            ),
        ],
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final VideoPlayerController controller;
  const _PlayerControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {
        return Container(
          color: Colors.black45,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () =>
                    value.isPlaying ? controller.pause() : controller.play(),
              ),
              Expanded(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_fmt(value.position)} / ${_fmt(value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    }
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }
}
