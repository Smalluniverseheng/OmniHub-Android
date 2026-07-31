# OmniHub（安卓版）

> 一款把 **漫画（Venera）** + **小说（开源阅读 Legado 规则）** 融合在一起的全能阅读 App，
> 配合 Supabase 云端同步，与 [OmniHub 网页版](https://smalluniverseheng.github.io/OmniHub/) **数据互通**。

本项目基于上游开源项目 [venera-app/venera](https://github.com/venera-app/venera)
（GPL-3.0，已停止维护并鼓励 fork）构建，并移植 [Legado 开源阅读](https://github.com/gedoor/legado)
的书源规则引擎（Dart 实现）。遵循 GPL-3.0 开源协议。

## 特性规划

- ✅ 漫画阅读（Venera 原版代码：本地漫画、JS 漫画源、收藏、下载）
- 🚧 小说阅读（Legado 书源规则引擎 Dart 移植，搜索/发现/正文/换源）
- 🚧 云端同步（Supabase：书源、书架、阅读进度、收藏、设置，与网页版互通）
- 🚧 AI 对话（集成开源 Flutter 聊天 UI）

## 架构与文档

- [doc/omnihub/ARCHITECTURE.md](doc/omnihub/ARCHITECTURE.md) —— 融合架构与里程碑
- [doc/omnihub/SYNC_SCHEMA.md](doc/omnihub/SYNC_SCHEMA.md) —— 云端同步表结构（网页/App 通用）

## 构建

无需本地环境：推送 tag（如 `v1.6`）后 GitHub Actions 自动构建 APK，
在 Actions 产物（artifact）或 Releases 中下载 `OmniHub-*-arm64-v8a.apk`。

本地构建见上游说明：安装 Flutter 3.41.4 + Rust（rustup），然后 `flutter build apk`。

## 致谢

- [venera-app/venera](https://github.com/venera-app/venera) —— 漫画底座（GPL-3.0）
- [gedoor/legado](https://github.com/gedoor/legado) —— 书源规则设计（GPL-3.0）
