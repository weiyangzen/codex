# DeprecationNoticeNotification.ts 研究文档

## 场景与职责

`DeprecationNoticeNotification.ts` 定义了弃用通知类型，用于向客户端通知某些功能、API 或行为已被弃用。这是 Codex 的 API 演进和向后兼容性策略的重要组成部分，帮助开发者及时了解需要迁移的功能。

该通知在连接建立、功能使用时或定期检查时发送，提醒客户端开发者关注即将移除的功能。

## 功能点目的

1. **弃用提醒**: 告知客户端某些功能已被弃用
2. **迁移指导**: 提供迁移建议和替代方案
3. **兼容性管理**: 帮助客户端平滑过渡到新 API

## 具体技术实现

### 数据结构定义

```typescript
export type DeprecationNoticeNotification = { 
  /**
   * Concise summary of what is deprecated.
   */
  summary: string, 
  /**
   * Optional extra guidance, such as migration steps or rationale.
   */
  details: string | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `summary` | `string` | 弃用内容的简洁摘要，如 `"ContextCompactedNotification is deprecated"` |
| `details` | `string \| null` | 可选的详细指导，包括迁移步骤、弃用原因等 |

### 使用示例

```typescript
// 处理弃用通知
socket.on('deprecationNotice', (notice: DeprecationNoticeNotification) => {
  console.warn(`[DEPRECATED] ${notice.summary}`);
  if (notice.details) {
    console.info(`Migration guide: ${notice.details}`);
  }
});
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DeprecationNoticeNotification {
    /// Concise summary of what is deprecated.
    pub summary: String,
    /// Optional extra guidance, such as migration steps or rationale.
    pub details: Option<String>,
}
```

### 通知发送

**文件**: `codex-rs/app-server/src/bespoke_event_handling.rs`

处理弃用通知的发送逻辑，在以下场景触发：
- 客户端使用已弃用的 API 方法
- 连接建立时的批量通知
- 服务器配置中的弃用功能启用

### 服务器通知枚举

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
pub enum ServerNotification {
    // ...
    DeprecationNotice(DeprecationNoticeNotification),
    // ...
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **TUI 客户端**: 在日志中显示弃用警告
- **VS Code 扩展**: 在输出面板显示弃用信息
- **第三方客户端**: 根据弃用通知调整实现

## 风险、边界与改进建议

### 已知风险

1. **通知泛滥**: 频繁发送可能导致客户端忽略
2. **信息不足**: 摘要可能过于简短，缺乏具体迁移步骤
3. **时序问题**: 通知可能在客户端已经迁移后仍然发送

### 边界情况

1. **空详情**: `details` 为 `null` 时，客户端需要自行查找迁移文档
2. **多语言**: 通知文本为英文，可能需要本地化
3. **版本关联**: 未包含版本信息，难以判断弃用的紧急程度

### 改进建议

1. **分级弃用**: 增加弃用级别（如 `warning`、`critical`）
2. **版本信息**: 增加计划移除的版本号
3. **文档链接**: 提供官方迁移文档的 URL
4. **代码示例**: 在详情中提供新旧 API 的对比示例
5. **批量通知**: 支持一次通知多个弃用项
6. **静默期**: 允许客户端设置静默期，避免重复通知

### 示例改进

```typescript
// 改进后的结构
export type DeprecationNoticeNotification = { 
  level: 'warning' | 'critical',
  summary: string, 
  details: string | null,
  deprecatedSince: string,  // 版本号
  removalVersion: string | null,  // 计划移除版本
  documentationUrl: string | null,
  migrationCodeExample: {
    old: string,
    new: string,
  } | null,
};
```
