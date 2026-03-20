# DIR `codex-rs/cloud-requirements/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-requirements/src`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 主要文件：`lib.rs`
- 对应 crate：`codex-cloud-requirements`

## 场景与职责

`codex-rs/cloud-requirements/src/lib.rs` 是 Codex “云端托管 requirements” 的执行核心。它在配置加载链路中的角色不是“解释配置”，而是“安全拉取 + 本地缓存 + 失败策略 + 恢复策略”，最终把结果以 `CloudRequirementsLoader` 提供给 `codex-core` 的配置合并层。

核心职责可归纳为 6 点：

1. **适用人群门控**
- 仅对 ChatGPT 登录且套餐为 `Business`/`Enterprise` 的账号生效。
- 非 ChatGPT 登录（例如 API key）或非上述套餐直接 `Ok(None)`，不启用云约束。
- 代码：`cloud-requirements/src/lib.rs:326-337`。

2. **启动时 fail-closed 拉取**
- 对符合门控的账号，启动阶段如果云 requirements 获取失败，会返回 `CloudRequirementsLoadError` 让配置加载失败，不会静默放行。
- 错误码包含 `Auth/Timeout/Parse/RequestFailed/Internal`。
- 代码：`cloud-requirements/src/lib.rs:270-324, 359-528`。

3. **401 自动恢复（受控）**
- 401 时尝试 `AuthManager::unauthorized_recovery()` 状态机：
  - managed token：`Reload -> RefreshToken -> Done`
  - external token：`ExternalRefresh -> Done`
- 恢复失败则返回面向用户的明确消息。
- 代码：`cloud-requirements/src/lib.rs:359-478`；状态机在 `core/src/auth.rs:861-1028`。

4. **签名缓存与身份绑定**
- 缓存文件：`$CODEX_HOME/cloud-requirements-cache.json`。
- 使用 HMAC-SHA256 对缓存载荷签名，并绑定 `chatgpt_user_id + account_id`，避免跨账号复用。
- 代码：`cloud-requirements/src/lib.rs:117-168, 573-686`。

5. **后台周期刷新**
- 启动加载后，会每 5 分钟后台刷新缓存；失败时保留旧缓存。
- 刷新任务句柄通过 `OnceLock<Mutex<Option<JoinHandle>>>` 全局替换，避免旧刷新任务悬挂。
- 代码：`cloud-requirements/src/lib.rs:62-65, 530-571, 689-711`。

6. **可观测性埋点**
- 区分启动/刷新触发，记录每次尝试与最终结果。
- 指标：
  - `codex.cloud_requirements.fetch_attempt`
  - `codex.cloud_requirements.fetch_final`
  - `codex.cloud_requirements.load`
  - 时长计时器 `codex.cloud_requirements.fetch.duration_ms`
- 代码：`cloud-requirements/src/lib.rs:50-52, 274, 752-816`。

## 功能点目的

### 1) `cloud_requirements_loader(...)`

目的：暴露上游统一可复用的 `CloudRequirementsLoader`，隐藏请求、重试、鉴权恢复、缓存和刷新细节。

行为要点：
- 构造 `CloudRequirementsService`。
- 启动一次性拉取任务（用于 `CloudRequirementsLoader::get()` 的共享 future）。
- 启动后台刷新任务（替换旧任务，旧任务 abort）。
- 返回 `CloudRequirementsLoader::new(async move { ... })`。

代码：`cloud-requirements/src/lib.rs:689-721`。

### 2) `cloud_requirements_loader_for_storage(...)`

目的：给“只有存储参数”的调用方（如 `tui_app_server`）提供便捷入口，内部创建 `AuthManager::shared(...)` 后复用主 loader。

代码：`cloud-requirements/src/lib.rs:723-735`。

### 3) `fetch_with_timeout()`

目的：为启动拉取设置硬超时（15s），避免进程卡死于远端不可用。

行为要点：
- `timeout(self.timeout, self.fetch())`。
- 超时返回 `CloudRequirementsLoadErrorCode::Timeout`。
- 输出错误日志与 load metric。

代码：`cloud-requirements/src/lib.rs:270-324`。

### 4) `fetch()`

目的：门控 + 缓存优先 + 远端兜底。

行为要点：
- 检查 auth 类型与 plan。
- 读取缓存：签名正确、身份匹配、TTL 有效则直接返回缓存。
- 缓存不可用时转入远端重试逻辑。

代码：`cloud-requirements/src/lib.rs:326-357, 573-646`。

### 5) `fetch_with_retries()`

目的：统一处理请求重试、401 恢复、解析失败、最终错误归一。

行为要点：
- 最大 5 次尝试（`CLOUD_REQUIREMENTS_MAX_ATTEMPTS`）。
- 非 401 错误按可重试路径 + `backoff(attempt)` 退避。
- 401 进入 `unauthorized_recovery`；可恢复则继续，失败则 `Auth` 错误。
- TOML 解析失败立即 `Parse` 错误，不继续重试。
- 成功后写缓存（写失败仅告警，不阻塞成功返回）。

代码：`cloud-requirements/src/lib.rs:359-528`。

### 6) `load_cache()` / `save_cache()`

目的：离线容错和冷启动提速，同时保证缓存完整性与身份隔离。

行为要点：
- 缓存读取失败状态细分为 `CacheLoadStatus`（文件缺失、解析失败、签名无效、身份不匹配、过期等）。
- 写缓存记录 `cached_at` 和 `expires_at`（TTL=30 分钟）。
- 签名可读 key 列表支持未来轮换。

代码：`cloud-requirements/src/lib.rs:92-107, 117-168, 573-686`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

#### 流程 1：启动加载（主路径）

1. 调用方创建 loader：
- `tui/src/lib.rs:365-369`
- `exec/src/lib.rs:299-303`
- `app-server/src/lib.rs:424-429`
- `tui_app_server/src/lib.rs:687-692`

2. `cloud_requirements_loader(...)` 同时起两个任务：
- 单次任务：`fetch_with_timeout()`（决定当前进程启动时使用的 requirements）
- 后台任务：`refresh_cache_in_background()`（持续刷新本地缓存）

3. `CloudRequirementsLoader` 在配置加载时被消费：
- `core/src/config_loader/mod.rs:119-126`（`cloud_requirements.get().await`）
- 若返回 `Some(requirements)`，以 `RequirementSource::CloudRequirements` 合并到约束层。

#### 流程 2：请求重试与 401 恢复

1. `BackendRequirementsFetcher` 调用 `BackendClient::from_auth(...).get_config_requirements_file()`。
2. 非 401 错误 => `Retryable`，进入指数退避重试。
3. 401 => `Unauthorized`，进入 `unauthorized_recovery`：
- managed：先 reload（仅同 account id），再 refresh token。
- external：调用外部 refresher。
4. 恢复后重新请求；若不可恢复则输出 Auth 错误并终止。

对应代码：
- `cloud-requirements/src/lib.rs:206-245, 359-478`
- `core/src/auth.rs:861-1028, 1270-1324`

#### 流程 3：缓存命中与远端兜底

1. 从 auth 提取 `(chatgpt_user_id, account_id)`。
2. `load_cache()` 检查：
- auth identity 是否完整
- 文件读取/反序列化
- HMAC 验签
- cached identity 是否一致
- `expires_at` 是否过期
3. 命中则直接解析并返回，不触发远端请求。
4. 未命中则走远端并写回新缓存。

代码：`cloud-requirements/src/lib.rs:170-183, 326-357, 573-686`。

#### 流程 4：后台刷新

- 周期：每 5 分钟。
- 仅在仍满足 ChatGPT + Business/Enterprise 条件时继续。
- 退出条件：无 auth 或不再符合 plan 条件（返回 `false` 后跳出循环）。

代码：`cloud-requirements/src/lib.rs:48, 530-571`。

### B. 关键数据结构

1. `FetchAttemptError`
- `Retryable(RetryableFailureKind)`
- `Unauthorized { status_code, message }`
- 作用：把“重试类错误”与“鉴权恢复类错误”明确分流。

2. `CloudRequirementsCacheFile`
- `{ signed_payload, signature }`

3. `CloudRequirementsCacheSignedPayload`
- `cached_at` / `expires_at`
- `chatgpt_user_id` / `account_id`
- `contents`

4. `CloudRequirementsLoadError`（来自 `codex-config`）
- `code + message + status_code`
- 上游可以结构化透传到 RPC 错误数据。

代码：
- `cloud-requirements/src/lib.rs:83-130`
- `config/src/cloud_requirements.rs:9-66`

### C. 协议与命令/接口

1. 云端接口
- `GET /api/codex/config/requirements`（Codex API path style）
- `GET /wham/config/requirements`（ChatGPT backend-api path style）
- 代码：`backend-client/src/client.rs:343-358`

2. path style 判定
- base_url 含 `/backend-api` => `ChatGptApi`
- 否则 `CodexApi`
- 代码：`backend-client/src/client.rs:79-98`

3. 响应模型
- `ConfigFileResponse { contents, sha256, updated_at, updated_by_user_id }`
- `cloud-requirements` 当前只使用 `contents`。
- 代码：`codex-backend-openapi-models/src/models/config_file_response.rs:14-24`

4. 常见验证命令（研究对象相关）

```bash
# 单 crate 回归
cargo test -p codex-cloud-requirements

# 配置层与优先级行为
cargo test -p codex-core config_loader::tests::load_config_layers_includes_cloud_requirements

# app-server 错误透传（thread_start）
cargo test -p codex-app-server thread_start_surfaces_cloud_requirements_load_errors
```

## 关键代码路径与文件引用

### 目标目录内（本体）

- `codex-rs/cloud-requirements/src/lib.rs`
  - 常量、错误类型、缓存签名：`45-183`
  - fetcher 与服务：`185-571`
  - cache 读写：`573-686`
  - loader 工厂：`689-735`
  - 解析与指标：`737-816`
  - 测试：`818-1930`

### 调用方（上游）

- CLI/TUI 入口注入
  - `codex-rs/tui/src/lib.rs:365-369, 663-681`
  - `codex-rs/exec/src/lib.rs:299-303, 363-367`
  - `codex-rs/tui_app_server/src/lib.rs:687-692, 1028-1044`

- App Server 注入与重建
  - 启动预加载：`codex-rs/app-server/src/lib.rs:395-442`
  - 登录成功后替换 loader：`codex-rs/app-server/src/codex_message_processor.rs:1071-1114, 1256-1264, 7714-7726`
  - Config API 读取当前 loader：`codex-rs/app-server/src/config_api.rs:61-97`

- 配置合并入口
  - `codex-rs/core/src/config/mod.rs:593-663`
  - `codex-rs/core/src/config_loader/mod.rs:87-126`

### 被调用方（下游）

- 后端客户端
  - `codex-rs/backend-client/src/client.rs:343-358`

- 鉴权恢复状态机
  - `codex-rs/core/src/auth.rs:861-1028, 1270-1324`

- 重试退避
  - `codex-rs/core/src/util.rs:11-12, 205-210`

### 配置语义与来源展示

- `RequirementSource::CloudRequirements` 显示名：`codex-rs/config/src/config_requirements.rs:17-37`
- 合并策略 `merge_unset_fields`：`codex-rs/config/src/config_requirements.rs:341-404`
- debug_config 输出 cloud source：
  - `codex-rs/tui/src/debug_config.rs:562-584, 673-674`
  - `codex-rs/tui_app_server/src/debug_config.rs:564-583, 673`

### 测试路径（跨目录）

- 本目录内强覆盖：`codex-rs/cloud-requirements/src/lib.rs:1082-1930`
- 配置层优先级与 fail-closed：`codex-rs/core/src/config_loader/tests.rs:582-764`
- app connector 受云约束：`codex-rs/core/src/connectors_tests.rs:488-566`
- app-server 错误透传：
  - `codex-rs/app-server/tests/suite/v2/thread_start.rs:332-410`
  - `codex-rs/app-server/tests/suite/v2/thread_resume.rs:1423-1510`
  - `codex-rs/app-server/tests/suite/v2/thread_fork.rs:226-316`

## 依赖与外部交互

### 内部 crate 依赖关系

1. `codex-core`
- `AuthManager` / `CodexAuth` / `RefreshTokenError`
- `config_loader::{CloudRequirementsLoader, CloudRequirementsLoadError, ConfigRequirementsToml}`
- `util::backoff`

2. `codex-backend-client`
- 远端 HTTP 拉取 `get_config_requirements_file()`。

3. `codex-protocol`
- `PlanType`（Business/Enterprise 门控）。

4. `codex-otel`
- 指标计数器与时长统计。

5. `tokio`
- timeout、sleep、异步文件 I/O、后台任务。

### 外部交互

1. **网络**
- 访问 chatgpt/codex backend 的 requirements 接口。
- 401 情况下可能触发 oauth token refresh（经 `AuthManager` 流程）。

2. **文件系统**
- 读写 `$CODEX_HOME/cloud-requirements-cache.json`。
- 依赖 auth 存储（`AuthManager` 读取 auth 数据）。

3. **RPC 错误面**
- app-server 会把 cloud requirements 加载错误转成 JSON-RPC `error.data`：
  - `reason=cloudRequirements`
  - `errorCode`
  - `statusCode`
  - `action=relogin`（当 `Auth`）
- 代码：`app-server/src/codex_message_processor.rs:7649-7680`。

### 配置与脚本文档上下文

- workspace 声明此 crate：`codex-rs/Cargo.toml:1-40, 80-104`
- crate 依赖定义：`codex-rs/cloud-requirements/Cargo.toml:1-30`
- Bazel 目标：`codex-rs/cloud-requirements/BUILD.bazel:1-5`
- app-server README 暴露 `configRequirements/read`（面向客户端可见）：`codex-rs/app-server/README.md:184`
- 研究工作流脚本：`.ops/generate_daily_research_todo.sh:1-41`

## 风险、边界与改进建议

### 风险与边界

1. **内置 HMAC key 固化在代码中**
- 当前 key 主要用于“本地缓存完整性防篡改”，不是密钥管理级别防护。
- 若机器被本地高权限入侵，攻击者可构造合法签名缓存。

2. **刷新任务全局槽位是进程级单实例**
- `OnceLock<Mutex<Option<JoinHandle>>>` 表示“新 loader 会替换旧刷新任务”。
- 在多 runtime/多上下文并发场景下，可能出现任务切换频繁，需明确这是设计预期。

3. **`contents = None` 被当成成功路径**
- 后端未下发 requirements 时按 `Ok(None)` 处理，这是协议约定；但若服务端异常导致 `contents` 丢失，也会被视作“无约束”。

4. **解析失败 fail-closed，但错误文本统一**
- 用户面多数看到通用提示（`failed to load your workspace-managed config`）。
- 对排障友好度依赖日志和上层 error data。

5. **文档与实现存在漂移风险**
- `core/src/config_loader/README.md` 对 layer 说明偏旧，未完整体现 cloud 层与当前参数签名；容易误导新维护者。

### 改进建议

1. **增强缓存 key 轮换策略文档**
- 当前已具备 `WRITE_KEY + READ_KEYS` 结构，可补充 key 轮换 SOP（版本切换、回收窗口、回滚策略）。

2. **为“contents 缺失”增加区分指标**
- 目前日志有记录，但建议增加单独 metric reason（例如 `response_missing_contents`），便于区分业务“无配置”与接口异常。

3. **补充运行时级别的刷新任务可见性**
- 建议在替换刷新任务时增加唯一 task_id 日志字段，便于排查“哪一次登录/重载触发了刷新任务替换”。

4. **统一 README 与真实层级实现**
- 更新 `core/src/config_loader/README.md`，对 cloud requirements 顺序、fail-closed 行为、`CloudRequirementsLoader` 参数做同步说明。

5. **补充 app-server 侧联动测试场景**
- 增加“登录成功后替换 loader + 同进程配置重读生效”的集成测试，覆盖 `replace_cloud_requirements_loader(...)` 的动态更新路径。
