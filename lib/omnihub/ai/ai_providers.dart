/// OmniHub AI Providers - 厂商注册表
///
/// 与网页版 js/ai-providers.js 保持一致（name/format/base/keySlug/models）。
/// 三种请求格式：openai（OpenAI 兼容）、anthropic、google。
library ai_providers;

class AiProvider {
  final String name;
  final String format; // openai | anthropic | google
  final String base;
  final String keySlug;
  final int color;
  final List<String> models;
  final bool custom;

  const AiProvider({
    required this.name,
    required this.format,
    required this.base,
    required this.keySlug,
    required this.color,
    required this.models,
    this.custom = false,
  });

  /// 聊天接口地址（google 流式需带 model 与 key）
  String chatUrl(String model, String apiKey) {
    if (format == 'anthropic') return '$base/v1/messages';
    if (format == 'google') {
      return '$base/v1beta/models/$model:streamGenerateContent?alt=sse&key=$apiKey';
    }
    return '$base/v1/chat/completions';
  }

  /// 模型列表接口地址（用于测试连接）
  String modelsUrl() {
    if (format == 'anthropic') return ''; // anthropic 无公开 models 端点
    if (format == 'google') return '$base/v1beta/models';
    return '$base/v1/models';
  }

  Map<String, String> headers(String apiKey) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (format == 'anthropic') {
      h['x-api-key'] = apiKey;
      h['anthropic-version'] = '2023-06-01';
    } else if (format == 'google') {
      // google 通过 URL key 参数鉴权
    } else {
      if (apiKey.isNotEmpty) h['Authorization'] = 'Bearer $apiKey';
    }
    return h;
  }
}

class AiProviders {
  AiProviders._();

  static const List<AiProvider> providers = [
    AiProvider(
      name: 'OpenAI',
      format: 'openai',
      base: 'https://api.openai.com',
      keySlug: 'openai',
      color: 0xFF10A37F,
      models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'o4-mini'],
    ),
    AiProvider(
      name: 'DeepSeek',
      format: 'openai',
      base: 'https://api.deepseek.com',
      keySlug: 'deepseek',
      color: 0xFF4D6BFE,
      models: ['deepseek-chat', 'deepseek-reasoner'],
    ),
    AiProvider(
      name: 'Kimi',
      format: 'openai',
      base: 'https://api.moonshot.cn',
      keySlug: 'kimi',
      color: 0xFF5B8FF9,
      models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'kimi-k2-0905-preview'],
    ),
    AiProvider(
      name: '通义千问',
      format: 'openai',
      base: 'https://dashscope.aliyuncs.com/compatible-mode',
      keySlug: 'qwen',
      color: 0xFF615CED,
      models: ['qwen-plus', 'qwen-turbo', 'qwen-max'],
    ),
    AiProvider(
      name: '智谱AI',
      format: 'openai',
      base: 'https://open.bigmodel.cn/api/paas',
      keySlug: 'zhipu',
      color: 0xFF2E6BFF,
      models: ['glm-4-plus', 'glm-4-air', 'glm-4-flash'],
    ),
    AiProvider(
      name: '火山引擎',
      format: 'openai',
      base: 'https://ark.cn-beijing.volces.com/api/v3',
      keySlug: 'volcengine',
      color: 0xFFFF7A00,
      models: ['doubao-seed-1-6-250615', 'doubao-1-5-pro-32k-250115'],
    ),
    AiProvider(
      name: 'xAI',
      format: 'openai',
      base: 'https://api.x.ai',
      keySlug: 'xai',
      color: 0xFFD0D0D0,
      models: ['grok-3', 'grok-3-mini'],
    ),
    AiProvider(
      name: 'Groq',
      format: 'openai',
      base: 'https://api.groq.com/openai',
      keySlug: 'groq',
      color: 0xFFF55036,
      models: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
    ),
    AiProvider(
      name: 'Anthropic',
      format: 'anthropic',
      base: 'https://api.anthropic.com',
      keySlug: 'anthropic',
      color: 0xFFD97757,
      models: ['claude-sonnet-4-5', 'claude-haiku-4-5'],
    ),
    AiProvider(
      name: 'Google',
      format: 'google',
      base: 'https://generativelanguage.googleapis.com',
      keySlug: 'google',
      color: 0xFF4285F4,
      models: ['gemini-2.5-flash', 'gemini-2.5-pro'],
    ),
    AiProvider(
      name: '自定义',
      format: 'openai',
      base: '',
      keySlug: 'custom',
      color: 0xFF8B5CF6,
      models: [],
      custom: true,
    ),
  ];

  static const List<String> domestic = [
    'deepseek', 'kimi', 'qwen', 'zhipu', 'volcengine'
  ];
  static const List<String> foreign = [
    'openai', 'anthropic', 'google', 'xai', 'groq'
  ];

  static List<AiProvider> list() => List.of(providers);

  static AiProvider? get(String keySlug) {
    for (final p in providers) {
      if (p.keySlug == keySlug) return p;
    }
    return null;
  }

  /// 按 API Key 前缀猜测厂商（与网页版规则一致）
  static String guessKeyProvider(String apiKey) {
    final key = apiKey.trim();
    if (RegExp(r'^sk-ant-', caseSensitive: false).hasMatch(key)) {
      return 'anthropic';
    }
    if (key.startsWith('AIza')) return 'google';
    if (key.startsWith('AQ.')) return 'google';
    if (key.startsWith('gsk_')) return 'groq';
    if (RegExp(r'^xai-', caseSensitive: false).hasMatch(key)) return 'xai';
    return 'openai';
  }

  static const Map<String, String> keyUrls = {
    'openai': 'https://platform.openai.com/api-keys',
    'anthropic': 'https://console.anthropic.com/settings/keys',
    'google': 'https://aistudio.google.com/apikey',
    'deepseek': 'https://platform.deepseek.com/api_keys',
    'kimi': 'https://platform.moonshot.cn/console/api-keys',
    'qwen': 'https://bailian.console.aliyun.com/#/api-key',
    'zhipu': 'https://open.bigmodel.cn/usercenter/apikeys',
    'volcengine': 'https://console.volcengine.com/ark',
    'xai': 'https://console.x.ai/',
    'groq': 'https://console.groq.com/keys',
  };
}
