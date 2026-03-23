# mcp_required_exit.rs 深度研究文档

## 场景与职责

`mcp_required_exit.rs` 是 `codex-exec` CLI 工具的 MCP（Model Context Protocol）服务器集成测试模块，专门验证当必需的 MCP 服务器启动失败时，CLI 能够正确退出并返回非零状态码。

**核心场景**：
- 用户配置了必需的 MCP 服务器（`required = true`）
- MCP 服务器启动失败（如命令不存在）
- CLI 应该报告错误并退出，而不是静默继续

## 功能点目的

### 单测试函数 (`exits_non_zero_when_required_mcp_server_fails_to_initialize`)

验证当必需的 MCP 服务器初始化失败时：
1. `codex-exec` 返回非零退出码（exit code 1）
2. 错误信息包含失败的 MCP 服务器名称
3. 自动化工具能够检测到失败

## 具体技术实现

### MCP 服务器配置

**TOML 配置**（测试中动态生成）：
```toml
[mcp_servers.required_broken]
command = "codex-definitely-not-a-real-binary"
required = true
```

**配置字段说明**：
| 字段 | 值 | 说明 |
|------|-----|------|
| `command` | 不存在的命令 | 模拟启动失败 |
| `required` | `true` | 标记为必需服务器 |

### 测试流程

```
创建 TestCodexExec 环境
  ↓
写入 MCP 配置到临时 CODEX_HOME/config.toml
  ├─ [mcp_servers.required_broken]
  ├─ command = "codex-definitely-not-a-real-binary"
  └─ required = true
  ↓
启动 Mock SSE 服务器
  ├─ 即使 MCP 失败，也挂载正常响应
  └─ （用于验证 CLI 在 MCP 失败时不会继续）
  ↓
执行 codex-exec 命令
  ├─ --skip-git-repo-check
  ├─ --experimental-json
  └─ "tell me something"
  ↓
验证退出码为 1
  ↓
验证 stderr 包含错误信息
  └─ "required MCP servers failed to initialize: required_broken"
```

### SSE Mock 事件

```rust
let body = responses::sse(vec![
    responses::ev_response_created("resp_1"),
    responses::ev_assistant_message("msg_1", "hello"),
    responses::ev_completed("resp_1"),
]);
```

注意：即使挂载了正常响应，CLI 也应该在 MCP 失败时退出，不会继续执行。

## 关键代码路径与文件引用

### 被测试代码路径

1. **MCP 配置解析**: `codex-rs/core/src/config/mcp_servers.rs`
   - 解析 `mcp_servers` 配置段
   - 识别 `required` 标志

2. **MCP 启动逻辑**: `codex-rs/core/src/mcp/mod.rs`
   - 启动配置的 MCP 服务器
   - 检查必需服务器状态

3. **Exec 错误处理**: `codex-rs/exec/src/lib.rs:834-855`
   ```rust
   EventMsg::McpStartupUpdate(update) => {
       if required_mcp_servers.contains(&update.server)
           && let McpStartupStatus::Failed { error } = &update.status
       {
           error_seen = true;
           eprintln!("Required MCP server '{}' failed to initialize: {error}", ...);
           // 请求关闭并退出
       }
   }
   ```

4. **必需服务器收集**: `codex-rs/exec/src/lib.rs:497-503`
   ```rust
   let required_mcp_servers: HashSet<String> = config
       .mcp_servers
       .get()
       .iter()
       .filter(|(_, server)| server.enabled && server.required)
       .map(|(name, _)| name.clone())
       .collect();
   ```

### MCP 启动状态

```rust
pub enum McpStartupStatus {
    Starting,
    Running,
    Failed { error: String },
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器 |
| `predicates` | 字符串匹配断言 |
| `assert_cmd` | CLI 测试断言 |
| `tokio` | 异步运行时 |

### 测试工具

| 工具 | 来源 | 用途 |
|------|------|------|
| `test_codex_exec` | `core_test_support` | 测试环境构造 |
| `responses::start_mock_server` | `core_test_support` | Mock SSE |
| `responses::mount_sse_once` | `core_test_support` | 挂载响应 |

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

## 风险、边界与改进建议

### 当前风险

1. **时序敏感**: MCP 启动和检测的时序可能影响测试结果
2. **错误信息匹配**: 依赖特定错误信息格式
3. **单一路径**: 仅测试命令不存在的情况

### 边界情况

1. **部分失败**: 多个必需服务器，部分失败
2. **超时场景**: MCP 启动超时
3. **权限问题**: MCP 命令存在但无执行权限
4. **配置错误**: 无效的配置格式
5. **依赖缺失**: MCP 命令存在但依赖库缺失

### 改进建议

1. **增加场景覆盖**:
   ```rust
   // 部分 MCP 失败
   // MCP 超时
   // MCP 崩溃后重启
   ```

2. **错误分类测试**: 验证不同失败原因的错误信息

3. **恢复测试**: 测试 MCP 失败后的优雅关闭

4. **日志验证**: 验证错误日志包含足够诊断信息

5. **并发测试**: 多个必需 MCP 同时失败的场景

### 相关文件

- `codex-rs/core/src/config/mcp_servers.rs` - MCP 配置
- `codex-rs/core/src/mcp/mod.rs` - MCP 客户端实现
- `codex-rs/exec/src/lib.rs` - Exec 主逻辑

### MCP 协议参考

- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- 基于 `rmcp` crate 实现
