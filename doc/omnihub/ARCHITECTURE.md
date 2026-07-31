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
