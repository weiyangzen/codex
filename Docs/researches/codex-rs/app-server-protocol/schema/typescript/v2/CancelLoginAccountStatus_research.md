# CancelLoginAccountStatus.ts 研究文档

## 1. 场景与职责 (Usage Scenarios and Responsibilities)

### 场景
`CancelLoginAccountStatus` 是 Codex App Server Protocol v2 API 中的状态枚举类型，专门用于表示取消登录账户操作的结果状态。它应用于以下场景：

- **OAuth 登录流程中断**：用户在浏览器中完成 OAuth 授权前关闭页面或取消操作
- **登录超时处理**：登录流程超过预定时间，系统自动或手动取消
- **用户主动取消**：用户在客户端界面点击"取消登录"按钮
- **账户切换**：用户决定切换到其他账户，取消当前正在进行的登录
- **错误恢复**：登录流程遇到错误，客户端决定取消并重试

### 职责
- 提供标准化的取消操作结果状态
- 区分"成功取消"和"会话不存在"两种场景
- 作为 `CancelLoginAccountResponse` 的核心状态字段
- 支持客户端根据状态进行相应的 UI 反馈和流程控制

## 2. 功能点目的 (Purpose of the Functionality)

### 核心功能
`CancelLoginAccountStatus` 定义了两种明确的状态值：

1. **`"canceled"`**
   - 表示登录会话已成功取消
   - 服务器已清理相关登录状态
   - 客户端可以安全地放弃该登录流程

2. **`"notFound"`**
   - 表示指定的登录会话不存在
   - 可能原因：会话已过期、ID 错误、或已完成登录
   - 客户端应更新本地状态，避免重复取消

### 设计目标
- **语义明确**：状态值名称直观表达含义
- **二元结果**：简化客户端处理逻辑
- **幂等性支持**：重复取消操作有明确的预期结果
- **向后兼容**：为未来扩展预留空间

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 类型定义
```typescript
export type CancelLoginAccountStatus = "canceled" | "notFound";
```

### 技术特性
1. **字符串字面量联合类型**：使用 TypeScript 联合类型实现枚举效果
2. **camelCase 命名**：遵循 API v2 的命名规范
3. **简洁性**：仅包含必要的状态值，避免过度设计

### Rust 源实现
在 Rust 代码中对应的定义为：

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

### 序列化行为
- Rust 中的 `Canceled` 序列化为 `"canceled"`（camelCase）
- Rust 中的 `NotFound` 序列化为 `"notFound"`（camelCase）
- 使用 `#[serde(rename_all = "camelCase")]` 确保 JSON 输出格式

### 代码生成
- 使用 `ts-rs` crate 从 Rust 枚举自动生成 TypeScript 类型
- 生成文件路径：`codex-rs/app-server-protocol/schema/typescript/v2/CancelLoginAccountStatus.ts`
- 自动应用 camelCase 转换规则

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 源文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 1636-1639) | Rust 源定义 `CancelLoginAccountStatus` 枚举 |

### 生成的 TypeScript 文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/CancelLoginAccountStatus.ts` | 主类型定义文件 |
| `codex-rs/app-server-protocol/schema/typescript/v2/CancelLoginAccountResponse.ts` | 使用该类型的响应结构 |
| `codex-rs/app-server-protocol/schema/typescript/v2/index.ts` | 模块导出索引 |

### JSON Schema
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/CancelLoginAccountResponse.json` | 包含状态枚举定义 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | v2 完整 Schema |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json` | 完整协议 Schema |

### 使用位置
- `CancelLoginAccountResponse.ts`: 作为 `status` 字段的类型
- 服务器端取消登录逻辑中的状态返回

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 被依赖方
- `CancelLoginAccountResponse.ts`: 作为响应类型的核心字段
- `index.ts`: 统一导出模块

### 外部交互
1. **登录取消流程**：
   ```
   1. 客户端调用 account/login/start 启动登录
   2. 服务器返回 LoginAccountResponse（包含 login_id）
   3. 客户端决定取消登录
   4. 客户端调用 account/login/cancel（传入 login_id）
   5. 服务器返回 CancelLoginAccountResponse
      - 成功：status = "canceled"
      - 失败：status = "notFound"
   ```

2. **状态机转换**：
   ```
   [登录启动] -> [等待授权] -> [取消请求] -> ["canceled" 或 "notFound"]
   ```

### API 使用场景
```typescript
// 示例：处理取消登录响应
function handleCancelResponse(status: CancelLoginAccountStatus): void {
  switch (status) {
    case "canceled":
      // 更新 UI：显示"登录已取消"
      showNotification("登录已成功取消");
      clearLoginState();
      break;
    case "notFound":
      // 更新 UI：显示"会话已过期"
      showNotification("登录会话不存在或已过期");
      clearLoginState();
      break;
    default:
      // TypeScript 会在此处进行穷尽检查
      const _exhaustive: never = status;
  }
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **状态歧义**
   - 风险：`"notFound"` 可能由多种原因导致（过期、错误 ID、已完成），客户端难以区分
   - 缓解：在日志中记录详细原因，客户端根据上下文判断

2. **竞态条件**
   - 风险：取消请求和登录完成可能同时发生
   - 当前行为：登录完成后，取消返回 `"notFound"`
   - 风险：客户端可能误判为"会话过期"

3. **扩展限制**
   - 风险：当前仅有两个状态值，可能无法覆盖所有业务场景
   - 缓解：保持简洁设计，通过其他字段补充信息

### 边界情况

1. **重复取消**
   - 第一次取消：`"canceled"`
   - 第二次取消：`"notFound"`（会话已不存在）

2. **无效登录 ID**
   - 使用随机字符串调用取消：`"notFound"`

3. **并发登录**
   - 多个登录流程使用不同 ID，互不影响

4. **时序问题**
   - 取消请求到达时，登录刚好完成：`"notFound"`

### 改进建议

1. **扩展状态枚举**
   ```typescript
   export type CancelLoginAccountStatus = 
     | "canceled" 
     | "notFound"
     | "alreadyCompleted"  // 新增：登录已完成
     | "alreadyCanceled"   // 新增：已取消过
     | "expired";          // 新增：会话已过期
   ```

2. **添加元数据字段**
   ```typescript
   export type CancelLoginAccountResponse = { 
     status: CancelLoginAccountStatus,
     metadata?: {
       reason?: string;           // 详细原因
       session_exists?: boolean;  // 会话是否存在
       completion_time?: string;  // 完成时间（如果已完成）
     }
   };
   ```

3. **保留原始状态**
   ```typescript
   export type CancelLoginAccountStatus = "canceled" | "notFound";
   
   export type CancelLoginAccountResponse = { 
     status: CancelLoginAccountStatus,
     original_status?: "pending" | "completed" | "expired"; // 会话原始状态
   };
   ```

4. **错误码细分**
   ```typescript
   export type CancelLoginAccountStatus = "canceled" | "notFound";
   
   export type CancelLoginAccountErrorCode = 
     | "SESSION_NOT_FOUND"
     | "SESSION_EXPIRED" 
     | "SESSION_COMPLETED"
     | "INVALID_LOGIN_ID";
   ```

5. **向后兼容策略**
   - 新增状态值时，确保旧客户端能正确处理（通过 `default` case）
   - 考虑使用版本控制或特性标志

### 测试建议

1. **单元测试**
   - 测试状态值的序列化/反序列化
   - 验证 camelCase 转换正确性

2. **集成测试**
   - 测试正常取消流程返回 `"canceled"`
   - 测试重复取消返回 `"notFound"`
   - 测试无效 ID 返回 `"notFound"`
   - 测试登录完成后取消返回 `"notFound"`

3. **边界测试**
   - 测试空字符串 ID
   - 测试超长 ID
   - 测试特殊字符 ID

4. **并发测试**
   - 测试多个登录流程同时取消
   - 测试取消和完成的竞态条件
