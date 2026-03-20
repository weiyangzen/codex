# DIR `codex-rs/cloud-requirements` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-requirements`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-cloud-requirements`

## 场景与职责

`codex-rs/cloud-requirements` 的定位是“云端托管 requirements.toml 的拉取与本地缓存层”，服务于配置加载链路中的受管约束（managed requirements）。它不直接决定配置字段语义，而是负责把后端下发的 requirements 文本安全、可恢复地交给 `CloudRequirementsLoader`，再由 `codex-core/config_loader` 合并到最终配置约束。

核心职责：

1. 按账号类型决定是否启用云要求
- 仅对 ChatGPT 登录且 `PlanType` 为 `Business|Enterprise` 的账号生效；其余登录形态返回 `Ok(None)`（不启用云要求）。
- 入口判定在 `CloudRequirementsService::fetch()`（`codex-rs/cloud-requirements/src/lib.rs:326-337`）。

2. fail-closed 拉取策略
- 对符合条件账号，启动阶段拉取失败会返回 `CloudRequirementsLoadError`，并让配置加载失败，而不是静默降级。
- 超时、请求耗尽、解析失败、401 认证失败均有明确错误码（`Auth/Timeout/Parse/RequestFailed/Internal`）和消息。

3. 认证恢复与重试
- 通过 `AuthManager::unauthorized_recovery()` 处理 401：先尝试“同账号 reload”，再尝试 token refresh；外部 token 模式走 external refresher。
- 重试上限 5 次，使用指数退避 + jitter（来自 `codex_core::util::backoff`）。

4. 本地缓存与完整性校验
- 缓存文件：`$CODEX_HOME/cloud-requirements-cache.json`。
- 缓存载荷包含 `cached_at/expires_at/chatgpt_user_id/account_id/contents`，并带 HMAC-SHA256 签名。
- 读取时校验签名、身份一致性、TTL，有效则直接命中，减少冷启动依赖后端可用性。

5. 后台刷新
- 启动加载后还会启动后台刷新任务，固定每 5 分钟轮询远端更新缓存（超时/错误保留旧缓存）。

## 功能点目的

### 1) `cloud_requirements_loader` / `cloud_requirements_loader_for_storage`

- 目的：向上游提供 `CloudRequirementsLoader`（shared future 语义），屏蔽拉取、重试、缓存、刷新细节。
- `cloud_requirements_loader(...)` 接收已有 `AuthManager`；`cloud_requirements_loader_for_storage(...)` 内部按 `codex_home + credentials_store_mode` 构造 `AuthManager`（`lib.rs:689-735`）。
- 同时启动：
  - 一次性启动拉取任务（返回给 loader）；
  - 持续后台刷新任务（写入静态 `OnceLock<Mutex<Option<JoinHandle>>>` 槽位，替换旧任务）。

### 2) `CloudRequirementsService::fetch_with_timeout`（启动阶段）

- 目的：给启动拉取设置硬超时（15s），避免配置加载无限阻塞。
- 超时返回 `CloudRequirementsLoadErrorCode::Timeout`，并打 `codex.cloud_requirements.load` 错误指标。

### 3) `CloudRequirementsService::fetch`（门控 + 缓存优先）

- 目的：先做 auth/plan 门控，再“先读缓存，后访远端”。
- 缓存命中条件严格依赖 auth identity（`chatgpt_user_id + account_id`）和签名/TTL。

### 4) `fetch_with_retries`（请求、401 恢复、解析、缓存写回）

- 目的：统一处理可重试错误与不可重试错误。
- 行为要点：
  - 可重试错误：重试到上限；
  - 401：走 `unauthorized_recovery` 状态机；
  - 解析错误：立即失败（不重试）；
  - 成功后写缓存并返回 `ConfigRequirementsToml` 或 `None`。

### 5) `load_cache` / `save_cache`

- 目的：提供“带身份绑定 + 防篡改签名 + TTL”的本地缓存。
- `load_cache` 失败会返回细粒度 `CacheLoadStatus`（如 `CacheSignatureInvalid` / `CacheIdentityMismatch` / `CacheExpired`）。
- `save_cache` 失败只告警，不影响已获取结果返回。

### 6) 指标埋点

- 目的：区分启动与刷新路径、每次尝试与最终结果，便于运维排障。
- 指标：
  - `codex.cloud_requirements.fetch_attempt`
  - `codex.cloud_requirements.fetch_final`
  - `codex.cloud_requirements.load`
  - 以及全局计时器 `codex.cloud_requirements.fetch.duration_ms`

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 启动加载主流程

1. 调用方构造 loader
- TUI：`codex-rs/tui/src/lib.rs:356-369`
- Exec：`codex-rs/exec/src/lib.rs:289-300`
- App Server：`codex-rs/app-server/src/lib.rs:419-429`
- TUI App Server：`codex-rs/tui_app_server/src/lib.rs:683-692`

2. `cloud_requirements_loader(...)` 内部
- 构建 `CloudRequirementsService`。
- `tokio::spawn` 一次性任务执行 `fetch_with_timeout()`。
- `tokio::spawn` 后台任务执行 `refresh_cache_in_background()`。
- 返回 `CloudRequirementsLoader::new(async move { task.await ... })`（`lib.rs:689-721`）。

3. Config 合并
- `ConfigBuilder::build()` -> `load_config_layers_state(..., cloud_requirements)`（`core/src/config/mod.rs:656-663`）。
- `load_config_layers_state` 先取 cloud requirements，再合并 MDM/system/legacy（`core/src/config_loader/mod.rs:114-149`）。

### B. 协议与请求路径

1. 后端接口
- `BackendClient::get_config_requirements_file()`：
  - Codex 风格：`GET /api/codex/config/requirements`
  - ChatGPT 风格：`GET /wham/config/requirements`
- 代码：`codex-rs/backend-client/src/client.rs:343-358`。

2. 路径风格判定
- `PathStyle::from_base_url()`：base_url 含 `/backend-api` 则走 `ChatGptApi`（`backend-client/src/client.rs:90-98`）。
- `Client::new` 会对 chatgpt 域名自动补 `/backend-api`（`client.rs:111-123`）。

3. 响应模型
- `ConfigFileResponse { contents, sha256, updated_at, updated_by_user_id }`
- 定义：`codex-rs/codex-backend-openapi-models/src/models/config_file_response.rs:14-24`。

### C. 数据结构与缓存格式

1. 缓存文件结构（JSON）
- `CloudRequirementsCacheFile { signed_payload, signature }`
- `CloudRequirementsCacheSignedPayload { cached_at, expires_at, chatgpt_user_id, account_id, contents }`
- 定义：`lib.rs:117-130`。

2. 签名机制
- HMAC-SHA256 + Base64；写入 key 为 `CLOUD_REQUIREMENTS_CACHE_WRITE_HMAC_KEY`。
- 读取支持 key 列表 `CLOUD_REQUIREMENTS_CACHE_READ_HMAC_KEYS`（目前仅 1 个），便于未来 key 轮换。
- 代码：`lib.rs:139-168`。

3. 身份绑定
- 缓存读取要求当前 auth 同时提供 `chatgpt_user_id` 和 `account_id`；两者与缓存一致才可用（`lib.rs:573-625`）。

4. TTL 与刷新
- TTL：30 分钟（`CLOUD_REQUIREMENTS_CACHE_TTL`）。
- 刷新周期：5 分钟（`CLOUD_REQUIREMENTS_CACHE_REFRESH_INTERVAL`）。
- 定时刷新不刷新失败即退出（auth 不匹配/非目标 plan）或记录错误后继续。

### D. 错误分层与恢复策略

1. 拉取错误分类
- `Retryable(BackendClientInit|Request{status_code})`
- `Unauthorized{status_code,message}`
- 定义：`lib.rs:67-89`。

2. 401 恢复逻辑
- `auth_manager.unauthorized_recovery()` 由 `core/auth.rs` 的状态机实现：
  - managed 模式：`Reload -> RefreshToken -> Done`
  - external token 模式：`ExternalRefresh -> Done`
- 关键实现：`core/src/auth.rs:861-1031`。

3. 失败闭环
- 解析错误：`CloudRequirementsLoadErrorCode::Parse`
- 超时：`Timeout`
- 重试耗尽：`RequestFailed`
- 认证无法恢复：`Auth`

4. 上游错误透传
- App Server 将 cloud requirements 错误结构化成 JSON-RPC `data`，包含 `reason=cloudRequirements`、`errorCode`、`statusCode`，且 `Auth` 会带 `action=relogin`（`app-server/src/codex_message_processor.rs:7662-7675`）。
- 对应测试：`codex_message_processor.rs:8338-8395`。

### E. 配置层优先级实现

1. cloud requirements 先于 system/legacy 填充
- `load_config_layers_state` 先 `cloud_requirements.get()`，然后再加载 MDM/system/legacy（`config_loader/mod.rs:121-149`）。
- `ConfigRequirementsWithSources::merge_unset_fields` 语义为“只填未设置字段”（apps 有专门 descending 合并逻辑），因此 cloud 先写入后通常拥有更高优先级（`config/src/config_requirements.rs:341-404`）。

2. 调试展示
- TUI 与 TUI app-server debug 配置输出会显示 source 为 `cloud requirements`，验证来源追踪链路正常（`tui/src/debug_config.rs:562-584`，`tui_app_server/src/debug_config.rs:562-584`）。

### F. 关键命令（开发/验证）

与该目录直接相关的常用命令：

```bash
# 仅测试本 crate
cargo test -p codex-cloud-requirements

# 查看配置层是否包含 cloud requirements（通过 core 测试）
cargo test -p codex-core config_loader::tests::load_config_layers_includes_cloud_requirements

# app-server 端验证 cloud requirements 错误透传
cargo test -p codex-app-server thread_start_surfaces_cloud_requirements_load_errors
```

### G. 脚本与文档上下文

1. 研究流程脚本
- 每日 TODO 由 `.ops/generate_daily_research_todo.sh` 从 `Docs/researches/blueprint_checklist.md` 生成（`.ops/generate_daily_research_todo.sh:4-41`）。

2. 对外文档
- app-server README 的 `configRequirements/read` 描述了 requirements API 的可见面（`codex-rs/app-server/README.md:184`），但未单独展开 cloud 拉取/缓存细节。

## 关键代码路径与文件引用

### 目标目录（DIR 本体）

- `codex-rs/cloud-requirements/src/lib.rs`
  - 常量与错误类型：`45-138`
  - 后端 fetcher：`184-245`
  - service 主流程：`255-571`
  - cache 读写：`573-686`
  - loader 工厂：`689-735`
  - metrics：`752-816`
  - 单测：`818-1930`

- `codex-rs/cloud-requirements/Cargo.toml`
- `codex-rs/cloud-requirements/BUILD.bazel`

### 调用方（上游）

- 配置加载核心入口：
  - `codex-rs/core/src/config/mod.rs:593-663`（`ConfigBuilder` 注入）
  - `codex-rs/core/src/config_loader/mod.rs:114-149`（合并顺序）

- 终端与执行面：
  - `codex-rs/tui/src/lib.rs:356-369, 663-681`
  - `codex-rs/exec/src/lib.rs:289-303, 363-367`
  - `codex-rs/tui_app_server/src/lib.rs:683-692, 1027-1045`

- app-server 注入与重建：
  - `codex-rs/app-server/src/lib.rs:395-442`
  - `codex-rs/app-server/src/codex_message_processor.rs:1102-1114, 7714-7747`
  - `codex-rs/app-server/src/config_api.rs:85-117`

### 被调用方（下游）

- 后端客户端与模型：
  - `codex-rs/backend-client/src/client.rs:343-358`
  - `codex-rs/codex-backend-openapi-models/src/models/config_file_response.rs:14-24`

- 认证恢复状态机：
  - `codex-rs/core/src/auth.rs:861-1031, 1270-1324`

- 重试退避：
  - `codex-rs/core/src/util.rs:205-210`

- cloud loader 抽象：
  - `codex-rs/config/src/cloud_requirements.rs:9-82`

### 测试路径（跨目录）

- 本 crate：`codex-rs/cloud-requirements/src/lib.rs`（内联 tests）
- core 合并行为：`codex-rs/core/src/config_loader/tests.rs:582-764`
- connectors 约束落地：`codex-rs/core/src/connectors_tests.rs:488-566`
- app-server 错误透传：
  - `codex-rs/app-server/tests/suite/v2/thread_start.rs:332-380`
  - `codex-rs/app-server/tests/suite/v2/thread_resume.rs:1423-1479`
  - `codex-rs/app-server/tests/suite/v2/thread_fork.rs:226-284`

## 依赖与外部交互

### 内部依赖

- `codex-core`
  - `AuthManager`、`CodexAuth`、`RefreshTokenError`
  - `config_loader::{CloudRequirementsLoader, CloudRequirementsLoadError, ConfigRequirementsToml}`
  - `util::backoff`

- `codex-backend-client`
  - `Client::from_auth` + `get_config_requirements_file()`

- `codex-protocol`
  - `account::PlanType`（Business/Enterprise 门控）

- `codex-config`
  - 通过 `CloudRequirementsLoader` 抽象 shared future 语义

- `codex-otel`
  - 计时与计数器埋点

### 外部交互

1. HTTP
- 与 ChatGPT backend / Codex backend 交互 `GET .../config/requirements`。
- 非 2xx 状态特别是 401 会触发认证恢复分支。

2. 本地文件系统
- 读写缓存：`$CODEX_HOME/cloud-requirements-cache.json`。
- 依赖 `tokio::fs` 异步 IO。

3. 认证基础设施
- 通过 `AuthManager` 访问当前 auth、reload、refresh token、external refresher。

4. 可观测性
- tracing + otel counters/timer，带触发源（startup/refresh）、状态码、attempt 等 tag。

## 风险、边界与改进建议

### 风险与边界

1. fail-closed 策略在产品面不完全一致
- `cloud-requirements` crate 本身对 eligible 账号是 fail-closed。
- 但 `exec` 和 `app-server` 仍存在“preload 失败回退默认 loader”注释（TODO），表现为某些入口尚未完全强制阻断（`exec/src/lib.rs:298-300`，`app-server/src/lib.rs:431-433`）。

2. 缓存签名 key 为内置常量
- 可防“文件被随意改写”导致误用，但密钥与二进制同分发，安全边界更偏“完整性检测”而非强抗攻击。

3. 背景刷新任务是全局单槽位
- `OnceLock<Mutex<Option<JoinHandle>>>` 设计会在同进程新建 loader 时中止旧刷新任务。
- 优点是避免重复刷新；边界是多实例/多 profile 场景下只保留最后一个 refresher。

4. 缓存身份要求严格（双字段）
- 必须同时有 `chatgpt_user_id + account_id` 才能读取缓存，减少串号风险；
- 但在身份不完整时会放弃缓存命中，增加对远端依赖（已有测试覆盖这一行为）。

5. 文档漂移风险
- `core/config_loader/README.md` 的示例调用仍展示旧形态（`cloud_requirements` 参数示例为 `None`），与当前签名不完全一致，可能误导新接入者。

### 改进建议

1. 统一“入口 fail-closed 策略”
- 收敛 `exec` 与 `app-server` 的 TODO 分支，明确在 eligible 账号上是否必须阻断启动，避免不同入口行为不一致。

2. 增强缓存可观测性
- 当前只在日志中区分 `CacheLoadStatus`；可增加 cache hit/miss/invalid/expired 专用指标，便于线上定位高频失效原因。

3. 签名 key 轮换策略制度化
- 代码已支持 read-key 列表；建议补充“多 key 读 + 单 key 写”轮换流程文档/测试，降低未来升级风险。

4. 文档修正
- 更新 `core/src/config_loader/README.md` 的 `load_config_layers_state` 示例参数，避免与当前 API 不一致。

5. 刷新任务生命周期管理
- 目前依赖全局 task slot + abort；可考虑在 runtime shutdown 时显式清理，或在多实例场景下引入更明确的 ownership 语义。
