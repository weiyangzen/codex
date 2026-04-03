# CancelLoginAccountStatus.ts 研究文档

## 场景与职责

`CancelLoginAccountStatus.ts` 定义了取消登录操作的状态枚举，用于表示 `account/login/cancel` API 的执行结果。该枚举是 `CancelLoginAccountResponse` 的核心组成部分，提供了简洁的状态反馈机制。

作为账户管理子系统的基础类型，它支持 Codex 多种登录方式的取消操作状态追踪。

## 功能点目的

### 核心功能

1. **操作结果分类**：明确区分成功取消和未找到目标的情况
2. **客户端指导**：帮助客户端决定下一步操作（如是否需要重试）
3. **错误处理简化**：提供标准化的状态码替代复杂的错误类型

### 类型定义

```typescript
export type CancelLoginAccountStatus = "canceled" | "notFound";
```

### 状态值说明

| 值 | 含义 | 场景 |
|----|------|------|
| `canceled` | 成功取消 | 找到了对应的登录请求并成功取消 |
| `notFound` | 未找到 | 登录请求不存在、已过期或已完成 |

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1632-1639)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CancelLoginAccountStatus {
    Canceled,
    NotFound,
}
```

### 序列化规则

- Rust 使用 `PascalCase` 枚举变体命名
- JSON/TypeScript 使用 `camelCase`（通过 `rename_all = "camelCase"` 转换）
- 序列化结果：
  - `Canceled` → `"canceled"`
  - `NotFound` → `"notFound"`

## 关键代码路径与文件引用

### 使用位置

| 文件 | 使用方式 |
|------|----------|
| `CancelLoginAccountResponse.ts` | 作为 `status` 字段的类型 |

### 依赖关系

```
CancelLoginAccountResponse.ts
  └── CancelLoginAccountStatus.ts
```

### API 上下文

```typescript
// 请求
interface CancelLoginAccountParams {
  loginId: string;
}

// 响应
interface CancelLoginAccountResponse {
  status: CancelLoginAccountStatus;  // "canceled" | "notFound"
}
```

## 依赖与外部交互

### 登录流程状态机

```
                    +-----------+
                    |  Created  |
                    +-----+-----+
                          |
                          v
+--------+          +-----+-----+          +-----------+
| Canceled|<---------|  Pending  |--------->| Completed |
+--------+  cancel   +-----------+  success +-----------+
                      |  ^
                      |  |
                      v  |
                   +-----------+
                   |  Expired  |
                   +-----------+
```

### 状态转换说明

| 当前状态 | 操作 | 结果状态 | CancelLoginAccountStatus |
|----------|------|----------|--------------------------|
| Pending | 取消 | Canceled | `canceled` |
| Canceled | 取消 | Canceled | `notFound` |
| Completed | 取消 | Completed | `notFound` |
| Expired | 取消 | Expired | `notFound` |

## 风险、边界与改进建议

### 设计权衡

当前设计采用极简的两个状态值，这是有意为之：

**优点**：
- 简单明了，易于理解和实现
- 减少客户端处理复杂度
- 向后兼容性好

**缺点**：
- 无法区分"已取消"和"已完成"的区别
- 客户端无法判断是否应该重试
- 调试信息不足

### 边界情况

1. **并发取消**：多个客户端同时尝试取消同一登录请求
   - 第一个请求返回 `canceled`
   - 后续请求返回 `notFound`

2. **网络重试**：客户端重试取消请求
   - 第一次：返回 `canceled`
   - 重试：返回 `notFound`（幂等性不严格保持）

3. **过期边界**：请求刚好过期时调用取消
   - 取决于服务器清理时机
   - 可能返回 `canceled` 或 `notFound`

### 改进建议

1. **增加状态值**（向后不兼容）：
   ```typescript
   type CancelLoginAccountStatus = 
     | "canceled"           // 成功取消
     | "notFound"           // 不存在
     | "alreadyCanceled"    // 已被取消
     | "alreadyCompleted"   // 已完成
     | "expired";           // 已过期
   ```

2. **添加元数据**（向后兼容）：
   ```typescript
   interface CancelLoginAccountResponse {
     status: CancelLoginAccountStatus;
     metadata?: {
       originalStatus?: "pending" | "completed" | "expired";
       canceledAt?: string;  // ISO 8601 timestamp
     };
   }
   ```

3. **保持简单**：当前设计对于大部分用例已足够，增加复杂度可能不值得

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定
- 变更类型：如需扩展，建议在 v3 中进行

### 测试建议

1. **单元测试**：
   - 取消待处理的登录请求 → 返回 `canceled`
   - 取消不存在的登录请求 → 返回 `notFound`
   - 取消已完成的登录请求 → 返回 `notFound`

2. **集成测试**：
   - 完整的登录-取消流程
   - 并发取消场景
   - 超时边界测试
