# DynamicToolCallResponse.ts Research Document

## 场景与职责

`DynamicToolCallResponse` 是 Codex App-Server Protocol v2 API 中用于表示动态工具调用响应的数据结构。当客户端通过 `DynamicToolCallParams` 调用动态工具后，服务器会返回此响应对象，包含工具执行的结果内容和执行状态。

动态工具（Dynamic Tools）是 Codex 系统中一种可扩展的工具机制，允许在运行时注册和调用自定义工具。与静态工具不同，动态工具可以在不重启服务的情况下被添加、修改或移除。

## 功能点目的

该类型的主要目的是：

1. **封装工具执行结果**：将动态工具调用的输出内容（文本、图片等）进行标准化封装
2. **指示执行状态**：通过 `success` 字段明确告知工具调用是否成功
3. **支持多模态输出**：允许返回多种类型的内容项（文本、图片等）
4. **与 ThreadItem 集成**：作为 `ThreadItem::DynamicToolCall` 的一部分，参与对话历史的构建

## 具体技术实现

### 数据结构定义

```typescript
// DynamicToolCallResponse.ts
import type { DynamicToolCallOutputContentItem } from "./DynamicToolCallOutputContentItem";

export type DynamicToolCallResponse = { 
  contentItems: Array<DynamicToolCallOutputContentItem>, 
  success: boolean, 
};
```

### 关键字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `contentItems` | `Array<DynamicToolCallOutputContentItem>` | 是 | 工具调用输出的内容项数组，每个元素可以是文本或图片类型 |
| `success` | `boolean` | 是 | 指示工具调用是否成功执行 |

#### contentItems 详细说明

`contentItems` 是一个数组，包含零个或多个 `DynamicToolCallOutputContentItem` 对象。每个内容项是一个 tagged union，支持以下类型：

```typescript
export type DynamicToolCallOutputContentItem = 
  | { "type": "inputText", text: string } 
  | { "type": "inputImage", imageUrl: string };
```

- **`inputText`**：纯文本输出，包含 `text` 字段
- **`inputImage`**：图片输出，包含 `imageUrl` 字段（通常是 base64 编码的数据 URL 或远程 URL）

### Rust 端对应实现

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DynamicToolCallResponse {
    pub content_items: Vec<DynamicToolCallOutputContentItem>,
    pub success: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum DynamicToolCallOutputContentItem {
    #[serde(rename_all = "camelCase")]
    InputText { text: String },
    #[serde(rename_all = "camelCase")]
    InputImage { image_url: String },
}
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/DynamicToolCallResponse.ts`
- **TypeScript 依赖**: `codex-rs/app-server-protocol/schema/typescript/v2/DynamicToolCallOutputContentItem.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `DynamicToolCallResponse` 结构体定义（约第 5636-5639 行）
  - `DynamicToolCallOutputContentItem` 枚举定义（约第 5645-5650 行）
- **相关类型**:
  - `DynamicToolCallParams` - 动态工具调用请求参数
  - `DynamicToolCallStatus` - 动态工具调用状态枚举
  - `ThreadItem::DynamicToolCall` - 线程项中的动态工具调用变体

## 依赖与外部交互

### 上游依赖

1. **DynamicToolCallParams**: 客户端发起动态工具调用时使用的请求参数类型
2. **DynamicToolCallStatus**: 表示工具调用的生命周期状态（inProgress/completed/failed）

### 下游消费

1. **ThreadItem**: 在 `ThreadItem::DynamicToolCall` 中使用 `content_items` 和 `success` 字段存储执行结果
2. **App Server 处理逻辑**: 服务器接收动态工具调用请求，执行相应逻辑后构造此响应返回给客户端

### 序列化行为

- 使用 camelCase 命名规范进行 JSON 序列化
- 通过 `ts-rs` 工具从 Rust 代码自动生成 TypeScript 类型定义
- 支持双向转换：Rust 类型 ↔ JSON ↔ TypeScript 类型

## 风险、边界与改进建议

### 潜在风险

1. **空内容数组**: `contentItems` 允许为空数组，但某些消费者可能期望至少有一个内容项。建议在文档中明确空数组的语义
2. **成功状态与内容的矛盾**: `success: true` 时 `contentItems` 为空，或 `success: false` 时有内容，这种不一致可能导致消费者困惑
3. **图片 URL 格式**: `imageUrl` 字段没有格式验证，可能接收无效的 URL 或数据 URL

### 边界情况

1. **大图片处理**: 如果 `imageUrl` 是 base64 编码的大图片，可能导致 JSON 响应体积过大
2. **内容项顺序**: 数组中的内容项顺序对渲染结果可能有影响，但协议层面没有明确顺序语义
3. **类型扩展**: 目前仅支持 text 和 image 两种类型，未来扩展新类型需要版本兼容性处理

### 改进建议

1. **添加错误信息字段**: 当 `success: false` 时，建议添加 `errorMessage` 字段说明失败原因
2. **内容大小限制**: 考虑在协议层面添加内容大小限制或分页机制
3. **内容类型协商**: 允许调用方指定期望的返回内容类型，工具提供方据此返回合适格式的内容
4. **流式响应**: 对于可能产生大量输出的工具，考虑支持流式响应模式
5. **元数据扩展**: 添加可选的 `metadata` 字段，允许工具返回额外的结构化信息
