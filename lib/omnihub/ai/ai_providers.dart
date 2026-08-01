/// OmniHub AI Providers - 厂商注册表
///
/// 与 aiBeta js/providers.js（23 家目录厂商）对齐，另加 4 家聚合平台
/// （OpenRouter / SiliconFlow / Together / Fireworks，单 Key 可用 200+ 模型）。
/// 三种请求格式：openai（OpenAI 兼容）、anthropic、google。
/// 品牌图标：lobe / simpleicons slug 供 BrandIcon 使用（真商标，非首字母）。
library ai_providers;

class AiProvider {
  final String name;
  final String format; // openai | anthropic | google
  final String base;
  final String keySlug;
  final int color;
  final List<String> models;
  final bool custom;

  /// lobehub icons slug（真商标图标），可空
  final String? iconLobe;

  /// simpleicons slug（备用商标图标），可空
  final String? iconSimple;

  const AiProvider({
    required this.name,
    required this.format,
    required this.base,
    required this.keySlug,
    required this.color,
    required this.models,
    this.custom = false,
    this.iconLobe,
    this.iconSimple,
  });

  /// 拼接版本化路径：base 已带 /v1、/v2、/v3 等版本段时直接拼接
  String _versioned(String path) {
    if (RegExp(r'/v\d+[a-z]*$').hasMatch(base)) return '$base$path';
    return '$base/v1$path';
  }

  /// 聊天接口地址（google 流式需带 model 与 key）
  String chatUrl(String model, String apiKey) {
    if (format == 'anthropic') return _versioned('/messages');
    if (format == 'google') {
      return '$base/v1beta/models/$model:streamGenerateContent?alt=sse&key=$apiKey';
    }
    return _versioned('/chat/completions');
  }

  /// 模型列表接口地址（用于测试连接）
  String modelsUrl() {
    if (format == 'anthropic') return ''; // anthropic 无公开 models 端点
    if (format == 'google') return '$base/v1beta/models';
    return _versioned('/models');
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
    // ---------------- 国内厂商 ----------------
    AiProvider(
      name: 'DeepSeek',
      format: 'openai',
      base: 'https://api.deepseek.com',
      keySlug: 'deepseek',
      color: 0xFF0066FF,
      iconLobe: 'deepseek-color',
      iconSimple: 'deepseek',
      models: ['deepseek-chat', 'deepseek-reasoner', 'deepseek-v4-pro'],
    ),
    AiProvider(
      name: 'Kimi',
      format: 'openai',
      base: 'https://api.moonshot.cn',
      keySlug: 'kimi',
      color: 0xFF6236FF,
      iconLobe: 'kimi-color',
      iconSimple: 'moonshot',
      models: ['kimi-k2', 'kimi-k2.5', 'moonshot-v1-32k'],
    ),
    AiProvider(
      name: '通义千问',
      format: 'openai',
      base: 'https://dashscope.aliyuncs.com/compatible-mode',
      keySlug: 'qwen',
      color: 0xFFFF6A00,
      iconLobe: 'qwen-color',
      iconSimple: 'alibabadotcom',
      models: ['qwen-plus', 'qwen-turbo', 'qwen-max', 'qwen3-max'],
    ),
    AiProvider(
      name: '智谱AI',
      format: 'openai',
      base: 'https://open.bigmodel.cn/api/paas',
      keySlug: 'zhipu',
      color: 0xFF2B5CE6,
      iconLobe: 'chatglm-color',
      iconSimple: 'zhipu',
      models: ['glm-4-plus', 'glm-4-air', 'glm-4-flash', 'glm-5'],
    ),
    AiProvider(
      name: '火山引擎',
      format: 'openai',
      base: 'https://ark.cn-beijing.volces.com/api/v3',
      keySlug: 'volcengine',
      color: 0xFF3B7DF0,
      iconLobe: 'doubao-color',
      iconSimple: 'bytedance',
      models: ['doubao-seed-1-6-250615', 'doubao-1-5-pro-32k-250115'],
    ),
    AiProvider(
      name: '小米 MiMo',
      format: 'openai',
      base: 'https://api.xiaomimimo.com',
      keySlug: 'mimo',
      color: 0xFFFF6900,
      iconLobe: 'xiaomimimo',
      iconSimple: 'xiaomi',
      models: ['mimo-v2.5', 'mimo-v2.5-pro'],
    ),
    AiProvider(
      name: '文心一言',
      format: 'openai',
      base: 'https://qianfan.baidubce.com/v2',
      keySlug: 'ernie',
      color: 0xFF2319DC,
      iconLobe: 'wenxin-color',
      iconSimple: 'baidu',
      models: ['ernie-4.5-turbo', 'ernie-4.0-turbo-8k', 'ernie-speed'],
    ),
    AiProvider(
      name: '腾讯混元',
      format: 'openai',
      base: 'https://api.hunyuan.cloud.tencent.com',
      keySlug: 'hunyuan',
      color: 0xFF07C160,
      iconLobe: 'hunyuan-color',
      iconSimple: 'tencentqq',
      models: ['hunyuan-turbos', 'hunyuan-standard', 'hunyuan-lite-v2'],
    ),
    AiProvider(
      name: 'MiniMax',
      format: 'openai',
      base: 'https://api.minimax.chat',
      keySlug: 'minimax',
      color: 0xFF000000,
      iconLobe: 'minimax-color',
      models: ['minimax-m2.5', 'minimax-m3', 'abab6.5s-chat'],
    ),
    AiProvider(
      name: '零一万物',
      format: 'openai',
      base: 'https://api.lingyiwanwu.com',
      keySlug: 'yi',
      color: 0xFF000000,
      iconLobe: 'yi',
      models: ['yi-large', 'yi-lightning', 'yi-34b-chat'],
    ),
    AiProvider(
      name: '阶跃星辰',
      format: 'openai',
      base: 'https://api.stepfun.com',
      keySlug: 'stepfun',
      color: 0xFF4F46E5,
      iconLobe: 'stepfun-color',
      models: ['step-2-16k', 'step-2-mini', 'step-1-32k'],
    ),
    AiProvider(
      name: '百川智能',
      format: 'openai',
      base: 'https://api.baichuan-ai.com',
      keySlug: 'baichuan',
      color: 0xFF2B5CE6,
      iconLobe: 'baichuan-color',
      models: ['Baichuan4', 'Baichuan3-Turbo'],
    ),
    AiProvider(
      name: '讯飞星火',
      format: 'openai',
      base: 'https://spark-api-open.xf-yun.com',
      keySlug: 'spark',
      color: 0xFF2B5CE6,
      iconLobe: 'spark-color',
      iconSimple: 'iflytek',
      models: ['spark-max', 'spark-pro', 'spark-lite'],
    ),
    AiProvider(
      name: '昆仑万维',
      format: 'openai',
      base: 'https://api.skywork.ai',
      keySlug: 'kunlun',
      color: 0xFF6D28D9,
      iconLobe: 'skywork-color',
      models: ['skywork-math', 'skywork-13b'],
    ),
    AiProvider(
      name: '商汤',
      format: 'openai',
      base: 'https://api.sensenova.cn',
      keySlug: 'sensetime',
      color: 0xFF0052CC,
      iconLobe: 'sensetime-color',
      iconSimple: 'sensetime',
      models: ['SenseChat-5', 'SenseChat-128K'],
    ),
    // ---------------- 聚合平台（单 Key 200+ 模型） ----------------
    AiProvider(
      name: 'OpenRouter',
      format: 'openai',
      base: 'https://openrouter.ai/api',
      keySlug: 'openrouter',
      color: 0xFF6467F2,
      iconLobe: 'openrouter',
      models: ['openai/gpt-4o', 'anthropic/claude-sonnet-4.5', 'google/gemini-2.5-flash'],
    ),
    AiProvider(
      name: 'SiliconFlow',
      format: 'openai',
      base: 'https://api.siliconflow.cn',
      keySlug: 'siliconflow',
      color: 0xFF7B61FF,
      iconLobe: 'siliconcloud-color',
      models: ['Qwen/Qwen2.5-72B-Instruct', 'deepseek-ai/DeepSeek-V3', 'Pro/deepseek-ai/DeepSeek-R1'],
    ),
    AiProvider(
      name: 'Together AI',
      format: 'openai',
      base: 'https://api.together.xyz',
      keySlug: 'together',
      color: 0xFF0F6FFF,
      iconLobe: 'together',
      models: ['meta-llama/Llama-3.3-70B-Instruct-Turbo', 'deepseek-ai/DeepSeek-V3'],
    ),
    AiProvider(
      name: 'Fireworks AI',
      format: 'openai',
      base: 'https://api.fireworks.ai/inference',
      keySlug: 'fireworks',
      color: 0xFFF25C05,
      iconLobe: 'fireworks',
      models: ['accounts/fireworks/models/llama-v3p3-70b-instruct'],
    ),
    // ---------------- 国际厂商 ----------------
    AiProvider(
      name: 'OpenAI',
      format: 'openai',
      base: 'https://api.openai.com',
      keySlug: 'openai',
      color: 0xFF10A37F,
      iconLobe: 'openai',
      iconSimple: 'openai',
      models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'o4-mini'],
    ),
    AiProvider(
      name: 'Anthropic',
      format: 'anthropic',
      base: 'https://api.anthropic.com',
      keySlug: 'anthropic',
      color: 0xFFD97757,
      iconLobe: 'anthropic',
      iconSimple: 'anthropic',
      models: ['claude-sonnet-4-5', 'claude-haiku-4-5'],
    ),
    AiProvider(
      name: 'Google',
      format: 'google',
      base: 'https://generativelanguage.googleapis.com',
      keySlug: 'google',
      color: 0xFF4285F4,
      iconLobe: 'gemini-color',
      iconSimple: 'googlegemini',
      models: ['gemini-2.5-flash', 'gemini-2.5-pro'],
    ),
    AiProvider(
      name: 'xAI',
      format: 'openai',
      base: 'https://api.x.ai',
      keySlug: 'xai',
      color: 0xFF333333,
      iconLobe: 'xai',
      iconSimple: 'x',
      models: ['grok-3', 'grok-3-mini', 'grok-4.1-fast'],
    ),
    AiProvider(
      name: 'Groq',
      format: 'openai',
      base: 'https://api.groq.com/openai',
      keySlug: 'groq',
      color: 0xFFF55036,
      iconLobe: 'groq',
      iconSimple: 'groq',
      models: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
    ),
    AiProvider(
      name: 'Mistral',
      format: 'openai',
      base: 'https://api.mistral.ai',
      keySlug: 'mistral',
      color: 0xFFFF7000,
      iconLobe: 'mistral-color',
      iconSimple: 'mistral',
      models: ['mistral-large-3', 'mistral-small-4', 'codestral-latest'],
    ),
    AiProvider(
      name: 'Meta',
      format: 'openai',
      base: 'https://api.llama.com',
      keySlug: 'meta',
      color: 0xFF0668E1,
      iconLobe: 'meta-color',
      iconSimple: 'meta',
      models: ['llama-4-maverick', 'llama-4-scout', 'llama-3.3-70b'],
    ),
    AiProvider(
      name: 'Cohere',
      format: 'openai',
      base: 'https://api.cohere.com/compatibility',
      keySlug: 'cohere',
      color: 0xFF39594D,
      iconLobe: 'cohere',
      iconSimple: 'cohere',
      models: ['command-a', 'command-r-plus', 'command-r'],
    ),
    // ---------------- 自定义 ----------------
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
    'deepseek', 'kimi', 'qwen', 'zhipu', 'volcengine', 'mimo', 'ernie',
    'hunyuan', 'minimax', 'yi', 'stepfun', 'baichuan', 'spark', 'kunlun',
    'sensetime',
  ];
  static const List<String> aggregators = [
    'openrouter', 'siliconflow', 'together', 'fireworks',
  ];
  static const List<String> foreign = [
    'openai', 'anthropic', 'google', 'xai', 'groq', 'mistral', 'meta', 'cohere',
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
    if (RegExp(r'^sk-or-', caseSensitive: false).hasMatch(key)) {
      return 'openrouter';
    }
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
    'mimo': 'https://platform.xiaomimimo.com/',
    'ernie': 'https://qianfan.cloud.baidu.com/',
    'hunyuan': 'https://cloud.tencent.com/product/hunyuan',
    'minimax': 'https://platform.minimaxi.com/',
    'yi': 'https://platform.lingyiwanwu.com/',
    'stepfun': 'https://platform.stepfun.com/',
    'baichuan': 'https://platform.baichuan-ai.com/',
    'spark': 'https://xinghuo.xfyun.cn/',
    'kunlun': 'https://platform.skywork.ai/',
    'sensetime': 'https://platform.sensenova.cn/',
    'openrouter': 'https://openrouter.ai/keys',
    'siliconflow': 'https://cloud.siliconflow.cn/account/ak',
    'together': 'https://api.together.xyz/settings/api-keys',
    'fireworks': 'https://fireworks.ai/account/api-keys',
    'xai': 'https://console.x.ai/',
    'groq': 'https://console.groq.com/keys',
    'mistral': 'https://console.mistral.ai/api-keys',
    'meta': 'https://llama.developer.meta.com/',
    'cohere': 'https://dashboard.cohere.com/api-keys',
  };
}
