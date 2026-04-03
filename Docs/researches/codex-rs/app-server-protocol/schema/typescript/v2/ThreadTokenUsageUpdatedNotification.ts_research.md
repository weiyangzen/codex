# ThreadTokenUsageUpdatedNotification Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadTokenUsageUpdatedNotification` 是服务器向客户端发送的异步通知，用于实时广播线程 token 使用情况的更新。这是成本透明化和上下文管理的关键机制，使客户端能够及时获知 API 调用的资源消耗。

**核心使用场景：**
1. **实时成本显示**：在 UI 中实时更新显示的 token 使用量和估计成本
2. **上下文窗口监控**：监控当前对话接近模型上下文上限的程度
3. **使用分析**：收集数据用于使用模式分析和优化
4. **预算预警**：当使用量接近预设阈值时触发警告

**职责范围：**
- 广播 token 使用统计的更新
- 标识发生更新的线程和轮次
- 提供完整的 token 使用分解（累计和最近）
- 支持客户端成本计算和显示

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **成本透明化**
   - 让用户实时了解 API 调用的资源消耗
   - 支持按轮次追踪成本

2. **资源管理**
   - 帮助用户管理模型上下文窗口的使用
   - 预警接近上下文上限的情况

3. **数据同步**
   - 确保所有客户端看到一致的 token 使用数据
   - 支持多设备同步使用统计

4. **分析支持**
   - 为使用分析和优化提供原始数据
   - 支持识别高消耗的交互模式

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 3522-3529）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadTokenUsageUpdatedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub token_usage: ThreadTokenUsage,
}
```

**TypeScript 生成类型**（`ThreadTokenUsageUpdatedNotification.ts`）：

```typescript
import type { ThreadTokenUsage } from "./ThreadTokenUsage";

export type ThreadTokenUsageUpdatedNotification = { 
    threadId: string, 
    turnId: string, 
    tokenUsage: ThreadTokenUsage, 
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 发生 token 使用更新的线程唯一标识符 |
| `turnId` | `string` | 产生此次 token 消耗的轮次标识符 |
| `tokenUsage` | `ThreadTokenUsage` | 完整的 token 使用统计信息 |

### ThreadTokenUsage 结构

```typescript
type ThreadTokenUsage = { 
    total: TokenUsageBreakdown,      // 累计使用量
    last: TokenUsageBreakdown,       // 最近一次使用量
    modelContextWindow: number | null, // 模型上下文窗口大小
};

type TokenUsageBreakdown = { 
    totalTokens: number, 
    inputTokens: number, 
    cachedInputTokens: number, 
    outputTokens: number, 
    reasoningOutputTokens: number, 
};
```

### 通知注册

**RPC 协议注册**（`codex-rs/app-server-protocol/src/protocol/common.rs` line 884）：

```rust
server_notification_definitions! {
    // ...
    ThreadTokenUsageUpdated => "thread/tokenUsage/updated" (v2::ThreadTokenUsageUpdatedNotification),
    // ...
}
```

### ServerNotification 枚举

```rust
pub enum ServerNotification {
    // ...
    ThreadTokenUsageUpdated(v2::ThreadTokenUsageUpdatedNotification),
    // ...
}
```

### 序列化示例

```json
{
    "jsonrpc": "2.0",
    "method": "thread/tokenUsage/updated",
    "params": {
        "threadId": "thread-uuid",
        "turnId": "turn-uuid",
        "tokenUsage": {
            "total": {
                "totalTokens": 15000,
                "inputTokens": 10000,
                "cachedInputTokens": 3000,
                "outputTokens": 5000,
                "reasoningOutputTokens": 2000
            },
            "last": {
                "totalTokens": 500,
                "inputTokens": 300,
                "cachedInputTokens": 100,
                "outputTokens": 200,
                "reasoningOutputTokens": 50
            },
            "modelContextWindow": 128000
        }
    }
}
```

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 3522-3529)
  - `ThreadTokenUsageUpdatedNotification` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 3531-3550)
  - `ThreadTokenUsage` 结构体定义

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (line 884)
  - 通知方法注册：`ThreadTokenUsageUpdated => "thread/tokenUsage/updated"`

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadTokenUsageUpdatedNotification.ts`**
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadTokenUsage.ts`**
- **`codex-rs/app-server-protocol/schema/typescript/v2/TokenUsageBreakdown.ts`**

### 服务器实现
- **`codex-rs/app-server/src/bespoke_event_handling.rs`**
  - token 使用事件的收集和通知分发

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
  - TUI 应用接收和显示 token 使用情况

### 文档
- **`codex-rs/app-server/README.md`**
  - API 文档中关于 `thread/tokenUsage/updated` 的说明

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `ThreadTokenUsage` | token 使用统计数据结构 |
| `TokenUsageBreakdown` | token 分类统计 |
| `Thread` | 标识 token 使用所属的线程 |
| `Turn` | 标识产生 token 消耗的轮次 |

### 外部系统交互

1. **模型 API**
   - 从模型响应中提取 usage 信息
   - OpenAI API 在响应中提供 usage 字段

2. **成本计算服务**
   - 结合模型定价计算估计成本
   - 可能需要外部定价数据源

3. **监控和分析系统**
   - 可以将 token 使用数据发送到分析平台
   - 支持使用模式分析和优化建议

### 数据流

```
用户发送消息
    ↓
调用模型 API
    ↓
接收模型响应（包含 usage）
    ↓
更新内部 token 统计
    ↓
构造 ThreadTokenUsageUpdatedNotification
    ↓
广播通知给所有订阅客户端
    ↓
客户端更新 UI 显示
```

### 触发时机

通知通常在以下时机触发：
1. **轮次完成时**：`turn/completed` 后发送最终统计
2. **流式响应中**：可能发送中间更新（取决于实现）
3. **模型切换时**：上下文窗口大小变化时

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **数据准确性**
   - token 计数依赖于模型提供商的准确性
   - 不同提供商的计数方式可能不同

2. **实时性限制**
   - 流式响应中的 token 计数可能不准确
   - 最终统计通常在响应完成后才可用

3. **通知频率**
   - 高频更新可能导致通知风暴
   - 需要适当的节流机制

### 边界情况

1. **零消耗**
   - 某些操作可能不产生 token 消耗（如缓存命中）
   - `last` 字段可能全为零

2. **模型上下文窗口为 null**
   - `modelContextWindow` 当前是可选的
   - 为 null 时客户端无法计算使用率

3. **多模型线程**
   - 线程中使用多个模型时，统计可能混合
   - 需要明确标识每个统计对应的模型

### 改进建议

1. **添加模型标识**
   - 在通知中添加 `model` 字段，标识统计对应的模型
   - 支持多模型线程的分别统计

2. **添加时间戳**
   - 添加 `timestamp` 字段，记录统计产生的时间
   - 便于分析和排序

3. **成本估算**
   - 添加 `estimatedCost` 字段，提供实时成本估算
   - 需要内置或配置模型定价信息

4. **使用率预计算**
   - 添加 `contextWindowUsagePercent` 字段
   - 减少客户端计算负担

5. **节流机制**
   - 对高频更新进行节流
   - 可配置节流间隔

6. **批量通知**
   - 支持多个轮次的统计批量通知
   - 减少网络开销

7. **历史趋势**
   - 支持查询历史 token 使用趋势
   - 添加趋势分析 API

8. **预警集成**
   - 添加上下文窗口使用率预警
   - 支持配置预算上限警告

9. **缓存效率指标**
   - 突出显示缓存命中率
   - 提供优化建议以提高缓存效率
