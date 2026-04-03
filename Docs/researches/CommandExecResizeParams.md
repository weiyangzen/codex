# CommandExecResizeParams 研究报告

## 1. 场景与职责

### 使用场景
`CommandExecResizeParams` 是 app-server-protocol v2 API 中用于调整正在运行的 PTY（伪终端）会话大小的请求参数结构。它主要用于以下场景：

- **终端窗口调整**：当用户调整终端模拟器窗口大小时，需要同步更新 PTY 的尺寸
- **响应式布局**：支持根据可用空间动态调整终端大小
- **多设备适配**：在不同屏幕尺寸的设备上提供合适的终端体验
- **分屏/标签页切换**：在终端复用器（如 tmux）或 IDE 集成终端中切换布局时

### 核心职责
1. **尺寸更新**：向运行的 PTY 会话发送新的终端尺寸（行数/列数）
2. **进程标识**：通过 `processId` 定位目标 PTY 会话
3. **实时同步**：确保终端应用程序能够及时响应窗口大小变化（SIGWINCH 信号）

## 2. 功能点目的

### 设计目标
- **终端兼容性**：支持需要知道终端尺寸的应用程序（如 vim、top、htop）
- **用户体验**：确保终端内容正确渲染，避免截断或换行问题
- **标准化**：提供统一的接口处理跨平台的终端大小调整

### 关键特性
| 特性 | 说明 |
|------|------|
| 精确尺寸控制 | 以字符单元（行/列）为单位指定终端大小 |
| 进程绑定 | 通过 `processId` 精确控制特定会话 |
| 即时生效 | 调整立即生效，应用程序收到 SIGWINCH 信号 |
| 与 TTY 模式配合 | 仅在 `tty=true` 的 `command/exec` 会话中有效 |

## 3. 具体技术实现

### 数据结构定义

```rust
// Rust 结构定义 (v2.rs)
/// Resize a running PTY-backed `command/exec` session.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecResizeParams {
    /// Client-supplied, connection-scoped `processId` from the original
    /// `command/exec` request.
    pub process_id: String,
    /// New PTY size in character cells.
    pub size: CommandExecTerminalSize,
}

/// PTY size in character cells for `command/exec` PTY sessions.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecTerminalSize {
    /// Terminal height in character cells.
    pub rows: u16,
    /// Terminal width in character cells.
    pub cols: u16,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "CommandExecTerminalSize": {
      "description": "PTY size in character cells for `command/exec` PTY sessions.",
      "properties": {
        "cols": {
          "description": "Terminal width in character cells.",
          "format": "uint16",
          "minimum": 0,
          "type": "integer"
        },
        "rows": {
          "description": "Terminal height in character cells.",
          "format": "uint16",
          "minimum": 0,
          "type": "integer"
        }
      },
      "required": ["cols", "rows"],
      "type": "object"
    }
  },
  "description": "Resize a running PTY-backed `command/exec` session.",
  "properties": {
    "processId": {
      "description": "Client-supplied, connection-scoped `processId` from the original `command/exec` request.",
      "type": "string"
    },
    "size": {
      "allOf": [{ "$ref": "#/definitions/CommandExecTerminalSize" }],
      "description": "New PTY size in character cells."
    }
  },
  "required": ["processId", "size"],
  "title": "CommandExecResizeParams",
  "type": "object"
}
```

### 字段详细说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `processId` | string | 是 | 原始 `command/exec` 请求中提供的连接作用域进程标识符 |
| `size` | CommandExecTerminalSize | 是 | 新的 PTY 尺寸 |
| `size.rows` | integer (u16) | 是 | 终端高度（字符行数） |
| `size.cols` | integer (u16) | 是 | 终端宽度（字符列数） |

### 使用示例

```json
{
  "processId": "terminal-session-001",
  "size": {
    "rows": 24,
    "cols": 80
  }
}
```

## 4. 关键代码路径与文件引用

### 核心文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 2418-2428 行） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `CommandExecTerminalSize` 定义（第 2270-2278 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义（第 471-475 行） |
| `codex-rs/app-server-protocol/schema/json/v2/CommandExecResizeParams.json` | JSON Schema 文件 |

### 协议注册

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    /// Resize a running PTY-backed `command/exec` session by client-supplied `processId`.
    CommandExecResize => "command/exec/resize" {
        params: v2::CommandExecResizeParams,
        response: v2::CommandExecResizeResponse,
    },
    // ...
}
```

### 关联类型

- `CommandExecParams` - 初始命令执行请求（需设置 `tty=true`）
- `CommandExecResizeResponse` - 调整大小操作的响应（空成功响应）
- `CommandExecTerminalSize` - 终端尺寸结构（复用类型）

## 5. 依赖与外部交互

### 内部依赖

```
CommandExecResizeParams
├── CommandExecTerminalSize (结构体)
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
└── std::u16 (行/列数值类型)
```

### 外部交互

1. **与 PTY 系统的交互**：
   - 调用操作系统 PTY API 调整窗口大小
   - 在 Unix/Linux 上通常使用 `ioctl` 系统调用（TIOCSWINSZ）
   - 向 PTY 主设备发送窗口大小变更

2. **与信号系统的交互**：
   - 调整大小后，子进程通常会收到 SIGWINCH 信号
   - 应用程序可以通过处理 SIGWINCH 重新查询终端大小并刷新界面

3. **与进程管理的交互**：
   - 通过 `processId` 查找对应的 PTY 会话
   - 验证进程是否仍在运行且处于 PTY 模式

### 平台实现差异

| 平台 | 实现方式 |
|------|----------|
| Linux/macOS | 使用 `ioctl(fd, TIOCSWINSZ, &winsize)` |
| Windows | 使用 Windows Console API 或 ConPTY |

### 生成产物

- TypeScript 类型定义（`v2/CommandExecResizeParams.ts`）
- JSON Schema（`schema/json/v2/CommandExecResizeParams.json`）

## 6. 风险、边界与改进建议

### 潜在风险

1. **无效进程 ID**：
   - 指定的 `processId` 不存在或已终止
   - 需要适当的错误处理

2. **非 PTY 会话**：
   - 尝试调整非 TTY 模式的会话大小
   - 应返回明确的错误信息

3. **极端尺寸值**：
   - 过大的尺寸可能导致应用程序异常
   - 零或负值可能引发问题

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| processId 不存在 | 返回错误（如 ProcessNotFound） |
| 进程已退出 | 返回错误（如 ProcessTerminated） |
| 非 TTY 模式会话 | 返回错误（如 NotAPtySession） |
| rows/cols 为 0 | 可能被视为无效输入 |
| 尺寸与之前相同 | 操作成功，但无实际效果 |

### 改进建议

1. **尺寸限制**：
   - 添加最小/最大尺寸限制（如最小 1x1，最大 999x999）
   - 防止极端值导致的问题

2. **批量调整**：
   - 支持一次调整多个 PTY 会话的大小
   - 添加 `processIds` 数组字段

3. **自动检测**：
   - 支持自动检测最佳终端大小
   - 添加 `autoSize` 选项

4. **历史记录**：
   - 记录尺寸变更历史
   - 支持恢复到之前的尺寸

5. **错误详细信息**：
   - 提供更详细的错误原因
   - 如：进程不存在、权限不足、非 PTY 会话等

6. **尺寸查询**：
   - 添加查询当前终端尺寸的 API
   - 便于客户端同步状态

### 最佳实践

1. **防抖处理**：
   - 客户端应对窗口大小变化事件进行防抖
   - 避免频繁发送调整请求

2. **比例保持**：
   - 考虑终端内容的纵横比
   - 避免内容被过度压缩或拉伸

3. **渐进调整**：
   - 对于大幅尺寸变化，考虑分步调整
   - 给应用程序时间适应新尺寸
