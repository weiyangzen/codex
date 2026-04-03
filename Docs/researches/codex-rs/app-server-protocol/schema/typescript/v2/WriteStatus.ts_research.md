# WriteStatus Research

## 场景与职责

`WriteStatus` 是一个简单的枚举类型，用于表示配置写入操作的结果状态。它在配置管理 API 中扮演关键角色，向调用者传达配置写入是否成功，以及是否存在值被覆盖的情况。

**使用场景：**
- 用户通过 API 修改配置（如 `config/write` 或 `config/batchWrite`）
- 配置值被成功写入用户层
- 写入的值被更高优先级的配置层覆盖
- 需要告知客户端配置的实际生效状态

**核心职责：**
1. 指示配置写入操作的基本成功状态
2. 区分"直接生效"和"被覆盖"两种情况
3. 配合 `OverriddenMetadata` 提供详细的覆盖信息

## 功能点目的

该枚举的设计目的是解决配置分层系统中的状态反馈问题：

1. **写入成功确认**：
   - `Ok` 表示配置已成功写入用户层
   - 写入的值当前正在生效

2. **覆盖检测通知**：
   - `OkOverridden` 表示配置已写入，但被更高优先级层覆盖
   - 用户写入的值不会立即生效
   - 需要用户了解实际生效的是另一个值

**设计背景：**
Codex 使用分层配置系统（用户层、项目层、系统层等），当用户写入一个配置值时，如果更高优先级的层已经定义了该值，用户的写入不会立即生效。`WriteStatus` 明确传达这一状态，避免用户困惑。

## 具体技术实现

### 数据结构

```typescript
export type WriteStatus = "ok" | "okOverridden";
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum WriteStatus {
    Ok,
    OkOverridden,
}
```

### 使用上下文

`WriteStatus` 是 `ConfigWriteResponse` 的核心字段：

```rust
pub struct ConfigWriteResponse {
    pub status: WriteStatus,
    pub version: String,
    pub file_path: AbsolutePathBuf,
    pub overridden_metadata: Option<OverriddenMetadata>,
}
```

### 状态判定逻辑

在 `core/src/config/service.rs` 中：

```rust
let overridden = first_overridden_edit(&updated_layers, &effective, &parsed_segments);
let status = overridden
    .as_ref()
    .map(|_| WriteStatus::OkOverridden)
    .unwrap_or(WriteStatus::Ok);
```

判定流程：
1. 写入配置到用户层
2. 重新加载所有配置层
3. 检查实际生效的值是否等于写入的值
4. 如果不相等，说明被覆盖，返回 `OkOverridden`

### 相关类型

**OverriddenMetadata** (当 `status = OkOverridden` 时提供)：
```rust
pub struct OverriddenMetadata {
    pub message: String,                    // 人类可读的覆盖说明
    pub overriding_layer: ConfigLayerMetadata,  // 覆盖发生的层
    pub effective_value: JsonValue,         // 实际生效的值
}
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 756-762)
  - Rust 枚举定义
  - 包含 `#[serde(rename_all = "camelCase")]` 确保 JSON 使用 camelCase

### TypeScript 生成
- `codex-rs/app-server-protocol/schema/typescript/v2/WriteStatus.ts`
  - 生成的 TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/index.ts` (line 333)
  - Barrel export
- `codex-rs/app-server-protocol/schema/typescript/v2/ConfigWriteResponse.ts` (line 6)
  - 作为 `ConfigWriteResponse` 的字段类型导入

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/v2/ConfigWriteResponse.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

### 服务端实现
- `codex-rs/core/src/config/service.rs` (lines 389-393)
  - 状态判定逻辑
  - 导入：`use codex_app_server_protocol::WriteStatus;`

- `codex-rs/app-server/src/config_api.rs` (line 27)
  - API 层导入和使用

### 测试
- `codex-rs/app-server/tests/suite/v2/config_rpc.rs` (line 23)
  - 集成测试导入 `WriteStatus`
  - 验证配置写入响应状态

### 配置编辑
- `codex-rs/core/src/config/edit.rs`
  - 配置编辑逻辑
  - 与 `first_overridden_edit` 函数交互

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `app-server-protocol` | 类型定义和序列化 |
| `core/config/service` | 状态判定和响应构建 |
| `app-server/config_api` | API 层暴露 |

### 序列化特性

- **JSON 表示**: `"ok"` 或 `"okOverridden"`
- **序列化库**: `serde` with `rename_all = "camelCase"`
- **TypeScript 生成**: `ts-rs` crate

### 交互流程

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   Client Request│────▶│   config/write API   │────▶│  Config Service │
│  (write config) │     │                      │     │  (apply edits)  │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
                                                              │
                                                              ▼
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   Client Display│◀────│ ConfigWriteResponse  │◀────│  Check Override │
│  (status + msg) │     │  {status, metadata}  │     │  (WriteStatus)  │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **状态歧义**:
   - `Ok` 只表示写入成功，不保证值会永远生效
   - 后续配置层的变化可能导致值被覆盖
   - 建议：文档中明确说明 `Ok` 仅表示"当前生效"

2. **覆盖信息不足**:
   - 当 `status = OkOverridden` 时，必须检查 `overridden_metadata`
   - 如果客户端忽略 `overridden_metadata`，用户不知道实际生效的值
   - 建议：API 文档强调必须处理覆盖情况

3. **批量写入复杂性**:
   - `ConfigBatchWriteParams` 可能包含多个编辑
   - 某些编辑可能被覆盖，某些可能直接生效
   - 当前设计只返回一个总体状态
   - 建议：考虑为批量操作提供每个编辑的详细状态

### 边界情况

1. **空值处理**:
   - 写入 `null` 或删除配置值时的行为
   - 需要明确这种情况下 `Ok` 和 `OkOverridden` 的判定逻辑

2. **并发写入**:
   - 多个客户端同时写入同一配置键
   - 版本控制机制（`version` 字段）用于检测冲突
   - 但 `WriteStatus` 本身不反映并发冲突

3. **配置验证失败**:
   - 写入的值未通过验证时，不会返回 `WriteStatus`
   - 而是返回错误响应
   - `WriteStatus` 只在成功路径中使用

### 改进建议

1. **增强状态枚举**:
   ```rust
   pub enum WriteStatus {
       Ok,                                    // 写入并生效
       OkOverridden,                          // 写入但被覆盖
       OkPendingRestart,                      // 写入但需重启生效（未来扩展）
   }
   ```

2. **批量操作改进**:
   - 为 `ConfigBatchWriteResponse` 添加每个编辑的独立状态
   - 允许客户端精确了解哪些编辑被覆盖

3. **客户端指导**:
   - 在 API 文档中添加处理 `OkOverridden` 的最佳实践
   - 提供示例代码展示如何向用户展示覆盖信息

4. **覆盖原因说明**:
   - 在 `OverriddenMetadata` 中添加更详细的覆盖原因
   - 如："被项目层 .codex/config.toml 覆盖"

### 测试建议

- 测试 `Ok` 状态的判定（写入值等于生效值）
- 测试 `OkOverridden` 状态的判定（写入值不等于生效值）
- 测试多层覆盖情况（用户层被项目层覆盖，项目层被 CLI 参数覆盖）
- 验证 TypeScript 类型与 Rust 类型的对应关系
- 测试边界情况：写入相同值、写入 null、删除配置键
