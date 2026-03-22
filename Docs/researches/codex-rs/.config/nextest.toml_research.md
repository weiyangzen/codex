# codex-rs/.config/nextest.toml 研究文档

## 场景与职责

### 文件定位
`codex-rs/.config/nextest.toml` 是 [cargo-nextest](https://nexte.st/) 测试运行器的配置文件，位于 Rust 工作区 `codex-rs` 目录下的 `.config/` 子目录中。这是 nextest 默认会查找配置文件的[标准位置](https://nexte.st/docs/configuration/)。

### 核心职责
该配置文件定义了 Codex Rust 项目的测试执行策略，主要解决以下问题：

1. **测试超时管理**：防止慢测试或死锁测试无限期阻塞 CI/本地测试运行
2. **并发控制**：通过 test-groups 限制特定测试的并发度，避免资源冲突
3. **测试隔离**：确保有状态测试（如集成测试）不会相互干扰

### 使用场景
- **本地开发**：开发者运行 `just test` 时自动应用这些配置
- **CI/CD 流水线**：GitHub Actions 等环境中确保测试稳定运行
- **资源敏感测试**：如 app-server 集成测试需要单线程执行

---

## 功能点目的

### 1. 默认慢测试超时配置 (`[profile.default]`)

```toml
[profile.default]
slow-timeout = { period = "15s", terminate-after = 2 }
```

**目的**：
- 定义测试的"慢"阈值为 15 秒
- 如果测试连续 2 个周期（即 30 秒）未完成，则强制终止
- 注释明确指出 "Do not increase, fix your test instead" —— 鼓励修复测试而非放宽限制

**实际影响**：
- 超过 30 秒的测试会被标记为 `TIMEOUT` 并终止
- 防止有问题的测试阻塞整个测试套件

### 2. 测试组并发控制 (`[test-groups]`)

```toml
[test-groups.app_server_protocol_codegen]
max-threads = 1

[test-groups.app_server_integration]
max-threads = 1
```

**目的**：
- `app_server_protocol_codegen`：代码生成测试需要串行执行，避免文件写入冲突
- `app_server_integration`：app-server 集成测试每个用例会启动子进程，单线程执行避免资源竞争

**设计背景**：
- app-server 集成测试在 `codex-rs/app-server/tests/suite/v2/` 目录下有 49 个测试模块
- 这些测试通过 WebSocket/Unix Socket 与 app-server 交互，多线程并发会导致端口冲突或状态污染

### 3. 特定测试超时覆盖 (`[[profile.default.overrides]]`)

#### 3.1 长时间运行测试的特殊超时

```toml
[[profile.default.overrides]]
filter = 'test(rmcp_client) | test(humanlike_typing_1000_chars_appears_live_no_placeholder)'
slow-timeout = { period = "1m", terminate-after = 4 }
```

**覆盖的测试**：
- `rmcp_client` 测试（位于 `codex-rs/core/tests/suite/rmcp_client.rs`）：
  - 涉及 MCP (Model Context Protocol) 客户端的端到端测试
  - 需要启动外部进程（stdio server 或 HTTP server）
  - 测试网络通信、OAuth 流程等，本身耗时较长
  
- `humanlike_typing_1000_chars_appears_live_no_placeholder`（位于 `codex-rs/tui/src/bottom_pane/chat_composer.rs`）：
  - TUI 输入组件的模拟打字测试
  - 模拟 1000 个字符的人性化输入，有延迟
  - 单元测试但涉及时间敏感的行为验证

**超时策略**：
- 周期延长至 1 分钟，最多 4 个周期（即 4 分钟）
- 比默认的 30 秒宽容得多

#### 3.2 中等超时测试

```toml
[[profile.default.overrides]]
filter = 'test(approval_matrix_covers_all_modes)'
slow-timeout = { period = "30s", terminate-after = 2 }
```

**覆盖的测试**：
- `approval_matrix_covers_all_modes`（位于 `codex-rs/core/tests/suite/approvals.rs:1627`）：
  - 遍历所有审批策略组合的矩阵测试
  - 涉及多种沙箱策略、审批策略的组合验证
  - 需要 60 秒超时（30s × 2）

#### 3.3 代码生成测试组分配

```toml
[[profile.default.overrides]]
filter = 'package(codex-app-server-protocol) & (test(typescript_schema_fixtures_match_generated) | test(json_schema_fixtures_match_generated) | test(generate_ts_with_experimental_api_retains_experimental_entries) | test(generated_ts_optional_nullable_fields_only_in_params) | test(generate_json_filters_experimental_fields_and_methods))'
test-group = 'app_server_protocol_codegen'
```

**覆盖的测试**（位于 `codex-rs/app-server-protocol/tests/schema_fixtures.rs`）：
- `typescript_schema_fixtures_match_generated`：验证 TypeScript schema 生成
- `json_schema_fixtures_match_generated`：验证 JSON schema 生成
- `generate_ts_with_experimental_api_retains_experimental_entries`：实验性 API 测试
- `generated_ts_optional_nullable_fields_only_in_params`：字段可空性测试
- `generate_json_filters_experimental_fields_and_methods`：实验字段过滤测试

**为何需要单线程**：
- 这些测试读写文件系统上的 schema fixtures
- 并发执行可能导致文件竞争或生成不一致的结果

#### 3.4 集成测试组分配

```toml
[[profile.default.overrides]]
filter = 'package(codex-app-server) & kind(test)'
test-group = 'app_server_integration'
```

**覆盖范围**：
- `codex-app-server` 包中的所有测试
- 位于 `codex-rs/app-server/tests/suite/` 下的所有集成测试

**为何需要单线程**：
- 每个测试用例会启动一个 app-server 子进程
- 测试通过 WebSocket 或 Unix Domain Socket 与 server 通信
- 多线程并发会导致：
  - 端口/套接字文件冲突
  - 进程资源竞争
  - 测试间状态泄漏

---

## 具体技术实现

### 配置格式与语法

nextest 配置使用 [TOML](https://toml.io/) 格式，支持以下关键结构：

#### Profile 配置
```toml
[profile.<name>]
slow-timeout = { period = "<duration>", terminate-after = <n> }
```

- `period`：检测周期，支持 `s`（秒）、`m`（分钟）等单位
- `terminate-after`：连续多少个周期超时后终止测试

#### Test Groups
```toml
[test-groups.<name>]
max-threads = <n>
```

- 定义命名资源组，限制并发线程数
- 用于需要互斥访问的测试集合

#### Overrides
```toml
[[profile.<name>.overrides]]
filter = '<predicate>'
# 覆盖的配置项
```

- `filter`：使用 nextest 的[过滤表达式语法](https://nexte.st/docs/filtersets/)
- 支持 `test()`、`package()`、`kind()` 等谓词
- 支持 `&`（与）、`|`（或）逻辑组合

### 过滤表达式详解

| 谓词 | 含义 | 示例 |
|------|------|------|
| `test(<regex>)` | 匹配测试名称 | `test(rmcp_client)` |
| `package(<name>)` | 匹配包名 | `package(codex-app-server)` |
| `kind(test)` | 匹配测试类型目标 | `kind(test)` |
| `&` | 逻辑与 | `package(foo) & test(bar)` |
| `\|` | 逻辑或 | `test(a) \| test(b)` |

### 与 Cargo 测试的对比

| 特性 | `cargo test` | `cargo nextest` |
|------|-------------|-----------------|
| 并行模型 | 线程级并行 | 进程级并行 |
| 超时控制 | 无内置支持 | 内置慢测试检测 |
| 测试隔离 | 共享进程 | 每个测试独立进程 |
| 配置方式 | 环境变量/代码 | TOML 配置文件 |
| 性能 | 一般 | 更快（进程级隔离） |

---

## 关键代码路径与文件引用

### 配置文件本身
- **路径**: `codex-rs/.config/nextest.toml`
- **格式**: TOML
- **行数**: 29 行

### 相关测试文件

#### MCP 客户端测试
```
codex-rs/core/tests/suite/rmcp_client.rs
├── stdio_server_round_trip (line 56)
├── stdio_image_responses_round_trip (line 198)
├── stdio_image_responses_are_sanitized_for_text_only_model (line 378)
├── stdio_server_propagates_whitelisted_env_vars (line 544)
├── streamable_http_tool_call_round_trip (line 683)
└── streamable_http_with_oauth_round_trip (line 861)
```

这些测试使用 `#[serial(mcp_test_value)]` 串行化，但仍需要更长的超时。

#### TUI 打字测试
```
codex-rs/tui/src/bottom_pane/chat_composer.rs:9379
└── humanlike_typing_1000_chars_appears_live_no_placeholder
```

模拟人性化打字 1000 个字符，验证无粘贴占位符出现。

#### 审批矩阵测试
```
codex-rs/core/tests/suite/approvals.rs:1627
└── approval_matrix_covers_all_modes
```

遍历所有审批策略和沙箱策略组合。

#### Schema 生成测试
```
codex-rs/app-server-protocol/tests/schema_fixtures.rs
├── typescript_schema_fixtures_match_generated (line 12)
├── json_schema_fixtures_match_generated (line 24)
└── 其他实验性 API 测试
```

#### App-server 集成测试
```
codex-rs/app-server/tests/
├── all.rs (测试入口)
└── suite/
    ├── mod.rs
    ├── auth.rs
    ├── conversation_summary.rs
    ├── fuzzy_file_search.rs
    └── v2/ (49 个测试模块)
        ├── mod.rs
        ├── thread_*.rs
        ├── turn_*.rs
        └── ...
```

### 调用方（使用该配置的工具）

#### justfile
```just
# codex-rs/../justfile (line 46-47)
test:
    cargo nextest run --no-fail-fast
```

#### AGENTS.md
```markdown
# 推荐开发者使用 `just test`（如果安装了 cargo-nextest）
```

#### 文档
```
docs/install.md (line 29-30, 44-45)
├── cargo install --locked cargo-nextest
└── just test  # 使用 nextest 运行测试
```

---

## 依赖与外部交互

### 外部工具依赖

| 工具 | 版本要求 | 安装方式 | 用途 |
|------|---------|---------|------|
| cargo-nextest | 最新稳定版 | `cargo install --locked cargo-nextest` | 测试运行器 |

### 与 just 的集成

```
开发者 -> just test -> cargo nextest run --no-fail-fast
                              |
                              v
                    读取 codex-rs/.config/nextest.toml
                              |
                              v
                    按配置执行测试（超时控制、并发限制）
```

### 与 Cargo 的关系

nextest 是 Cargo 测试的替代方案：
- 使用相同的测试编译产物（`cargo test --no-run` 生成的二进制文件）
- 但使用自己的运行时和配置系统
- 支持 Cargo 的 `CARGO_TARGET_DIR` 等环境变量

### 与 CI/CD 的集成

配置确保测试在 CI 环境中稳定运行：
- 明确的超时防止死锁导致 CI 挂起
- 单线程测试组避免资源竞争导致的 flaky tests
- `--no-fail-fast` 确保所有测试都执行（发现多个问题）

---

## 风险、边界与改进建议

### 当前风险

#### 1. 超时配置过于严格
- **风险**：某些测试在资源受限的 CI 环境中可能偶发超时
- **表现**：测试被标记为 `TIMEOUT` 而非实际失败
- **缓解**：当前已通过 overrides 为慢测试配置更长超时

#### 2. 单线程测试组成为瓶颈
- **风险**：`app_server_integration` 组包含 49+ 个测试，串行执行时间较长
- **表现**：整个测试套件等待这些测试完成
- **现状**：注释说明这是有意为之（"These integration tests spawn a fresh app-server subprocess per case"）

#### 3. 测试泄漏检测
- **风险**：异步测试清理不当可能导致 nextest 报告 `LEAK`
- **相关代码**：
  ```rust
  // codex-rs/app-server/tests/common/mcp_process.rs:626
  /// racing teardown and intermittently show up as `LEAK` in nextest.
  ```
- **缓解**：代码中已实现 `interrupt_turn_and_wait_for_aborted` 等辅助函数确保清理

### 边界情况

#### 1. 测试过滤表达式复杂度
当前 overrides 使用复杂的过滤表达式：
```toml
filter = 'package(codex-app-server-protocol) & (test(a) | test(b) | ... | test(e))'
```

- **边界**：新增 schema 测试时需要更新此配置
- **风险**：忘记更新导致新测试未加入单线程组，可能产生 flaky 结果

#### 2. 平台差异
- **边界**：某些测试（如 `connection_handling_websocket_unix`）仅在 Unix 平台编译
- **影响**：Windows 上这些测试不存在，过滤表达式仍能正常工作

#### 3. 与 `serial_test` crate 的交互
部分测试使用 `#[serial(mcp_test_value)]`：
- `serial_test` 在测试代码层面串行化
- `test-groups` 在 nextest 运行时层面串行化
- **潜在冲突**：双重串行化可能导致不必要的性能损失

### 改进建议

#### 1. 增加注释说明测试选择原因
当前配置中某些测试（如 `approval_matrix_covers_all_modes`）的超时原因未明确说明。建议：

```toml
[[profile.default.overrides]]
# 原因：遍历 20+ 种审批策略组合，每种组合需启动 mock server
filter = 'test(approval_matrix_covers_all_modes)'
slow-timeout = { period = "30s", terminate-after = 2 }
```

#### 2. 考虑按测试文件分组
当前 `app_server_integration` 组包含所有 app-server 测试。如果测试数量继续增长，可考虑：

```toml
[test-groups.app_server_integration_ws]
max-threads = 1

[test-groups.app_server_integration_unix]
max-threads = 1
```

#### 3. 定期审查超时配置
建议每季度审查：
- 是否有测试频繁接近超时阈值
- 是否有新测试需要加入特殊超时组
- 是否有已修复的测试可以移出慢测试组

#### 4. 考虑使用 nextest 的其他特性
当前配置仅使用了基础功能，可考虑：

```toml
# 失败测试自动重试（针对已知 flaky 的测试）
[[profile.default.overrides]]
filter = 'test(known_flaky_test)'
retries = { count = 2, backoff = "fixed", delay = "1s" }

# 特定测试的环境变量
[[profile.default.overrides]]
filter = 'package(codex-core) & test(network)'
env = { "CODEX_SANDBOX_NETWORK_DISABLED" = "1" }
```

#### 5. 监控测试执行时间
建议定期运行：
```bash
cargo nextest run --profile ci --no-fail-fast 2>&1 | tee test-timing.log
```

分析输出中的慢测试，及时调整配置。

### 相关文档链接

- [nextest 官方文档](https://nexte.st/docs/)
- [nextest 配置参考](https://nexte.st/docs/configuration/)
- [过滤表达式语法](https://nexte.st/docs/filtersets/)
- [慢测试处理](https://nexte.st/docs/features/slow-tests/)
