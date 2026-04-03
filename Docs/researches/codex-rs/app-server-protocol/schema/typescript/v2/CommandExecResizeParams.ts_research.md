# CommandExecResizeParams.ts 研究文档

## 场景与职责

`CommandExecResizeParams.ts` 定义了调整 PTY（伪终端）大小的请求参数类型，用于 `command/exec/resize` API。当客户端运行的交互式程序（如 vim、htop、tmux）需要适应新的终端尺寸时，通过此 API 通知服务器调整 PTY 的大小。

该类型是 Codex 交互式命令执行系统的重要组成部分，支持响应式终端体验。

## 功能点目的

### 核心功能

1. **终端尺寸调整**：动态调整运行中 PTY 的行数和列数
2. **窗口变化响应**：支持客户端窗口大小变化时的自适应
3. **SIGWINCH 信号**：触发向子进程发送窗口变化信号
4. **多会话管理**：通过 `processId` 定位特定 PTY 会话

### 类型定义

```typescript
import type { CommandExecTerminalSize } from "./CommandExecTerminalSize";

/**
 * Resize a running PTY-backed `command/exec` session.
 */
export type CommandExecResizeParams = { 
  /**
   * Client-supplied, connection-scoped `processId` from the original
   * `command/exec` request.
   */
  processId: string, 
  /**
   * New PTY size in character cells.
   */
  size: CommandExecTerminalSize, 
};
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `processId` | `string` | 是 | 原始 `command/exec` 请求中的进程标识符 |
| `size` | `CommandExecTerminalSize` | 是 | 新的终端大小（行数和列数） |

### CommandExecTerminalSize

```typescript
type CommandExecTerminalSize = {
  rows: number;  // 终端高度（字符行数）
  cols: number;  // 终端宽度（字符列数）
};
```

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2418-2434)

```rust
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

/// Empty success response for `command/exec/resize`.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecResizeResponse {}
```

### 终端大小定义

```rust
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

### 系统调用

在 Unix 系统上，调整 PTY 大小通常涉及：

```rust
// 伪代码
use libc::{winsize, TIOCSWINSZ};

fn resize_pty(fd: RawFd, rows: u16, cols: u16) -> Result<()> {
    let ws = winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,  // 可选的像素尺寸
        ws_ypixel: 0,
    };
    
    unsafe {
        ioctl(fd, TIOCSWINSZ, &ws);
    }
    
    // 向子进程发送 SIGWINCH 信号
    kill(child_pid, SIGWINCH);
    
    Ok(())
}
```

## 关键代码路径与文件引用

### 依赖关系

```
CommandExecResizeParams.ts
  └── CommandExecTerminalSize.ts
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `CommandExecTerminalSize.ts` | 终端大小结构 |
| `CommandExecResizeResponse.ts` | 调整响应（空对象） |
| `CommandExecParams.ts` | 初始执行参数（包含初始 size） |

### 完整流程

```
Client                              Server
  |                                    |
  |-- command/exec ------------------->|
  |   {                                |
  |     command: ["vim", "file.txt"],  |
  |     processId: "vim-123",          |
  |     tty: true,                     |
  |     size: { rows: 24, cols: 80 }   |
  |   }                                |
  |<-- outputDelta notifications       |
  |                                    |
  |   [用户调整窗口大小]                |
  |                                    |
  |-- command/exec/resize ------------>|
  |   {                                |
  |     processId: "vim-123",          |
  |     size: { rows: 30, cols: 100 }  |
  |   }                                |
  |<-- CommandExecResizeResponse ------|
  |   {}                               |
  |                                    |
  |   [vim 收到 SIGWINCH，重绘界面]      |
```

## 依赖与外部交互

### 浏览器/客户端集成

在 Web 客户端中，通常监听窗口大小变化：

```typescript
// 浏览器环境
const resizeObserver = new ResizeObserver((entries) => {
  for (const entry of entries) {
    const { rows, cols } = calculateTerminalSize(entry.contentRect);
    
    client.send({
      method: "command/exec/resize",
      params: {
        processId: currentProcessId,
        size: { rows, cols },
      },
    });
  }
});

resizeObserver.observe(terminalElement);
```

### 桌面客户端集成

在桌面客户端（如 TUI）中：

```typescript
// 监听终端大小变化信号
process.on('SIGWINCH', () => {
  const { rows, cols } = process.stdout;
  
  client.send({
    method: "command/exec/resize",
    params: {
      processId: currentProcessId,
      size: { rows, cols },
    },
  });
});
```

### 限制条件

1. **PTY 模式必需**：只对 `tty: true` 的会话有效
2. **连接作用域**：必须在原始连接上发送
3. **进程存在**：目标进程必须仍在运行

## 风险、边界与改进建议

### 潜在风险

1. **尺寸计算错误**：客户端计算的行列数可能不准确
2. **频繁调整**：快速连续调整可能导致性能问题
3. **不支持的应用**：某些程序可能不响应 SIGWINCH
4. **竞态条件**：调整时进程可能刚好退出

### 边界情况

1. **非 PTY 会话**：
   - 对非 PTY 命令调用 resize 应返回错误
   - 错误信息：`"Resize only supported for PTY sessions"`

2. **无效尺寸**：
   - `rows` 或 `cols` 为 0 应被拒绝
   - 过大尺寸（如 10000x10000）可能被限制

3. **进程已退出**：
   - 返回错误：`"Process not found"`

4. **连接断开**：
   - 无法发送 resize（进程可能已终止）

### 改进建议

1. **添加防抖**：
   ```typescript
   // 客户端实现
   const debouncedResize = debounce((size) => {
     sendResizeRequest(size);
   }, 100);  // 100ms 防抖
   ```

2. **添加最小尺寸限制**：
   ```typescript
   interface CommandExecResizeParams {
     processId: string;
     size: CommandExecTerminalSize;
     minRows?: number;  // 可选的最小尺寸提示
     minCols?: number;
   }
   ```

3. **支持像素尺寸**：
   ```typescript
   interface CommandExecTerminalSize {
     rows: number;
     cols: number;
     widthPx?: number;   // 新增：像素宽度
     heightPx?: number;  // 新增：像素高度
   }
   ```

4. **批量调整**：
   ```typescript
   interface CommandExecResizeBatchParams {
     resizes: Array<{
       processId: string;
       size: CommandExecTerminalSize;
     }>;
   }
   ```

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定
- 向后兼容：是

### 最佳实践

1. **防抖处理**：客户端应对频繁的大小变化进行防抖
2. **合理默认值**：初始启动时使用合理的默认尺寸（如 24x80）
3. **错误处理**：优雅处理 resize 失败（不影响用户体验）
4. **尺寸计算**：准确计算字符行列数，考虑字体和 DPI
