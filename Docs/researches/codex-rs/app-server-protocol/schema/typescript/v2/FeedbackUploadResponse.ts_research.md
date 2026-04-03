# FeedbackUploadResponse.ts 研究文档

## 场景与职责

`FeedbackUploadResponse.ts` 定义了反馈上传请求的响应类型，用于确认用户反馈已成功接收。这是 Codex 用户反馈系统的组成部分，帮助团队收集用户意见和问题报告。

该类型在用户反馈提交、问题报告、体验改进等场景中发挥作用。

## 功能点目的

1. **确认接收**: 确认反馈已成功上传
2. **关联线程**: 将反馈与特定线程关联，便于后续跟进
3. **日志关联**: 支持包含日志文件进行问题诊断

## 具体技术实现

### 数据结构定义

```typescript
export type FeedbackUploadResponse = { 
  threadId: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 反馈关联的线程 ID |

### 请求参数

```typescript
export type FeedbackUploadParams = {
  classification: string,      // 反馈分类（如 bug、feature_request）
  reason?: string | null,      // 反馈原因/描述
  threadId?: string | null,    // 关联的线程 ID
  includeLogs: boolean,        // 是否包含日志
  extraLogFiles?: Array<string> | null,  // 额外的日志文件路径
};
```

### 使用示例

```typescript
// 提交反馈
const params: FeedbackUploadParams = {
  classification: 'bug',
  reason: '模型响应不正确',
  threadId: 'thread-123',
  includeLogs: true
};

const response: FeedbackUploadResponse = await client.uploadFeedback(params);
console.log(`反馈已提交，关联线程: ${response.threadId}`);
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2111-2116)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct FeedbackUploadResponse {
    pub thread_id: String,
}
```

### 请求参数

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2100-2109)

```rust
pub struct FeedbackUploadParams {
    pub classification: String,
    #[ts(optional = nullable)]
    pub reason: Option<String>,
    #[ts(optional = nullable)]
    pub thread_id: Option<String>,
    pub include_logs: bool,
    #[ts(optional = nullable)]
    pub extra_log_files: Option<Vec<PathBuf>>,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 客户端**: 提交用户反馈
- **VS Code 扩展**: 集成反馈功能
- **反馈收集服务**: 接收和处理反馈数据

## 风险、边界与改进建议

### 已知风险

1. **响应简单**: 仅返回 threadId，缺乏详细的提交状态
2. **日志隐私**: 包含日志可能泄露敏感信息
3. **重复提交**: 缺乏防重复提交机制

### 边界情况

1. **线程不存在**: 指定的 threadId 可能不存在
2. **日志过大**: 包含大量日志可能导致请求失败
3. **网络中断**: 上传过程中可能失败

### 改进建议

1. **详细状态**: 返回提交状态、处理队列位置等
2. **反馈 ID**: 返回唯一的反馈 ID 用于查询
3. **上传进度**: 大日志文件支持进度通知
4. **隐私审查**: 上传前预览和编辑日志内容
5. **自动脱敏**: 自动移除日志中的敏感信息
6. **确认邮件**: 支持发送确认邮件给用户

### 扩展示例

```typescript
export type FeedbackUploadResponse = { 
  threadId: string,
  // 新增字段
  feedbackId: string,  // 唯一反馈 ID
  status: 'queued' | 'processing' | 'completed',
  estimatedProcessingTime: number,  // 预计处理时间（秒）
  queuePosition: number,  // 队列位置
};
```
