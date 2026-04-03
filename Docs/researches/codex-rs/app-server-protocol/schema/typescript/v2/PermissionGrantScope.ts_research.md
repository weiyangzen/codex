# PermissionGrantScope.ts 研究文档

## 场景与职责

`PermissionGrantScope` 是一个简单的字符串枚举类型，用于定义**权限授予的范围**。在 Codex 系统中，当用户批准某项权限请求时，需要明确该权限是仅对当前操作（turn）有效，还是对整个会话（session）持续有效。

**典型使用场景：**
- AI 请求额外的文件系统或网络权限
- 用户审批界面展示权限授予选项
- 系统根据用户选择缓存或清理权限
- 安全审计追踪权限来源

**范围对比：**
| 范围 | 持续时间 | 使用场景 |
|------|----------|----------|
| "turn" | 单次操作 | 临时性、高风险操作 |
| "session" | 整个会话 | 重复性、可信操作 |

## 功能点目的

该枚举定义了两种权限授予范围：

1. **"turn"**: 单次操作范围
   - 权限仅在当前 turn 有效
   - turn 结束后权限自动失效
   - 适用于一次性、高风险的权限请求
   - 提供最小权限原则的安全保障

2. **"session"**: 会话范围
   - 权限在整个用户会话期间保持有效
   - 适用于需要多次执行的相似操作
   - 减少重复权限请求，提升用户体验
   - 会话结束时权限清理

## 具体技术实现

### TypeScript 定义
```typescript
export type PermissionGrantScope = "turn" | "session";
```

### Rust 源码定义
```rust
v2_enum_from_core!(
    #[derive(Default)]
    pub enum PermissionGrantScope from CorePermissionGrantScope {
        #[default]
        Turn,
        Session
    }
);
```

### 宏展开后的实际定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum PermissionGrantScope {
    #[default]
    Turn,
    Session,
}

impl PermissionGrantScope {
    pub fn to_core(self) -> CorePermissionGrantScope {
        match self {
            PermissionGrantScope::Turn => CorePermissionGrantScope::Turn,
            PermissionGrantScope::Session => CorePermissionGrantScope::Session,
        }
    }
}

impl From<CorePermissionGrantScope> for PermissionGrantScope {
    fn from(value: CorePermissionGrantScope) -> Self {
        match value {
            CorePermissionGrantScope::Turn => PermissionGrantScope::Turn,
            CorePermissionGrantScope::Session => PermissionGrantScope::Session,
        }
    }
}
```

### 序列化规则
- 使用 `camelCase` 命名规范
- TypeScript 中使用字符串字面量类型
- Rust 默认值为 `Turn`（更安全的选择）

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 5615-5621)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PermissionGrantScope.ts`

### Core 协议定义
- **位置**: `codex-rs/protocol/src/request_permissions.rs`
- **定义**:
  ```rust
  #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
  pub enum PermissionGrantScope {
      Turn,
      Session,
  }
  ```

### 使用位置

1. **PermissionsRequestApprovalResponse** (v2.rs 行 5627-5631)
   ```rust
   pub struct PermissionsRequestApprovalResponse {
       pub permissions: GrantedPermissionProfile,
       #[serde(default)]
       pub scope: PermissionGrantScope,
   }
   ```

2. **bespoke_event_handling.rs** (app-server)
   - 行 831: `scope: CorePermissionGrantScope::Turn`
   - 行 2380, 2387: 默认使用 Turn 范围
   - 行 3054, 3075: 根据用户选择设置范围

### 使用示例
```rust
// 创建响应时指定范围
let response = PermissionsRequestApprovalResponse {
    permissions: GrantedPermissionProfile { ... },
    scope: PermissionGrantScope::Session,  // 或 Turn
};

// 默认值使用
let response = PermissionsRequestApprovalResponse {
    permissions: GrantedPermissionProfile { ... },
    scope: PermissionGrantScope::default(),  // Turn
};
```

## 依赖与外部交互

### 内部依赖
| 依赖项 | 说明 |
|--------|------|
| `CorePermissionGrantScope` | 核心协议中的权限范围枚举 |
| `v2_enum_from_core!` | 宏，用于从 Core 类型生成 v2 枚举 |
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 外部交互

1. **权限审批流程**
   ```
   AI 请求权限 -> Server 发送 PermissionsRequestApproval -> Client 展示审批 UI
   -> 用户选择范围 (turn/session) -> Client 发送 PermissionsRequestApprovalResponse
   -> Server 根据 scope 缓存权限
   ```

2. **权限缓存管理**
   - `turn` 范围：权限仅存储在当前 turn 的上下文中
   - `session` 范围：权限存储在会话级别的缓存中

3. **安全审计**
   - 记录权限授予的范围，用于后续审计
   - 区分临时权限和持久权限

### 流程图
```
+-------------+     +------------------+     +------------------+
| Permission  |     |  User Approval   |     |  PermissionCache |
|   Request   | --> |   (turn/session) | --> |   (scoped)       |
+-------------+     +------------------+     +------------------+
                                                        |
                       +--------------------------------+
                       |
         +-------------+-------------+
         |                           |
         v                           v
+------------------+      +------------------+
|   Turn Cache     |      |  Session Cache   |
| (turn-scoped)    |      | (session-scoped) |
+------------------+      +------------------+
```

## 风险、边界与改进建议

### 潜在风险

1. **默认范围安全性**
   - 默认值为 `Turn`，这是安全的设计
   - 但如果客户端错误地默认使用 `Session`，可能导致权限过度授予
   - **建议**: 在服务端验证默认行为

2. **范围理解不一致**
   - 用户可能不理解 "turn" 和 "session" 的区别
   - 可能导致用户做出不恰当的选择
   - **建议**: UI 中提供清晰的解释和示例

3. **会话边界模糊**
   - "session" 的定义可能因客户端而异
   - 是应用生命周期？还是连接持续时间？
   - **建议**: 明确文档化 session 的定义

### 边界情况

1. **长时间运行的 Turn**
   - 如果 turn 持续很长时间，`turn` 范围的权限实际上持久存在
   - 可能违背最小权限原则

2. **会话恢复**
   - 会话恢复后，`session` 范围的权限是否应该保留？
   - 当前实现可能需要重新授权

3. **嵌套权限请求**
   - 在一个已授予 `session` 权限的上下文中，再次请求权限
   - 如何处理范围冲突？

4. **权限降级**
   - 用户先授予 `session` 权限，之后想改为 `turn`
   - 当前设计不支持动态调整

### 改进建议

1. **添加更多范围选项**
   ```rust
   pub enum PermissionGrantScope {
       Turn,           // 单次操作
       Session,        // 当前会话
       Workspace,      // 当前工作区（新增）
       Permanent,      // 永久有效（需要额外确认）
   }
   ```

2. **添加时间限制**
   ```rust
   pub struct PermissionGrant {
       pub scope: PermissionGrantScope,
       pub expires_at: Option<DateTime<Utc>>,  // 可选过期时间
   }
   ```

3. **权限撤销支持**
   ```rust
   pub enum PermissionGrantScope {
       // ... 现有变体
   }
   
   // 新增 API
   pub struct PermissionRevokeParams {
       pub permission_id: String,
   }
   ```

4. **范围继承可视化**
   - 在 UI 中展示当前有效的权限及其范围
   - 帮助用户理解和管理已授予的权限

5. **智能默认范围**
   ```rust
   impl PermissionGrantScope {
       pub fn suggested_for(permission: &PermissionProfile) -> Self {
           // 根据权限类型建议默认范围
           // 高风险操作 -> Turn
           // 低风险常用操作 -> Session
       }
   }
   ```

6. **范围变更通知**
   - 当 `session` 范围权限即将过期时通知用户
   - 提供续期或撤销选项
