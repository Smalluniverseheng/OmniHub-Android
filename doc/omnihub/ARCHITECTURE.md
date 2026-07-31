# OmniHub-Android 架构规划

> 目标：一个原生体验的安卓 App = **Legado（开源阅读）书源生态** + **Venera 漫画图源引擎** + **开源对话 UI**，
> 云端只做一个角色——**通用存储与同步服务**（Supabase），网页版 OmniHub 与安卓 App 数据完全互通。

## 一、技术底座决策

| 层 | 选型 | 理由 |
|---|---|---|
| 应用框架 | **Flutter**（以 Venera 原代码为底座） | Venera 本身就是 Flutter，漫画/图文阅读器、JS 图源引擎（flutter_qjs）、收藏/历史/下载全部现成，GPL-3.0 允许二次开发 |
| 小说书源 | **Legado 规则引擎 Dart 移植** | Legado 是 Kotlin，无法直接并入 Flutter。但其规则引擎是纯规则解析（XPath/JSONPath/CSS/JS 注入），我们在网页版已完成 JS 实现（legado-engine.js），按同一套语义移植 Dart，直接兼容海量现成 Legado 书源 JSON |
| 漫画图源 | **Venera 原生 JS 引擎**（flutter_qjs） | 原样保留，直接跑 venera-configs 官方仓库 |
| 对话 | 开源 Flutter 聊天 UI（flutter_chat_ui 系）+ OpenAI 兼容协议层 | 不自研 UI，接各家厂商 API |
| 云同步 | **Supabase**（与网页版同一项目 mxvxlgjzeboktufumxbp） | supabase-flutter 官方 SDK；表结构与网页版共用，见 SYNC_SCHEMA.md |

## 二、模块划分

```
lib/
  (Venera 原有)           —— 漫画阅读/收藏/下载/JS 图源引擎，保持原样
  omnihub/
    legado/               —— Legado 引擎 Dart 移植（search/bookInfo/toc/content）
    novel/                —— 小说书架/阅读器页（复用 Venera 组件风格）
    chat/                 —— 对话模块（开源聊天 UI + 厂商 API 层）
    sync/                 —— Supabase 同步层（认证 + 增量同步 + 冲突合并）
    bridge/               —— 网页版数据模型互转（书架/进度/书源/设置）
```

## 三、融合步骤（里程碑）

1. **M1 底座可构建**：Venera 改名 OmniHub，CI 出 APK（本提交）
2. **M2 同步骨架**：Supabase 登录（邮箱/密码，与网页版同账号体系），收藏/历史/设置上云，网页端↔App 互相可见
3. **M3 Legado 引擎**：Dart 移植 + 小说书架/阅读器，导入 Legado JSON 书源
4. **M4 对话模块**：开源聊天 UI 接入，OpenAI 兼容协议，Key 与网页版互通
5. **M5 全量同步**：书源列表、阅读进度、对话记录全量双向同步

## 四、合规

- Venera / Legado 均为 GPL-3.0，本仓库整体继承 GPL-3.0，保留上游版权声明与 LICENSE
- 不内置任何第三方书源/图源内容，仅提供引擎与用户自导入能力

## v1.8 AI 模块（2026-07-31）

- `lib/omnihub/ai/`：AI 核心层
  - `ai_providers.dart`：厂商注册表，与网页版 js/ai-providers.js 对齐（openai/anthropic/google 三格式）
  - `ai_api.dart`：dio 直连用户 API（BYOK），三格式 SSE 流式输出 + validateKey 测试连接
  - `ai_store.dart`：Key/选中模型/对话记录本地 JSON 持久化（Key 仅本地，不上云）
  - `annotations.dart`：阅读注释（手写笔记 + AI 问答留痕，参考 read-aware ask-note），
    经 Supabase user_data 表 module=annotations 与网页端互通（含墓碑删除）
- UI：设置页新增「AI」分类（BYOK 填 Key/选模型/测试连接）；主页搜索栏右侧 AI 对话入口；
  漫画详情页菜单新增「问 AI」（携带书名/简介/标签/章节上下文开聊）与「注释」页

## v1.9.0 更新笔记（2026-07-31）

### AI 模型目录 + 排行榜
- `lib/omnihub/ai/ai_models.dart` + `ai_models_data.dart`（part）：移植网页版 js/ai-models.js 全部 293 个模型 + js/leaderboard-data.js 六榜单 Top10（离线快照，随版本更新）。
- `AiModels.keySlugOf()`：目录厂商名 → App keySlug 映射（含别名表：月之暗面→kimi、字节跳动→volcengine 等），未接入厂商返回 null（目录中置灰不可选）。
- `lib/pages/ai_models_page.dart`：模型目录页（搜索 + 类型筛选 + 按厂商分组）与排行榜页（六榜单 ChoiceChip、金银铜前三名、"离线参考数据"标注）。入口：AI 设置页两按钮、AI 对话列表页排行榜图标；AI 设置中模型下拉改为"从目录选择"。

### 底部导航（main_page.dart）
- 新导航：主页 / AI / 发现 / 分类 / 设置。收藏（FavoritesPage）并入主页 Tab；设置从 paneAction 变为导航项。

### 主页重构（home_page.dart，番茄书架式）
- 顶部 5 Tab（书架/历史/收藏/小说/圈子，TabBarView 可左右滑动）+ 搜索 + 三点菜单。
- 三点菜单：连载更新提醒 / 切换宫格列表（appdata.settings['shelfDisplayMode']）/ 云同步管理 / 导入图书 / 书架展示设置 / 最近删除。
- 书架 Tab：宫格/列表双模式；长按进入多选（全选、移动至分组、加入书单、删除→回收站；找相似书/加入桌面占位）；进度文案来自 HistoryManager.find。
- 顶部筛选 chips（全部/阅读/听书/短剧/漫剧 + 筛选页入口），听书/短剧/漫剧为后续版本占位，显隐由书架展示设置控制。

### 子页面（lib/pages/shelf/shelf_subpages.dart）
- ShelfFilterPage：分组/阅读状态（未读/在读/读完）/仅已下载/标签多维筛选。
- ShelfDisplaySettingsPage：短剧/漫剧/互动开关、推荐内容、刷新方式。
- CloudSyncManagePage：同步开关（appdata['omniShelfCloudSync']）、会员额度进度条（读 Supabase profiles.membership；free=1GB/vip=2GB/svip=10GB）、BookshelfSync 立即同步、从电脑/本机导入入口。
- ReadingStatsPage：总时长/次数/日均/书籍数/最长单次/今日 + 本周柱状趋势；同步走 user_data module='stats'。
- RecentlyDeletedPage：回收站（lib/omnihub/shelf/recycle_bin.dart，30 天保留，可恢复/彻底删除）。

### 阅读统计（lib/omnihub/stats/reading_stats.dart）
- Reader initState→startSession()、dispose→endSession()，<5s 不计、>4h 截断；按天聚合 JSON 存储；小说阅读器同样挂钩。

### 小说模块（Legado 书源引擎 Dart 移植）
- `lib/omnihub/novel/legado_engine.dart`：完整移植网页版 legado-engine.js 规则语义——CSS(JSoup 简写)/JSONPath(简易)/XPath(常用子集，自研求值器)/JS 段（JsEngine.runCode + JS 版 java stub：put/get/ajax(空)/md5/base64）、##正则尾部、||、&&、{{}} 插值、@js: 尾段、目录/正文分页（5/3 页上限）、图片章节判定。
- `lib/omnihub/novel/book_source.dart`：BookSource/NovelBook/NovelChapter/NovelContent 模型；BookSourceManager（导入 JSON 数组/单对象）；NovelShelf（小说书架 + 章节进度）。
- `lib/pages/novel/novel_pages.dart`：NovelTab（主页小说 Tab）、书源管理（剪贴板/文件/粘贴导入）、多书源并发搜索页、详情+目录页、正文阅读器（字号调节、上下章、阅读计时）。

### 版本号
- pubspec: 1.9.0+190。安卓允许 x.y.z+build（网页版仍严格 x.y）。
