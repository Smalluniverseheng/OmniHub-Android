import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/utils/translations.dart';

import '../omnihub/ai/ai_models.dart';
import '../omnihub/ai/ai_store.dart';

/// Full model catalog (ported from the web version's 293-model list).
/// Picks a model and pops with `true` when a selection was made.
class AiModelsPage extends StatefulWidget {
  const AiModelsPage({super.key});

  @override
  State<AiModelsPage> createState() => _AiModelsPageState();
}

class _AiModelsPageState extends State<AiModelsPage> {
  String _query = '';
  String _type = 'all';

  static const _types = {
    'all': 'All',
    'chat': 'Chat',
    'image': 'Image',
    'video': 'Video',
    'audio': 'Audio',
  };

  @override
  Widget build(BuildContext context) {
    final models = AiModels.search(_query, type: _type);
    // group by display provider, keep original order
    final groups = <String, List<AiModel>>{};
    for (final m in models) {
      groups.putIfAbsent(m.provider, () => []).add(m);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text("Model Catalog".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined),
            tooltip: "Leaderboard".tl,
            onPressed: () => context.to(() => const AiLeaderboardPage()),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "Search models".tl,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final e in _types.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(e.value.tl),
                          selected: _type == e.key,
                          onSelected: (_) => setState(() => _type = e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                '${entry.key} · ${entry.value.length}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.colorScheme.primary,
                ),
              ),
            ),
            for (final m in entry.value.where((e) => e.status != 'deprecated'))
              _ModelTile(m),
            // 已下线/不可用模型：默认折叠，点击展开
            if (entry.value.any((e) => e.status == 'deprecated'))
              _DeprecatedGroup(
                models: entry.value
                    .where((e) => e.status == 'deprecated')
                    .toList(),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final AiModel model;
  const _ModelTile(this.model);

  @override
  Widget build(BuildContext context) {
    final store = AiStore.instance;
    final keySlug = AiModels.keySlugOf(model.provider);
    final selected = keySlug != null &&
        keySlug == store.selectedProvider &&
        model.id == store.effectiveModel;
    final usable = keySlug != null &&
        model.type == 'chat' &&
        model.status != 'deprecated';
    return ListTile(
      dense: true,
      leading: Icon(
        model.type == 'image'
            ? Icons.image_outlined
            : model.type == 'video'
                ? Icons.videocam_outlined
                : model.type == 'audio'
                    ? Icons.graphic_eq
                    : Icons.smart_toy_outlined,
        color: usable ? null : context.colorScheme.outline,
      ),
      title: Row(
        children: [
          Flexible(child: Text(model.name, overflow: TextOverflow.ellipsis)),
          if (model.status == 'new')
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('NEW',
                  style: TextStyle(color: Colors.white, fontSize: 9)),
            ),
        ],
      ),
      subtitle: Text(
        [
          model.id,
          if (model.ctx > 0) '${model.ctx} ctx',
          if (model.vision) 'vision',
          if (model.thinking) 'thinking',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            Icon(Icons.check_circle, color: context.colorScheme.primary),
          IconButton(
            icon: Icon(Icons.info_outline,
                size: 18, color: context.colorScheme.outline),
            tooltip: "详细介绍".tl,
            visualDensity: VisualDensity.compact,
            onPressed: () => _showModelDetail(context, model, usable),
          ),
        ],
      ),
      enabled: usable,
      onTap: usable
          ? () {
              store.select(keySlug, model.id);
              context.showMessage(message: '${model.provider} · ${model.name}');
              Navigator.of(context).pop(true);
            }
          : null,
    );
  }
}

/// Model leaderboard (offline snapshot of the web version's boards).
class AiLeaderboardPage extends StatefulWidget {
  const AiLeaderboardPage({super.key});

  @override
  State<AiLeaderboardPage> createState() => _AiLeaderboardPageState();
}

class _AiLeaderboardPageState extends State<AiLeaderboardPage> {
  String _board = AiModels.boards().first;

  @override
  Widget build(BuildContext context) {
    final rows = AiModels.leaderboard(_board);
    final boards = AiModels.boards();
    return Scaffold(
      appBar: AppBar(
        title: Text("Model Leaderboard".tl),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final b in boards)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(AiModels.boardName(b)),
                      selected: _board == b,
                      onSelected: (_) => setState(() => _board = b),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              "Offline reference data".tl,
              style: TextStyle(fontSize: 12, color: context.colorScheme.outline),
            ),
          ),
          for (final r in rows) _row(r),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(LeaderboardRow r) {
    final color = switch (r.rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => context.colorScheme.outline,
    };
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.2),
        child: Text('${r.rank}',
            style: TextStyle(
                color: r.rank <= 3 ? color : context.colorScheme.outline,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ),
      title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(r.provider),
      trailing: Text(
        AiModels.scoreDisplay(_board, r.score),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onTap: () {
        final keySlug = AiModels.keySlugOf(r.provider);
        if (keySlug != null) {
          AiStore.instance.select(keySlug, r.id);
          context.showMessage(message: '${r.provider} · ${r.name}');
        }
      },
    );
  }
}


/// 已下线模型折叠组
class _DeprecatedGroup extends StatefulWidget {
  final List<AiModel> models;
  const _DeprecatedGroup({required this.models});

  @override
  State<_DeprecatedGroup> createState() => _DeprecatedGroupState();
}

class _DeprecatedGroupState extends State<_DeprecatedGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: context.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  "已下线/不可用（${widget.models.length}）".tl,
                  style: TextStyle(
                      fontSize: 12, color: context.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final m in widget.models)
            Opacity(opacity: 0.55, child: _ModelTile(m)),
      ],
    );
  }
}

/// 模型详细介绍弹窗
void _showModelDetail(BuildContext context, AiModel model, bool usable) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(model.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (model.status == 'new')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('NEW',
                        style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                if (model.status == 'deprecated')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text("已下线".tl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${model.provider} · ${model.id}',
                style: TextStyle(
                    fontSize: 12, color: ctx.colorScheme.outline)),
            const SizedBox(height: 12),
            Text(
              (model.desc?.isNotEmpty == true)
                  ? model.desc!
                  : "暂无详细介绍".tl,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (model.ctx > 0)
                  Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${model.ctx}K 上下文')),
                Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(switch (model.type) {
                      'image' => "生图",
                      'video' => "视频生成",
                      'audio' => "音频",
                      _ => "对话",
                    }.tl)),
                if (model.vision)
                  const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('识图')),
                if (model.thinking)
                  const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('深度思考')),
              ],
            ),
            if (model.note?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(model.note!,
                  style: TextStyle(
                      fontSize: 12, color: ctx.colorScheme.outline)),
            ],
            const SizedBox(height: 16),
            if (usable)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final keySlug = AiModels.keySlugOf(model.provider);
                    if (keySlug != null) {
                      AiStore.instance.select(keySlug, model.id);
                      Navigator.pop(ctx);
                      Navigator.of(context).pop(true);
                      context.showMessage(
                          message: '${model.provider} · ${model.name}');
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: Text("使用此模型".tl),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
