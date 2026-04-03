# CommandExecOutputStream.ts 研究文档

## 场景与职责

`CommandExecOutputStream.ts` 定义了命令执行输出流的类型枚举，用于 `CommandExecOutputDeltaNotification` 中的 `stream` 字段。该枚举区分 stdout 和 stderr 两个标准输出流，是 Codex 实时命令执行系统的基础类型。

该类型虽然简单，但在流式输出处理中起着关键的标识作用，确保客户端能够正确处理和展示不同来源的输出数据。

## 功能点目的

### 核心功能

1. **流标识**：明确标识输出数据来源于 stdout 还是 stderr
2. **UI 区分**：支持客户端以不同样式展示不同流的输出
3. **日志分离**：便于分别记录和处理标准输出与错误输出
4. **PTY 兼容**：支持伪终端模式下的流多路复用

### 类型定义

```typescript
/**
 * Stream label for `command/exec/outputDelta` notifications.
 */
export type CommandExecOutputStream = "stdout" | "stderr";
```

### 枚举值说明

| 值 | 说明 | 典型用途 |
|----|------|----------|
| `stdout` | 标准输出流 | 正常程序输出、PTY 模式的多路复用输出 |
| `stderr` | 标准错误流 | 错误信息、警告、诊断输出 |

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2436-2445)

```rust
/// Stream label for `command/exec/outputDelta` notifications.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CommandExecOutputStream {
    /// stdout stream. PTY mode multiplexes terminal output here.
    Stdout,
    /// stderr stream.
    Stderr,
}
```

### 序列化规则

- Rust 使用 `PascalCase` 枚举变体命名（`Stdout`, `Stderr`）
- JSON/TypeScript 使用 `camelCase`（通过 `rename_all = "camelCase"` 转换）
- 序列化结果：
  - `Stdout` → `"stdout"`
  - `Stderr` → `"stderr"`

## 关键代码路径与文件引用

### 使用位置

| 文件 | 字段 | 说明 |
|------|------|------|
| `CommandExecOutputDeltaNotification.ts` | `stream` | 输出通知的流标识 |

### 依赖关系

```
CommandExecOutputDeltaNotification.ts
  └── CommandExecOutputStream.ts
```

### 使用示例

```typescript
// 接收输出通知
const notification: CommandExecOutputDeltaNotification = {
  processId: "proc-123",
  stream: "stdout",  // CommandExecOutputStream
  deltaBase64: "SGVsbG8=",
  capReached: false,
};

// UI 展示
if (notification.stream === "stdout") {
  appendToTerminal(notification.deltaBase64, { color: "white" });
} else if (notification.stream === "stderr") {
  appendToTerminal(notification.deltaBase64, { color: "red" });
}
```

## 依赖与外部交互

### PTY 模式行为

在 PTY（伪终端）模式下：

```typescript
const params: CommandExecParams = {
  command: ["vim", "file.txt"],
  processId: "pty-123",
  tty: true,  // 启用 PTY
  streamStdoutStderr: true,
};
```

**重要**：PTY 模式下，所有终端输出（包括原本写入 stderr 的数据）都多路复用到 `stdout` 流。

原因：
- PTY 将 stdout 和 stderr 合并为单个终端输出流
- 这是 Unix 终端的标准行为
- 客户端应将 `stdout` 视为完整的终端输出

### 非 PTY 模式行为

在标准模式下：
- stdout 和 stderr 保持分离
- 客户端可以独立处理两个流
- 支持分别捕获和记录

## 风险、边界与改进建议

### 设计权衡

当前设计采用简单的两个值枚举：

**优点**：
- 简单明了，易于理解和实现
- 与 Unix 标准流概念一致
- 序列化结果紧凑

**缺点**：
- 不支持自定义流
- 无法表示混合流（PTY 模式通过文档约定处理）
- 未来扩展需要新增枚举值（破坏兼容性）

### 边界情况

1. **PTY 模式下的 stderr**：
   - 虽然原始程序写入 stderr
   - 但通知中标记为 `stdout`
   - 客户端无法区分

2. **Windows 平台**：
   - Windows 使用不同的流概念
   - 但 API 保持一致性

3. **空流**：
   - 某些命令可能只使用一个流
   - 另一个流永远不会产生通知

### 改进建议

1. **添加 PTY 标记**（向后兼容）：
   ```typescript
   interface CommandExecOutputDeltaNotification {
     stream: CommandExecOutputStream;
     isPtyMultiplexed?: boolean;  // 指示是否为 PTY 多路复用
   }
   ```

2. **扩展流类型**（向后不兼容）：
   ```typescript
   type CommandExecOutputStream = 
     | "stdout"
     | "stderr"
     | "stdinEcho"   // 新增：回显的输入
     | "control";    // 新增：控制序列
   ```

3. **保持简单**：当前设计对于大部分用例已足够，增加复杂度可能不值得

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定
- 向后兼容：是
- 未来扩展：如需更多流类型，建议在 v3 中设计更灵活的方案

### 测试建议

1. **单元测试**：
   - 验证序列化和反序列化
   - 测试大小写敏感性

2. **集成测试**：
   - 验证 stdout 和 stderr 正确分离
   - 验证 PTY 模式下的流行为

3. **UI 测试**：
   - 验证不同流的样式区分
   - 测试颜色编码正确性
