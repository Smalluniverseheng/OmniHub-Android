/// OmniHub AI 模型目录（与网页版 js/ai-models.js 对齐）
///
/// 提供 293 个模型的查询/搜索/分组，以及厂商名 → keySlug 映射。
library ai_models;


part 'ai_models_data.dart';

class AiModel {
  final String id;
  final String name;
  final String provider; // 目录厂商名（可能是 App 未接入的厂商）
  final String type; // chat / tts / image / asr ...
  final int ctx; // 上下文（K tokens）
  final bool vision;
  final bool thinking;
  final String? status; // new / hot / deprecated
  final String? desc;
  final String? note;
  final String? category;

  const AiModel({
    required this.id,
    required this.name,
    required this.provider,
    this.type = 'chat',
    this.ctx = 0,
    this.vision = false,
    this.thinking = false,
    this.status,
    this.desc,
    this.note,
    this.category,
  });

  factory AiModel.fromJson(Map<String, Object?> j) => AiModel(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? (j['id'] as String? ?? ''),
        provider: j['provider'] as String? ?? '',
        type: j['type'] as String? ?? 'chat',
        ctx: (j['ctx'] as num?)?.toInt() ?? 0,
        vision: j['vision'] == true,
        thinking: j['thinking'] == true,
        status: j['status'] as String?,
        desc: j['desc'] as String?,
        note: j['note'] as String?,
        category: j['category'] as String?,
      );
}

class LeaderboardRow {
  final int rank;
  final String id;
  final String name;
  final String provider;
  final double score;

  const LeaderboardRow(
      {required this.rank,
      required this.id,
      required this.name,
      required this.provider,
      required this.score});
}

class AiModels {
  AiModels._();

  static List<AiModel>? _cache;

  static List<AiModel> list() {
    return _cache ??= kAiModelsData.map(AiModel.fromJson).toList();
  }

  static AiModel? get(String id) {
    for (final m in list()) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<AiModel> byType(String type) {
    if (type == 'all') return list();
    return list().where((m) => m.type == type).toList();
  }

  static List<AiModel> search(String keyword, {String type = 'all'}) {
    final kw = keyword.trim().toLowerCase();
    var res = list();
    if (type != 'all') res = res.where((m) => m.type == type).toList();
    if (kw.isEmpty) return res;
    return res
        .where((m) =>
            m.id.toLowerCase().contains(kw) ||
            m.name.toLowerCase().contains(kw) ||
            m.provider.toLowerCase().contains(kw))
        .toList();
  }

  /// 目录厂商名 → App 厂商 keySlug（与网页版 mapModelProvider 对齐，含别名表）
  static const Map<String, String> _providerAlias = {
    '月之暗面': 'kimi',
    '字节跳动': 'volcengine',
    'OpenAI': 'openai',
    'DeepSeek': 'deepseek',
    'Kimi': 'kimi',
    '通义千问': 'qwen',
    '智谱AI': 'zhipu',
    '火山引擎': 'volcengine',
    'xAI': 'xai',
    'Groq': 'groq',
    'Anthropic': 'anthropic',
    'Google': 'google',
    '小米 MiMo': 'mimo',
    '文心一言': 'ernie',
    '腾讯混元': 'hunyuan',
    'MiniMax': 'minimax',
    '零一万物': 'yi',
    '阶跃星辰': 'stepfun',
    '百川智能': 'baichuan',
    '讯飞星火': 'spark',
    '昆仑万维': 'kunlun',
    '商汤': 'sensetime',
    'Mistral': 'mistral',
    'Meta': 'meta',
    'Cohere': 'cohere',
  };

  /// 返回 null 表示 App 未接入该厂商（目录展示用，不可直接配置）
  static String? keySlugOf(String providerName) =>
      _providerAlias[providerName];

  /// 某 App 厂商可用的目录模型（type=chat）
  static List<AiModel> forProvider(String keySlug) {
    return list()
        .where((m) => m.type == 'chat' && keySlugOf(m.provider) == keySlug)
        .toList();
  }

  static List<String> providers() {
    final seen = <String>{};
    final out = <String>[];
    for (final m in list()) {
      if (seen.add(m.provider)) out.add(m.provider);
    }
    return out;
  }

  // ---------------- 排行榜 ----------------

  static List<String> boards() => kLeaderboardNames.keys.toList();

  static String boardName(String board) => kLeaderboardNames[board] ?? board;

  static List<LeaderboardRow> leaderboard(String board) {
    final rows = kLeaderboardData[board] ?? [];
    return [
      for (var i = 0; i < rows.length; i++)
        LeaderboardRow(
          rank: i + 1,
          id: rows[i]['id'] as String,
          name: rows[i]['name'] as String,
          provider: rows[i]['provider'] as String,
          score: (rows[i]['score'] as num).toDouble(),
        )
    ];
  }

  static String scoreDisplay(String board, double score) {
    if (board == 'value') return '¥${score.toStringAsFixed(1)}/M';
    return score.toStringAsFixed(1);
  }
}
