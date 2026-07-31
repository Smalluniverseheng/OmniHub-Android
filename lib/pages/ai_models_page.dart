import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';

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
            for (final m in entry.value) _ModelTile(m),
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
    final usable = keySlug != null && model.type == 'chat';
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
          if (model.ctx != null) '${model.ctx} ctx',
          if (model.vision) 'vision',
          if (model.thinking) 'thinking',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: context.colorScheme.primary)
          : null,
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
