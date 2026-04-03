# RequestPermissionProfile 研究文档

## 场景与职责

`RequestPermissionProfile` 是 Codex 系统中用于定义和传递权限请求配置的核心类型。它封装了工具执行所需的网络和文件系统权限，主要用于 `request_permissions` 工具的权限申请和审批流程。

**核心职责：**
- 定义权限请求的配置结构
- 支持网络和文件系统权限的独立配置
- 作为权限审批流程中的数据载体

**使用场景：**
- 工具执行前请求额外权限（如网络访问、特定目录写入）
- 权限审批 UI 展示请求的权限详情
- 会话级别的权限持久化和恢复

## 功能点目的

| 字段 | 类型 | 说明 |
|------|------|------|
| `network` | `AdditionalNetworkPermissions \| null` | 额外的网络权限配置 |
| `fileSystem` | `AdditionalFileSystemPermissions \| null` | 额外的文件系统权限配置 |

**设计目的：**
1. **权限隔离**：将网络权限和文件系统权限分离，实现细粒度控制
2. **可选配置**：两个字段均可为 null，支持仅请求某一类权限
3. **扩展性**：通过独立的权限类型定义，便于未来扩展更多权限类别

### 相关权限类型

**AdditionalNetworkPermissions**：
```typescript
export type AdditionalNetworkPermissions = {
  allowDomains?: string[];
  allowAllDomains?: boolean;
};
```

**AdditionalFileSystemPermissions**：
```typescript
export type AdditionalFileSystemPermissions = {
  allowPaths?: string[];
  allowAllPaths?: boolean;
};
```

## 具体技术实现

### TypeScript 定义
```typescript
import type { AdditionalFileSystemPermissions } from "./AdditionalFileSystemPermissions";
import type { AdditionalNetworkPermissions } from "./AdditionalNetworkPermissions";

export type RequestPermissionProfile = { 
  network: AdditionalNetworkPermissions | null, 
  fileSystem: AdditionalFileSystemPermissions | null 
};
```

### Rust 源码定义
位于 `codex-rs/protocol/src/request_permissions.rs`：

```rust
#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(deny_unknown_fields)]
pub struct RequestPermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
}

impl RequestPermissionProfile {
    pub fn is_empty(&self) -> bool {
        self.network.is_none() && self.file_system.is_none()
    }
}
```

### 转换实现
```rust
impl From<RequestPermissionProfile> for PermissionProfile {
    fn from(value: RequestPermissionProfile) -> Self {
        Self {
            network: value.network,
            file_system: value.file_system,
            macos: None,
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
| 文件 | 说明 |
|------|------|
| `codex-rs/protocol/src/request_permissions.rs` | Rust 结构体定义（核心协议层） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议层引用 |
| `codex-rs/app-server-protocol/schema/typescript/v2/RequestPermissionProfile.ts` | 生成的 TypeScript 类型 |

### 使用位置
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/tools/handlers/request_permissions.rs` | 权限请求工具处理器 |
| `codex-rs/core/tests/suite/request_permissions_tool.rs` | 权限工具测试 |
| `codex-rs/core/src/codex.rs` | Codex 核心逻辑 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs` | TUI 审批覆盖层 UI |
| `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs` | TUI App Server 审批 UI |

### 事件定义
```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct RequestPermissionsEvent {
    pub call_id: String,
    pub turn_id: String,
    pub reason: Option<String>,
    pub permissions: RequestPermissionProfile,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct RequestPermissionsResponse {
    pub permissions: RequestPermissionProfile,
    pub scope: PermissionGrantScope,
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::models::FileSystemPermissions`：文件系统权限定义
- `codex_protocol::models::NetworkPermissions`：网络权限定义
- `codex_protocol::models::PermissionProfile`：完整权限配置（包含 macOS 权限）

### 权限范围
```rust
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum PermissionGrantScope {
    #[default]
    Turn,    // 仅当前回合有效
    Session, // 整个会话有效
}
```

### 外部交互流程
1. **工具调用**：`request_permissions` 工具被调用，传入 `RequestPermissionsArgs`
2. **事件生成**：生成 `RequestPermissionsEvent` 发送给客户端
3. **用户审批**：客户端展示权限请求，用户选择批准或拒绝
4. **响应返回**：客户端发送 `RequestPermissionsResponse` 回服务器
5. **权限应用**：服务器根据响应更新当前执行上下文的权限

## 风险、边界与改进建议

### 潜在风险
1. **权限提升攻击**：恶意工具可能请求过度权限，用户可能未仔细审查就批准
2. **权限持久化风险**：Session 级别的权限可能在用户不知情的情况下长期有效
3. **权限继承混乱**：子进程或派生工具可能继承不适当的权限

### 边界情况
1. **空权限请求**：`is_empty()` 返回 true 时应拒绝请求或给出警告
2. **重复权限请求**：同一回合内多次请求相同权限应去重或合并
3. **权限撤销**：当前实现主要关注权限授予，权限撤销机制不完善

### 改进建议
1. **权限模板**：提供常用权限组合模板（如"仅读取当前目录"、"允许访问 GitHub API"）
2. **权限审计日志**：记录所有权限请求和授权决策，便于安全审计
3. **自动过期**：Session 级别权限支持设置过期时间
4. **权限可视化**：在 UI 中更直观地展示权限影响范围
5. **智能推荐**：根据工具历史行为推荐合适的权限配置
6. **权限沙箱**：实现更细粒度的权限沙箱，限制权限的实际影响范围

### 安全配置建议
```toml
# config.toml 中可配置权限相关设置
[permissions]
approval_policy = "on-request"  # 或 "never", "unless-trusted"
```
