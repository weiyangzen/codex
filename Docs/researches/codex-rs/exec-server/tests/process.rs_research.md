# process.rs 研究文档

## 场景与职责

`process.rs` 是 `codex-exec-server` 的集成测试文件，专门用于验证进程管理相关的 JSON-RPC 方法。当前测试聚焦于 `process/start` 方法的存根（stub）实现行为验证。

在 Codex 架构中，exec-server 负责在沙箱环境中执行外部命令。`process/start` 方法是启动新进程的核心 API，允许客户端指定命令参数、工作目录、环境变量等。当前该功能尚未完全实现，测试验证了存根返回正确的错误信息。

## 功能点目的

### 1. 存根实现验证 (`exec_server_stubs_process_start_over_websocket`)

该测试的核心目的是验证：
- 在初始化完成后，服务器能够接收 `process/start` 请求
- 对于未实现的方法，服务器返回标准的 JSON-RPC 错误
- 错误码符合 JSON-RPC 2.0 规范（Method Not Found: -32601）
- 错误消息清晰表明该方法尚未实现

### 2. 协议状态机验证

测试验证了完整的状态转换：
1. 初始状态 → 2. 初始化请求 → 3. 初始化完成 → 4. 业务请求 → 5. 错误响应

## 具体技术实现

### 关键流程

```
测试启动
    ↓
启动 exec-server 子进程
    ↓
建立 WebSocket 连接
    ↓
发送 initialize 请求 (等待响应确认)
    ↓
发送 process/start 请求
    │   method: "process/start"
    │   params: {
    │       "processId": "proc-1",
    │       "argv": ["true"],
    │       "cwd": <当前目录>,
    │       "env": {},
    │       "tty": false,
    │       "arg0": null
    │   }
    ↓
等待错误响应
    ↓
验证错误
    │   - 确认是 JSONRPCMessage::Error 类型
    │   - 验证 error.code == -32601 (Method Not Found)
    │   - 验证错误消息包含 "exec-server stub does not implement"
    ↓
关闭连接并清理
```

### 请求参数结构

```rust
// process/start 请求参数（内联 JSON）
{
    "processId": "proc-1",        // 客户端指定的进程标识
    "argv": ["true"],              // 命令行参数数组
    "cwd": "/current/working/dir", // 工作目录
    "env": {},                     // 环境变量映射
    "tty": false,                  // 是否分配伪终端
    "arg0": null                   // 可选的 arg0 覆盖
}
```

### JSON-RPC 错误码

| 错误码 | 含义 | 来源 |
|--------|------|------|
| -32601 | Method not found | JSON-RPC 2.0 标准 |

### 错误响应结构

```rust
JSONRPCError {
    id: RequestId::Integer(2),  // 与请求 ID 匹配
    error: JSONRPCErrorError {
        code: -32601,
        message: "exec-server stub does not implement `process/start` yet",
        data: None,
    }
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/exec-server/tests/process.rs` - 本测试文件
- `codex-rs/exec-server/tests/common/exec_server.rs` - 测试辅助工具

### 被测试的源代码
- `codex-rs/exec-server/src/server/processor.rs` - 请求分发逻辑
  - `dispatch_request()` 函数处理请求路由
  - 未匹配的方法返回 `method_not_found` 错误
- `codex-rs/exec-server/src/server/jsonrpc.rs` - JSON-RPC 辅助函数
  - `method_not_found()` 创建标准错误
  - `response_message()` 包装响应

### 错误生成代码路径
```rust
// processor.rs:dispatch_request
other => response_message(
    id,
    Err(method_not_found(format!(
        "exec-server stub does not implement `{other}` yet"
    ))),
)

// jsonrpc.rs:method_not_found
pub(crate) fn method_not_found(message: String) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32601,
        data: None,
        message,
    }
}
```

### 辅助方法
- `ExecServerHarness::wait_for_event()` - 带谓词函数的事件等待
- 使用 `matches!` 宏进行模式匹配筛选事件

## 依赖与外部交互

### 运行时依赖
- **Tokio**: 异步运行时，多线程模式
- **anyhow**: 错误处理

### 协议依赖
- `codex_app_server_protocol::JSONRPCError` - 错误消息类型
- `codex_app_server_protocol::JSONRPCMessage` - 消息枚举

### 条件编译
```rust
#![cfg(unix)]
```
与 initialize.rs 相同，仅 Unix 平台执行。

### 测试辅助函数
```rust
// 等待匹配特定条件的事件
pub(crate) async fn wait_for_event<F>(
    &mut self,
    mut predicate: F,
) -> anyhow::Result<JSONRPCMessage>
where
    F: FnMut(&JSONRPCMessage) -> bool,
```

## 风险、边界与改进建议

### 当前限制

1. **存根状态**: `process/start` 尚未实现，测试仅验证错误响应
2. **有限参数测试**: 仅测试了最基本的参数组合
3. **无并发测试**: 未测试多个进程同时启动的场景

### 边界情况分析

1. **进程 ID 冲突**: 当 `processId` 已存在时的行为
2. **无效工作目录**: `cwd` 指向不存在目录的错误处理
3. **环境变量大小**: 大量环境变量时的性能表现
4. **TTY 模式**: `tty: true` 时的伪终端分配

### 未来实现建议

当 `process/start` 完整实现后，建议添加以下测试：

```rust
// 1. 基本进程启动
#[tokio::test]
async fn process_start_executes_command() { ... }

// 2. 进程 ID 唯一性验证
#[tokio::test]
async fn process_start_rejects_duplicate_id() { ... }

// 3. 工作目录验证
#[tokio::test]
async fn process_start_respects_cwd() { ... }

// 4. 环境变量传递
#[tokio::test]
async fn process_start_passes_env_vars() { ... }

// 5. TTY 模式
#[tokio::test]
async fn process_start_allocates_pty_when_tty_true() { ... }

// 6. 进程输出捕获
#[tokio::test]
async fn process_start_streams_stdout_stderr() { ... }
```

### 架构改进建议

1. **进程生命周期管理**:
   - 考虑添加 `process/list` 方法查询活跃进程
   - 考虑添加 `process/kill` 方法强制终止进程

2. **资源限制**:
   - 实现超时机制防止进程无限运行
   - 添加内存/CPU 使用限制

3. **安全性增强**:
   - 验证命令白名单
   - 路径遍历防护

### 相关测试文件
- `initialize.rs` - 初始化流程测试
- `websocket.rs` - 连接和错误处理测试
