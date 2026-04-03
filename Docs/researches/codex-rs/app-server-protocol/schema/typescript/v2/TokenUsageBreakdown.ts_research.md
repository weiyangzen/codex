# TokenUsageBreakdown 类型研究报告

## 场景与职责

`TokenUsageBreakdown` 是一个数据结构，用于详细记录和报告 AI 模型 API 调用的令牌（token）使用情况。它提供了细粒度的 token 消耗统计，帮助用户和开发者理解模型调用的资源消耗模式。

**核心使用场景：**

1. **成本监控**：跟踪 API 调用的 token 消耗，估算使用成本
2. **性能优化**：分析输入/输出 token 比例，优化提示词设计
3. **上下文管理**：监控上下文窗口使用情况，避免超出模型限制
4. **缓存效率分析**：通过 `cachedInputTokens` 评估提示词缓存命中率
5. **推理成本追踪**：通过 `reasoningOutputTokens` 追踪推理模型的思考过程消耗

**典型使用场景：**
```
用户对话 -> 模型调用 -> TokenUsageBreakdown 统计 -> 显示在 UI -> 成本估算
```

## 功能点目的

该类型的设计目的包括：

1. **完整消耗可见性**：提供从输入到输出的全链路 token 使用明细
2. **缓存效果量化**：区分普通输入 token 和缓存命中 token，评估缓存策略效果
3. **推理模型支持**：专门追踪 reasoning 模型的思考过程输出
4. **成本透明度**：让用户清楚了解每次交互的资源消耗
5. **预算管理**：支持设置 token 使用上限和告警

**字段设计意图：**

| 字段 | 目的 |
|------|------|
| `totalTokens` | 总体消耗，快速了解本次调用的规模 |
| `inputTokens` | 输入规模，评估提示词复杂度 |
| `cachedInputTokens` | 缓存命中，评估缓存策略效果 |
| `outputTokens` | 输出规模，评估响应长度 |
| `reasoningOutputTokens` | 推理消耗，评估 reasoning 模型的思考成本 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
export type TokenUsageBreakdown = { 
  totalTokens: number, 
  inputTokens: number, 
  cachedInputTokens: number, 
  outputTokens: number, 
  reasoningOutputTokens: number, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TokenUsageBreakdown {
    #[ts(type = "number")]
    pub total_tokens: i64,
    #[ts(type = "number")]
    pub input_tokens: i64,
    #[ts(type = "number")]
    pub cached_input_tokens: i64,
    #[ts(type = "number")]
    pub output_tokens: i64,
    #[ts(type = "number")]
    pub reasoning_output_tokens: i64,
}
```

### 类型映射

| Rust 类型 | TypeScript 类型 | 说明 |
|-----------|-----------------|------|
| `i64` | `number` | 使用 `#[ts(type = "number")]` 属性映射 |

### 核心转换实现

```rust
impl From<CoreTokenUsage> for TokenUsageBreakdown {
    fn from(value: CoreTokenUsage) -> Self {
        Self {
            total_tokens: value.total_tokens,
            input_tokens: value.input_tokens,
            cached_input_tokens: value.cached_input_tokens,
            output_tokens: value.output_tokens,
            reasoning_output_tokens: value.reasoning_output_tokens,
        }
    }
}
```

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `CoreTokenUsage` | 转换源 | 核心库中的原始 token 使用数据 |
| `ThreadTokenUsage` | 包含 | 聚合了 `total` 和 `last` 两个 `TokenUsageBreakdown` |
| `TokenUsageInfo` | 核心类型 | 内部使用的 token 信息结构 |

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3552-3578) | Rust 结构体定义及转换实现 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TokenUsageBreakdown.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 包含在通知 schema 中 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/core/src/context_manager/history.rs` | `TotalTokenUsageBreakdown` 结构使用 |
| `codex-rs/core/src/context_manager/mod.rs` | 上下文管理器 token 统计 |
| `codex-rs/core/src/compact_remote.rs` | 远程压缩 token 使用 |
| `codex-rs/core/src/codex.rs` | 核心 Codex 实现中的 token 追踪 |
| `codex-rs/tui_app_server/src/app.rs` | TUI 应用中的 token 显示 |
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | 适配器层 token 转换 |

### 数据流路径

```
OpenAI API Response
  -> CoreTokenUsage (codex_protocol)
  -> TokenUsageBreakdown::from() (v2.rs)
  -> ThreadTokenUsage (聚合)
  -> thread/tokenUsageUpdated 通知
  -> 客户端 UI 显示
```

## 依赖与外部交互

### 内部依赖

```
TokenUsageBreakdown
  ├── CoreTokenUsage (from core)
  ├── serde (序列化/反序列化)
  ├── schemars (JSON Schema)
  ├── ts_rs (TypeScript 生成)
  └── ThreadTokenUsage (聚合容器)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| OpenAI API | 数据源 | 从 API 响应中提取 token 使用信息 |
| TUI/CLI | 通知接收 | 通过 `thread/tokenUsageUpdated` 接收更新 |
| ContextManager | 内部使用 | 用于上下文窗口管理和截断决策 |

### 序列化示例

```json
{
  "totalTokens": 1523,
  "inputTokens": 1024,
  "cachedInputTokens": 512,
  "outputTokens": 499,
  "reasoningOutputTokens": 150
}
```

## 风险、边界与改进建议

### 潜在风险

1. **数值溢出**：虽然使用 `i64`，但极端情况下仍可能溢出（理论上 OpenAI API 返回的 token 计数为正数，应使用 `u64`）
2. **缓存统计误差**：`cachedInputTokens` 的统计依赖于 API 返回的准确性
3. **reasoning token 定义变化**：不同 reasoning 模型对 reasoning token 的定义可能不同

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| 首次调用（无缓存） | `cachedInputTokens = 0` |
| 非 reasoning 模型 | `reasoningOutputTokens = 0` |
| 空响应 | 所有字段为 0 |
| 超长对话 | 数值正常累加，需关注是否接近 `i64` 上限 |

### 改进建议

1. **考虑使用 u64**：token 计数应为非负数，考虑将 `i64` 改为 `u64`：
   ```rust
   #[ts(type = "number")]
   pub total_tokens: u64,
   ```

2. **添加验证方法**：实现验证方法确保数据一致性：
   ```rust
   impl TokenUsageBreakdown {
       pub fn is_valid(&self) -> bool {
           self.total_tokens >= 0
               && self.input_tokens >= 0
               && self.cached_input_tokens <= self.input_tokens
               && self.total_tokens >= self.input_tokens + self.output_tokens
       }
   }
   ```

3. **添加派生字段**：考虑添加计算字段：
   ```rust
   pub fn effective_input_tokens(&self) -> i64 {
       self.input_tokens - self.cached_input_tokens
   }
   
   pub fn cache_hit_rate(&self) -> f64 {
       if self.input_tokens == 0 {
           0.0
       } else {
           self.cached_input_tokens as f64 / self.input_tokens as f64
       }
   }
   ```

4. **成本估算扩展**：添加成本相关字段或关联类型：
   ```rust
   pub struct TokenUsageWithCost {
       pub breakdown: TokenUsageBreakdown,
       pub estimated_cost_usd: f64,
   }
   ```

5. **历史聚合支持**：考虑添加时间序列聚合支持，便于长期分析

6. **文档增强**：在 TypeScript 类型上添加 JSDoc，说明各字段含义：
   ```typescript
   export type TokenUsageBreakdown = {
     /** Total tokens consumed in this API call */
     totalTokens: number,
     /** Input/prompt tokens sent to the model */
     inputTokens: number,
     /** Input tokens that were cache hits */
     cachedInputTokens: number,
     /** Output/completion tokens generated by the model */
     outputTokens: number,
     /** Reasoning tokens (for reasoning models like o1) */
     reasoningOutputTokens: number,
   };
   ```

### 性能考虑

- 该结构体较小（5 × 8 bytes = 40 bytes），复制开销低
- 频繁更新的场景（如流式响应）应考虑批量更新策略
- 在 `ContextManager` 中使用时注意内存累积问题
