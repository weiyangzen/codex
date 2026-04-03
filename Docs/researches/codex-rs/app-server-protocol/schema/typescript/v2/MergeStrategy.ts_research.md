# MergeStrategy.ts 研究文档

## 场景与职责

`MergeStrategy.ts` 定义了配置合并策略的类型。该类型用于指定在更新配置时如何处理现有值和新值的合并。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **配置更新控制**: 控制配置更新的合并行为
2. **数据一致性**: 确保配置合并符合预期
3. **灵活性**: 支持不同的合并需求场景

## 具体技术实现

### 数据结构

```typescript
export type MergeStrategy = "replace" | "upsert";
```

### 策略说明

| 策略值 | 说明 | 行为 |
|--------|------|------|
| `"replace"` | 替换 | 完全替换现有值 |
| `"upsert"` | 更新或插入 | 更新现有值，如果不存在则插入 |

### 策略对比

| 场景 | replace | upsert |
|------|---------|--------|
| 键已存在 | 替换值 | 更新值 |
| 键不存在 | 添加 | 添加 |
| 数组处理 | 完全替换 | 合并/追加 |
| 嵌套对象 | 完全替换 | 递归合并 |

### 生成来源

该文件由 Rust 枚举通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum MergeStrategy {
    Replace,
    Upsert,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 枚举 |
| `codex-rs/core/src/config/edit.rs` | 配置编辑逻辑 |

### 下游使用（TypeScript 消费者）

- 配置更新 API
- 设置同步逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `ConfigValueWriteParams.ts` | 配置值写入参数 |

## 依赖与外部交互

### 使用场景

1. **配置更新**: 更新用户配置时指定合并策略
2. **插件配置**: 合并插件提供的默认配置
3. **远程同步**: 同步远程配置到本地

## 风险、边界与改进建议

### 改进建议

1. **添加更多策略**:
   ```typescript
   export type MergeStrategy = 
     | "replace"      // 完全替换
     | "upsert"       // 更新或插入
     | "append"       // 追加到数组
     | "prepend"      // 前置到数组
     | "deepMerge";   // 深度合并对象
   ```

2. **添加路径特定策略**:
   ```typescript
   {
     strategy: MergeStrategy;
     pathStrategies?: Record<string, MergeStrategy>;
   }
   ```
