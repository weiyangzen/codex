# CommandExecOutputDeltaNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`CommandExecOutputDeltaNotification` 是服务器向客户端发送的流式通知，用于实时传递 `command/exec` 命令执行的标准输出/错误输出。

**使用场景：**
- 执行长时间运行的命令时实时查看输出
- 交互式命令（如 REPL）的实时输出
- PTY 模式的终端输出流
- 监控命令执行进度

**职责：**
- 实时传输 stdout/stderr 输出
- 支持 base64 编码的二进制数据
- 指示输出是否被截断（capReached）
- 通过 processId 关联到具体命令实例

## 2. 功能点目的 (Purpose of the Functionality)

该通知的核心目的是实现命令执行的实时输出流：

1. **实时反馈**: 用户无需等待命令完成即可看到输出
2. **交互支持**: 支持交互式命令的实时输入输出
3. **二进制支持**: 通过 base64 支持二进制数据
4. **流量控制**: 指示输出截断情况

**字段说明：**
- `processId` (string, required): 命令实例标识
- `stream` (`CommandExecOutputStream`, required): 输出流类型（stdout/stderr）
- `deltaBase64` (string, required): base64 编码的输出内容
- `capReached` (boolean, required): 是否达到输出上限

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构设计

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecOutputDeltaNotification {
    /// Client-supplied, connection-scoped `processId` from the original `command/exec` request.
    pub process_id: String,
    /// Output stream for this chunk.
    pub stream: CommandExecOutputStream,
    /// Base64-encoded output bytes.
    pub delta_base64: String,
    /// `true` on the final streamed chunk for a stream when `outputBytesCap` truncated later output on that stream.
    pub cap_reached: bool,
}

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

### 协议集成

在 `common.rs` 中注册：

```rust
server_notification_definitions! {
    CommandExecOutputDelta => "command/exec/outputDelta" (v2::CommandExecOutputDeltaNotification),
}
```

### 流式传输流程

1. 客户端发送 `command/exec` 请求（启用 `streamStdoutStderr`）
2. 服务器启动命令执行
3. 命令产生输出时，发送 `CommandExecOutputDeltaNotification`
4. 客户端解码 base64 并展示输出
5. 命令完成后发送 `CommandExecResponse`

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **主要定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` (第 2436-2445 行)
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs`

### 相关类型
- `CommandExecParams`: 命令执行参数
- `CommandExecResponse`: 命令执行响应
- `CommandExecWriteParams`: 写入 stdin 参数

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/CommandExecOutputDeltaNotification.json`

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `CommandExecOutputStream` 枚举
- base64 编解码

### 外部交互
- **进程管理**: 捕获子进程输出
- **PTY**: PTY 模式的终端输出

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **乱序到达**: 网络问题可能导致输出乱序
2. **base64 开销**: 编码增加约 33% 数据量
3. **内存累积**: 大量输出可能导致内存问题

### 边界情况

1. **空输出**: 命令无输出时的处理
2. **超大输出**: 超出 cap 的截断处理
3. **二进制数据**: 非 UTF-8 数据的处理

### 改进建议

1. **添加序号**: 用于排序和丢包检测
2. **原始模式**: 支持原始字节传输（非 base64）
3. **压缩选项**: 大量数据时启用压缩

### 客户端实现建议

1. 累积解码后的输出
2. 区分 stdout 和 stderr 展示
3. 处理 capReached 的提示
4. 支持 ANSI 颜色代码解析
