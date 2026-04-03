# OverriddenMetadata.ts 研究文档

## 场景与职责

`OverriddenMetadata` 类型用于描述配置写入操作中的**配置覆盖元数据**。当用户尝试写入某个配置值时，如果该值在更高优先级的配置层（如系统层、MDM层）已被设置，则写入操作会被覆盖，此时需要通过该类型向用户展示覆盖的详细信息。

**典型使用场景：**
- 用户通过 `config/value/write` 或 `config/batchWrite` API 修改配置
- 配置系统检测到目标键在更高优先级层已存在值
- 向用户返回 `WriteStatus::OkOverridden` 状态，并附带 `OverriddenMetadata` 说明覆盖详情

## 功能点目的

该类型的核心目的是提供**透明度和可追溯性**：

1. **message**: 向用户展示可读的覆盖说明信息，解释为什么写入被覆盖
2. **overridingLayer**: 标识哪个配置层（`ConfigLayerMetadata`）的设置在起实际作用
3. **effectiveValue**: 展示实际生效的配置值（JSON格式），让用户知道当前实际使用的值是什么

通过这三个字段，用户可以清楚地了解：
- 写入操作是否成功
- 为什么写入的值没有生效
- 哪个层级的配置在控制该设置
- 实际生效的值是什么

## 具体技术实现

### TypeScript 定义
```typescript
export type OverriddenMetadata = { 
  message: string, 
  overridingLayer: ConfigLayerMetadata, 
  effectiveValue: JsonValue 
};
```

### Rust 源码定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct OverriddenMetadata {
    pub message: String,
    pub overriding_layer: ConfigLayerMetadata,
    pub effective_value: JsonValue,
}
```

### 序列化规则
- 使用 `camelCase` 命名规范进行序列化
- `effective_value` 使用 `serde_json::Value` 类型，支持任意 JSON 值
- 通过 `ts-rs` 宏自动生成 TypeScript 类型定义

### 使用流程
1. 用户发起配置写入请求（`ConfigValueWriteParams` 或 `ConfigBatchWriteParams`）
2. 配置系统检查目标键的现有层级
3. 如果存在更高优先级的层已设置该键：
   - 返回 `WriteStatus::OkOverridden`
   - 构造 `OverriddenMetadata` 包含覆盖信息
4. 客户端接收 `ConfigWriteResponse`，检查 `overridden_metadata` 字段

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 767-771)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/OverriddenMetadata.ts`

### 相关类型
- `ConfigWriteResponse`: 包含 `overridden_metadata: Option<OverriddenMetadata>` 字段
- `WriteStatus`: 枚举类型，`OkOverridden` 变体表示配置被覆盖
- `ConfigLayerMetadata`: 描述配置层的元数据（名称、版本等）
- `ConfigLayerSource`: 配置层来源枚举（MDM、System、User、Project 等）

### 使用位置
- `ConfigWriteResponse` 结构体（v2.rs 行 776-782）
- 配置写入 API 的响应处理逻辑

### 配置层优先级（从高到低）
```rust
ConfigLayerSource::Mdm { .. } => 0,                           // 最高优先级
ConfigLayerSource::System { .. } => 10,
ConfigLayerSource::User { .. } => 20,
ConfigLayerSource::Project { .. } => 25,
ConfigLayerSource::SessionFlags => 30,
ConfigLayerSource::LegacyManagedConfigTomlFromFile { .. } => 40,
ConfigLayerSource::LegacyManagedConfigTomlFromMdm => 50,      // 最低优先级
```

## 依赖与外部交互

### 内部依赖
| 依赖项 | 说明 |
|--------|------|
| `ConfigLayerMetadata` | 描述覆盖层的元数据信息 |
| `serde_json::Value` | 用于表示任意 JSON 类型的生效值 |
| `schemars::JsonSchema` | 生成 JSON Schema 用于 API 文档 |
| `ts_rs::TS` | 生成 TypeScript 类型定义 |

### 外部交互
- **客户端**: 接收 `ConfigWriteResponse` 后，根据 `overridden_metadata` 的存在与否，向用户展示覆盖警告
- **配置系统**: 在写入配置时检测层级冲突并构造此类型

### API 交互流程
```
Client -> ConfigValueWrite/ConfigBatchWrite -> Server
Server -> 检测层级冲突 -> 构造 OverriddenMetadata
Server -> ConfigWriteResponse(overridden_metadata) -> Client
Client -> 展示覆盖警告给用户
```

## 风险、边界与改进建议

### 潜在风险

1. **信息泄露风险**
   - `effectiveValue` 可能包含敏感配置信息
   - 建议：确保只有授权用户才能看到覆盖的详细值

2. **用户体验问题**
   - 频繁的配置覆盖可能导致用户困惑
   - 建议：提供清晰的 UI 引导，帮助用户理解配置层级概念

3. **版本兼容性问题**
   - 如果 `ConfigLayerMetadata` 结构变更，可能影响序列化
   - 建议：保持向后兼容或使用版本控制

### 边界情况

1. **空值处理**
   - `effectiveValue` 可能为 `null` 或缺失
   - 客户端应做好空值检查

2. **多层覆盖**
   - 当前只返回最高优先级层的覆盖信息
   - 如果有多个层都设置了该键，中间层的信息会丢失

3. **并发写入**
   - 多个客户端同时写入同一配置键时，覆盖检测可能存在竞态条件

### 改进建议

1. **增强覆盖信息**
   ```rust
   // 建议添加：显示所有冲突的层级
   pub conflicting_layers: Vec<ConfigLayerMetadata>,
   ```

2. **提供解决建议**
   ```rust
   // 建议添加：向用户展示如何解决覆盖问题
   pub suggestion: Option<String>,
   ```

3. **支持强制写入**
   - 添加 `force` 选项允许用户强制写入到指定层，即使更高层有设置

4. **审计日志**
   - 记录所有配置覆盖事件，便于后续审计和故障排查

5. **UI 优化**
   - 在客户端提供配置层级可视化工具
   - 帮助用户直观理解配置继承和覆盖关系
