# ServiceTier.ts 研究文档

## 1. 场景与职责

ServiceTier 类型在 Codex 系统中用于指定 OpenAI API 的服务层级。它在以下场景中发挥作用：

- **模型调用优先级**: 控制模型调用的处理优先级和响应时间
- **成本优化**: 允许用户在速度和成本之间做出权衡
- **流量管理**: 帮助 OpenAI 管理 API 流量和资源分配

## 2. 功能点目的

ServiceTier 提供两个服务层级选项：

1. **Fast**: 高优先级处理，更快的响应时间，通常成本更高
2. **Flex**: 灵活处理，可能有延迟但成本更低

这个类型直接映射到 OpenAI API 的 `service_tier` 参数，用于控制请求的服务质量。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ServiceTier = "fast" | "flex";
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` (lines 248-254):

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum ServiceTier {
    Fast,
    Flex,
}
```

### 关键特性

1. **简单枚举**: 只有两个变体，设计简洁明确
2. **小写序列化**: 使用 `"fast"` 和 `"flex"` 小写字符串与 OpenAI API 兼容
3. **Copy trait**: 实现 Copy，可以低成本传递
4. **Display trait**: 支持格式化为字符串

### 使用场景

在 `UserTurn` 操作中 (protocol.rs lines 274-280):

```rust
pub struct UserTurn {
    // ...
    /// Optional service tier override for this turn.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    service_tier: Option<Option<ServiceTier>>,
    // ...
}
```

使用 `Option<Option<ServiceTier>>` 的设计：
- `None`: 保持现有会话设置
- `Some(None)`: 明确清除层级设置
- `Some(Some(tier))`: 设置特定层级

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | ServiceTier 定义 (lines 248-254) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` | UserTurn 中的使用 (lines 274-280) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/openai_models.rs` | ModelInfo 中的支持信息 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ServiceTier.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成
- **strum**: Display trait 派生

### 外部交互

- **OpenAI API**: 直接映射到 OpenAI API 的 service_tier 参数
- **模型配置**: 在 ModelInfo 中可能包含服务层级支持信息
- **用户配置**: 用户可以通过配置文件设置默认服务层级

## 6. 风险、边界与改进建议

### 风险

1. **API 变更**: OpenAI 可能添加新的服务层级，需要同步更新
2. **模型支持**: 不是所有模型都支持所有服务层级
3. **成本意识**: 用户可能不了解不同层级的成本差异

### 边界情况

1. **无效值**: 从旧数据或不兼容系统反序列化时可能遇到无效值
2. **默认行为**: 未指定服务层级时的默认行为可能因模型而异
3. **动态变更**: 会话进行中变更服务层级的行为

### 改进建议

1. **模型兼容性检查**: 在设置服务层级前检查模型支持情况
2. **成本提示**: 在 UI 中显示不同层级的预估成本
3. **自动选择**: 基于任务类型自动推荐服务层级
4. **降级策略**: 当 Fast 层级不可用时自动降级到 Flex
5. **性能指标**: 收集和展示不同层级的实际响应时间
6. **批量操作优化**: 批量请求时建议使用 Flex 层级节省成本
