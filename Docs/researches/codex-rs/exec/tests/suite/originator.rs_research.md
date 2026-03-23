# originator.rs 深度研究文档

## 场景与职责

`originator.rs` 是 `codex-exec` CLI 工具的 HTTP Header 测试模块，专门验证 `Originator` Header 的正确设置。该 Header 用于标识请求的来源客户端类型，便于服务端进行统计和差异化处理。

**核心场景**：
- 服务端需要区分不同客户端（CLI、TUI、Web 等）
- 默认使用 `codex_exec` 作为标识
- 支持通过环境变量覆盖默认值

## 功能点目的

### 1. 默认 Originator 测试 (`send_codex_exec_originator`)

验证默认情况下，`codex-exec` 会在 HTTP 请求中发送 `Originator: codex_exec` Header。

### 2. 自定义 Originator 测试 (`supports_originator_override`)

验证可以通过 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` 环境变量自定义 Originator 值。

## 具体技术实现

### HTTP Header 规范

**默认 Header**:
```
Originator: codex_exec
```

**自定义 Header**（通过环境变量）:
```
CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_exec_override
Originator: codex_exec_override
```

### 测试流程

#### 默认 Originator 测试
```
创建 TestCodexExec 环境
  ↓
启动 Mock SSE 服务器
  ↓
使用 mount_sse_once_match 挂载带 Header 匹配的 Mock
  ├─ 匹配条件: header("Originator", "codex_exec")
  └─ 响应: SSE 事件序列
  ↓
执行 codex-exec 命令
  ├─ --skip-git-repo-check
  └─ "tell me something"
  ↓
验证命令成功执行
```

#### 自定义 Originator 测试
```
创建 TestCodexExec 环境
  ↓
启动 Mock SSE 服务器
  ↓
使用 mount_sse_once_match 挂载带 Header 匹配的 Mock
  ├─ 匹配条件: header("Originator", "codex_exec_override")
  └─ 响应: SSE 事件序列
  ↓
执行 codex-exec 命令
  ├─ 环境变量: CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_exec_override
  ├─ --skip-git-repo-check
  └─ "tell me something"
  ↓
验证命令成功执行
```

### 关键代码

**Header 匹配器**:
```rust
use wiremock::matchers::header;

// 默认测试
responses::mount_sse_once_match(&server, header("Originator", "codex_exec"), body).await;

// 自定义测试
responses::mount_sse_once_match(&server, header("Originator", "codex_exec_override"), body).await;
```

**环境变量移除**（确保测试隔离）:
```rust
// 默认测试中移除环境变量，确保使用默认值
test.cmd_with_server(&server)
    .env_remove(CODEX_INTERNAL_ORIGINATOR_OVERRIDE_ENV_VAR)
    ...
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **环境变量常量**: `codex-rs/core/src/default_client.rs`
   ```rust
   pub const CODEX_INTERNAL_ORIGINATOR_OVERRIDE_ENV_VAR: &str = 
       "CODEX_INTERNAL_ORIGINATOR_OVERRIDE";
   ```

2. **Originator 设置**: `codex-rs/exec/src/lib.rs:162-164`
   ```rust
   pub async fn run_main(cli: Cli, arg0_paths: Arg0DispatchPaths) -> anyhow::Result<()> {
       if let Err(err) = set_default_originator("codex_exec".to_string()) {
           tracing::warn!(?err, "Failed to set codex exec originator override {err:?}");
       }
       ...
   }
   ```

3. **HTTP 客户端**: `codex-rs/core/src/default_client.rs`
   - 读取环境变量或默认值
   - 添加到每个 HTTP 请求的 Header

4. **设置函数**: `codex-rs/core/src/default_client.rs`
   ```rust
   pub fn set_default_originator(originator: String) -> Result<(), String> {
       // 设置全局默认 originator
       // 可被环境变量覆盖
   }
   ```

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `default_client` | `codex-rs/core/src/default_client.rs` | Originator 常量定义 |
| `test_codex_exec` | `codex-rs/core/tests/common/test_codex_exec.rs` | 测试环境 |
| `responses` | `codex-rs/core/tests/common/responses.rs` | Mock 工具 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器和 Header 匹配 |
| `assert_cmd` | CLI 测试断言 |
| `tokio` | 异步运行时 |

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | - | 可选，覆盖默认 originator |

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

## 风险、边界与改进建议

### 当前风险

1. **内部 API**: `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` 是内部变量，可能变更
2. **Header 名称硬编码**: 测试依赖特定的 Header 名称
3. **单一验证点**: 仅验证 Header 存在，不验证服务端处理

### 边界情况

1. **空值处理**: 未测试空字符串 originator
2. **特殊字符**: 未测试包含特殊字符的 originator
3. **长度限制**: 未测试超长 originator
4. **并发修改**: 未测试运行中修改环境变量

### 改进建议

1. **增加边界测试**:
   ```rust
   #[tokio::test]
   async fn handles_empty_originator() { ... }
   
   #[tokio::test]
   async fn handles_special_chars_in_originator() { ... }
   ```

2. **验证服务端行为**: 测试服务端如何根据 originator 差异化处理

3. **文档化**: 在 CLI 文档中说明 originator 的用途

4. **标准化**: 定义允许的 originator 值列表

### 相关文件

- `codex-rs/core/src/default_client.rs` - Originator 实现
- `codex-rs/exec/src/lib.rs` - Exec 启动逻辑

### 客户端标识对照

| 客户端 | Originator 值 |
|--------|---------------|
| codex-exec | `codex_exec` |
| codex-tui | `codex_tui` |
| 自定义 | 通过环境变量设置 |
