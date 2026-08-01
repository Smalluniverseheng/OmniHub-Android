/// OmniHub AI 图像/视频模型目录
///
/// 目录 ai_models.dart 只覆盖 chat 模型，这里补充主流生图/生视频模型。
/// type: image | video。provider 为目录厂商名（经 AiModels.keySlugOf 映射到
/// App 厂商 keySlug）。新增/下架模型只需改这张表。
library ai_media_models;

class AiMediaModel {
  final String id;
  final String name;
  final String provider;

  /// image | video
  final String type;
  final String? desc;
  final String? status; // new / hot / deprecated

  const AiMediaModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.type,
    this.desc,
    this.status,
  });
}

const List<AiMediaModel> kAiMediaModels = [
  // ---------------- 图像 ----------------
  AiMediaModel(
      id: 'gpt-image-2',
      name: 'GPT Image 2',
      provider: 'OpenAI',
      type: 'image',
      desc: 'OpenAI 最新图像生成模型，文字渲染与细节表现出色。',
      status: 'new'),
  AiMediaModel(
      id: 'gpt-image-1',
      name: 'GPT Image 1',
      provider: 'OpenAI',
      type: 'image'),
  AiMediaModel(
      id: 'dall-e-3',
      name: 'DALL·E 3',
      provider: 'OpenAI',
      type: 'image',
      status: 'deprecated'),
  AiMediaModel(
      id: 'doubao-seedream-4-5',
      name: 'Seedream 4.5',
      provider: '火山引擎',
      type: 'image',
      desc: '字节即梦旗舰生图，中文海报与人像表现强。',
      status: 'hot'),
  AiMediaModel(
      id: 'doubao-seedream-4-0-250828',
      name: 'Seedream 4.0',
      provider: '火山引擎',
      type: 'image'),
  AiMediaModel(
      id: 'qwen-image-max',
      name: '通义万相 Image Max',
      provider: '通义千问',
      type: 'image',
      desc: '阿里万相图像旗舰，中文文字渲染准确。'),
  AiMediaModel(
      id: 'wan2.7-image-pro',
      name: '万相 2.7 Image Pro',
      provider: '通义千问',
      type: 'image',
      status: 'new'),
  AiMediaModel(
      id: 'gemini-3-pro-image',
      name: 'Nano Banana Pro',
      provider: 'Google',
      type: 'image',
      desc: 'Gemini 3 Pro 图像生成（Nano Banana Pro）。',
      status: 'hot'),
  AiMediaModel(
      id: 'gemini-2.5-flash-image',
      name: 'Nano Banana',
      provider: 'Google',
      type: 'image'),
  AiMediaModel(
      id: 'grok-imagine-image',
      name: 'Grok Imagine Image',
      provider: 'xAI',
      type: 'image'),
  AiMediaModel(
      id: 'hunyuan-image-3.0',
      name: '混元图像 3.0',
      provider: '腾讯混元',
      type: 'image'),
  AiMediaModel(
      id: 'ernie-irag-4.0',
      name: '文心一格 4.0',
      provider: '文心一言',
      type: 'image'),
  AiMediaModel(
      id: 'kling-image-o1',
      name: '可灵 Image O1',
      provider: '快手',
      type: 'image',
      desc: '快手可灵图像模型，视频与图像创作一体化。'),

  // ---------------- 视频 ----------------
  AiMediaModel(
      id: 'doubao-seedance-1-5-pro',
      name: 'Seedance 1.5 Pro',
      provider: '火山引擎',
      type: 'video',
      desc: '字节即梦视频旗舰，多镜头叙事与音画同步。',
      status: 'new'),
  AiMediaModel(
      id: 'doubao-seedance-1-0-pro',
      name: 'Seedance 1.0 Pro',
      provider: '火山引擎',
      type: 'video'),
  AiMediaModel(
      id: 'kling-v3-omni',
      name: '可灵 V3 Omni',
      provider: '快手',
      type: 'video',
      desc: '快手可灵多模态视频模型。',
      status: 'hot'),
  AiMediaModel(
      id: 'kling-v2.5-turbo',
      name: '可灵 V2.5 Turbo',
      provider: '快手',
      type: 'video'),
  AiMediaModel(
      id: 'wan2.6',
      name: '万相 2.6',
      provider: '通义千问',
      type: 'video',
      desc: '阿里万相视频生成，新增多镜头叙事能力。',
      status: 'new'),
  AiMediaModel(
      id: 'veo-3.1',
      name: 'Veo 3.1',
      provider: 'Google',
      type: 'video',
      desc: 'Google DeepMind 视频旗舰，原生音画同出。',
      status: 'hot'),
  AiMediaModel(
      id: 'sora-2',
      name: 'Sora 2',
      provider: 'OpenAI',
      type: 'video'),
  AiMediaModel(
      id: 'grok-imagine-video',
      name: 'Grok Imagine Video',
      provider: 'xAI',
      type: 'video'),
  AiMediaModel(
      id: 'hunyuan-video-1.5',
      name: '混元视频 1.5',
      provider: '腾讯混元',
      type: 'video'),
  AiMediaModel(
      id: 'minimax-hailuo-2.3',
      name: '海螺 2.3',
      provider: 'MiniMax',
      type: 'video'),
  AiMediaModel(
      id: 'vidu-q3',
      name: 'Vidu Q3',
      provider: '生数科技',
      type: 'video',
      desc: 'Vidu Q3 画面质感强，支持智能切镜。'),
  AiMediaModel(
      id: 'pixverse-v5.6',
      name: 'PixVerse V5.6',
      provider: '爱诗科技',
      type: 'video'),
];
