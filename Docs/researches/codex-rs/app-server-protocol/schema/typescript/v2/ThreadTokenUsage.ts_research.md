# ThreadTokenUsage Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadTokenUsage` 是用于跟踪和报告线程 token 使用情况的统计数据结构。它为客户端提供了详细的 token 消耗信息，帮助用户了解 API 使用成本和模型上下文窗口的利用情况。

**核心使用场景：**
1. **成本监控**：实时显示当前线程的 API 调用成本
2. **上下文管理**：监控模型上下文窗口的使用情况，预警接近上限
3. **使用分析**：分析不同操作类型的 token 消耗模式
4. **预算控制**：帮助用户控制 API 使用预算

**职责范围：**
- 记录累计 token 使用量（total）
- 记录最近一次操作的 token 使用量（last）
- 提供模型上下文窗口大小信息
- 支持细粒度的 token 分类统计（输入、输出、缓存等）

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **成本透明化**
   - 让用户清楚了解每次交互的 API 成本
   - 支持按操作类型分析成本

2. **上下文窗口管理**
   - 监控上下文窗口的使用率
   - 预警接近上下文上限的情况

3. **性能优化**
   - 通过分析 token 使用模式优化提示词
   - 识别高消耗的交互模式

4. **预算管理**
   - 支持用户设置和使用预算跟踪
   - 提供历史使用数据用于预测

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 3531-3550）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadTokenUsage {
    pub total: TokenUsageBreakdown,
    pub last: TokenUsageBreakdown,
    // TODO(aibrahim): make this not optional
    #[ts(type = "number | null")]
    pub model_context_window: Option<i64>,
}

impl From<CoreTokenUsageInfo> for ThreadTokenUsage {
    fn from(value: CoreTokenUsageInfo) -> Self {
        Self {
            total: value.total_token_usage.into(),
            last: value.last_token_usage.into(),
            model_context_window: value.model_context_window,
        }
    }
}
```

**TypeScript 生成类型**（`ThreadTokenUsage.ts`）：

```typescript
import type { TokenUsageBreakdown } from "./TokenUsageBreakdown";

export type ThreadTokenUsage = { 
    total: TokenUsageBreakdown, 
    last: TokenUsageBreakdown, 
    modelContextWindow: number | null, 
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `total` | `TokenUsageBreakdown` | 累计 token 使用量统计 |
| `last` | `TokenUsageBreakdown` | 最近一次操作的 token 使用量 |
| `modelContextWindow` | `number \| null` | 模型上下文窗口大小（TODO：计划改为非可选） |

### TokenUsageBreakdown 结构

**TypeScript 类型**（`TokenUsageBreakdown.ts`）：

```typescript
export type TokenUsageBreakdown = { 
    totalTokens: number, 
    inputTokens: number, 
    cachedInputTokens: number, 
    outputTokens: number, 
    reasoningOutputTokens: number, 
};
```

### 字段说明

| 字段 | 说明 |
|------|------|
| `totalTokens` | 总 token 数 |
| `inputTokens` | 输入 token 数（提示词） |
| `cachedInputTokens` | 缓存的输入 token 数（可节省成本） |
| `outputTokens` | 输出 token 数（模型响应） |
| `reasoningOutputTokens` | 推理过程的输出 token 数（reasoning 模型） |

### 序列化示例

```json
{
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
```

### 从核心类型转换

```rust
impl From<CoreTokenUsageInfo> for ThreadTokenUsage {
    fn from(value: CoreTokenUsageInfo) -> Self {
        Self {
            total: value.total_token_usage.into(),
            last: value.last_token_usage.into(),
            model_context_window: value.model_context_window,
        }
    }
}
```

这表明 `ThreadTokenUsage` 是从内部核心类型 `CoreTokenUsageInfo` 转换而来的协议层类型。

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 3531-3550)
  - `ThreadTokenUsage` 结构体定义
  - `From<CoreTokenUsageInfo>` 转换实现

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadTokenUsage.ts`**
- **`codex-rs/app-server-protocol/schema/typescript/v2/TokenUsageBreakdown.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadTokenUsage.json`**

### 使用场景
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 3522-3529)
  - `ThreadTokenUsageUpdatedNotification` 使用 `ThreadTokenUsage`

### 通知注册
- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (line 884)
  - `ThreadTokenUsageUpdated => "thread/tokenUsage/updated"`

### 服务器实现
- **`codex-rs/app-server/src/bespoke_event_handling.rs`**
  - token 使用事件的收集和通知

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
  - TUI 应用显示 token 使用情况

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `TokenUsageBreakdown` | token 统计的详细分解 |
| `CoreTokenUsageInfo` | 内部核心 token 使用信息 |
| `ThreadTokenUsageUpdatedNotification` | 使用此类型的通知 |

### 外部系统交互

1. **模型 API**
   - 从模型响应中提取 token 使用信息
   - OpenAI API 在响应头中提供 usage 信息

2. **成本计算**
   - 结合模型定价计算 API 调用成本
   - 需要考虑输入/输出的不同定价

3. **缓存机制**
   - `cachedInputTokens` 反映提示词缓存的命中情况
   - 缓存可以显著降低成本

### 数据流

```
模型 API 调用
    ↓
提取 usage 信息
    ↓
更新 CoreTokenUsageInfo
    ↓
转换为 ThreadTokenUsage
    ↓
发送 ThreadTokenUsageUpdatedNotification
    ↓
客户端更新显示
```

### 上下文窗口计算

```typescript
const usage = threadTokenUsage.total.totalTokens;
const window = threadTokenUsage.modelContextWindow;
const usagePercent = window ? (usage / window) * 100 : null;
```

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **可选字段问题**
   - `model_context_window` 当前是 `Option<i64>`
   - 代码中有 TODO 注释计划改为非可选
   - 为 `null` 时客户端无法计算使用率

2. **精度问题**
   - token 计数由模型提供商提供，可能存在不一致
   - 不同模型的计数方式可能不同

3. **实时性**
   - token 使用信息通常在响应完成后才可用
   - 流式响应中的实时 token 计数可能不准确

### 边界情况

1. **零值处理**
   - 新线程的所有计数为 0
   - 需要正确处理除零等边界情况

2. **大数值**
   - 长时间运行的线程可能有非常大的累计值
   - 确保数值类型不会溢出

3. **模型切换**
   - 线程中切换模型时，上下文窗口大小可能变化
   - 累计值可能跨越不同定价的模型

### 改进建议

1. **完成 TODO**
   - 将 `model_context_window` 改为非可选字段
   - 确保所有模型都提供上下文窗口信息

2. **添加更多指标**
   - 添加 `estimatedCost` 字段（结合模型定价）
   - 添加 `contextWindowUsagePercent` 预计算字段
   - 添加 `averageTokensPerMessage` 统计

3. **历史数据**
   - 支持查询历史 token 使用趋势
   - 添加按时间段的聚合统计

4. **预警机制**
   - 添加上下文窗口使用率预警阈值
   - 支持配置预算上限警告

5. **模型特定信息**
   - 添加模型标识符，便于区分不同模型的使用
   - 支持多模型线程的分别统计

6. **成本计算**
   - 内置常见模型的定价信息
   - 提供实时成本估算

7. **缓存效率**
   - 添加缓存命中率指标
   - 帮助用户优化提示词以提高缓存效率

8. **导出功能**
   - 支持导出 token 使用报告
   - 便于成本分析和报销
