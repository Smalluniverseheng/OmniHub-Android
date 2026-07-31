# OmniHub 通用云端同步 Schema

> 目标：**一个存储服务，两端互通**。网页版 OmniHub（GitHub Pages PWA）与
> 安卓版 OmniHub（本仓库）共用同一套 Supabase 表，登录同一账号后数据互通。

- Supabase 项目：`mxvxlgjzeboktufumxbp`
- 认证：Supabase Auth（邮箱 + 密码），两端使用同一 anon key
- 所有用户表启用 RLS，策略统一为 `auth.uid() = user_id` 可读写

---

## 1. 表结构

### 1.1 `profiles`（已存在于网页版）

| 列 | 类型 | 说明 |
|---|---|---|
| id | uuid PK → auth.users | 用户 ID |
| email | text | 邮箱 |
| is_admin | bool | 管理员标记 |
| role | text | `admin` / `user` |
| membership | text | `free` / `member`（会员解锁 API 代理等） |
| created_at / updated_at | timestamptz | |

### 1.2 `user_settings`（键值设置，两端通用）

| 列 | 类型 | 说明 |
|---|---|---|
| user_id | uuid PK | |
| settings | jsonb | 整个设置对象（阅读器、主题、网络等），两端各自读写自己认识的键 |
| updated_at | timestamptz | 冲突解决：last-write-wins |

网页版当前 localStorage 的设置键原样放入 `settings`，App 端新增键加前缀 `app_`。

### 1.3 `user_data`（通用 KV，按模块区分）

| 列 | 类型 | 说明 |
|---|---|---|
| user_id | uuid | |
| module | text | `sources` / `bookshelf` / `history` / `favorites` / `chat` |
| key | text | 记录键（如书源 url、书籍 id） |
| value | jsonb | 记录内容 |
| updated_at | timestamptz | |
| PK | (user_id, module, key) | upsert 同步 |

同步协议：上行 = 本地变更按 `updated_at` upsert；下行 = `select * where updated_at > last_sync`。
`last_sync` 存本地（两端各自维护）。

### 1.4 模块内 `value` 约定

- `sources`：`{ name, url, type(book|comic|chat), engine(legado|venera), raw?, enabled, group, ... }`
  —— 与网页版 localStorage `omni_sources` 元素一一对应。
- `bookshelf`：`{ title, author, cover, sourceKey, latestChapter, progress:{chapterIndex, offset}, addedAt }`
- `history` / `favorites`：同网页版现有记录格式。
- `chat`：`{ conversationId, title, messages:[{role, content, ts}] }`（对话功能 M4 接入）。

---

## 2. 同步冲突策略

1. 以 `updated_at` 为准，后写覆盖先写（last-write-wins）。
2. 删除用墓碑：value 置 `{ "_deleted": true }`，保留 30 天后物理清理。
3. 首次登录：本地非空 → 提示「上传本地 / 下载云端 / 合并」。

## 3. 两端实现对应

| 端 | 模块 | 状态 |
|---|---|---|
| 网页 | `js/sync.js`（Supabase JS SDK，已有 auth） | 已有基础，按本 Schema 扩展 |
| 安卓 | `lib/omnihub/sync/`（supabase-flutter SDK） | M2 里程碑实现 |

## 4. SQL 建表（Supabase SQL Editor 执行）

```sql
create table if not exists user_settings (
  user_id uuid primary key references auth.users on delete cascade,
  settings jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists user_data (
  user_id uuid not null references auth.users on delete cascade,
  module text not null,
  key text not null,
  value jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (user_id, module, key)
);

alter table user_settings enable row level security;
alter table user_data enable row level security;

create policy "own settings" on user_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own data" on user_data
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```
