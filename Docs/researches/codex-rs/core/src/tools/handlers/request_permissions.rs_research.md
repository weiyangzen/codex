# request_permissions.rs 研究文档

## 场景与职责

`request_permissions.rs` 实现了 Codex 的权限请求工具处理器，允许模型在执行需要额外权限的操作前，向用户请求文件系统或网络权限。该工具是 Codex 安全模型的关键组成部分，确保敏感操作需要显式用户授权。

## 功能点目的

### 1. 权限请求工具 (request_permissions)
- **动态权限获取**: 允许模型在运行时请求超出当前沙箱限制的权限
- **用户授权流程**: 向用户展示权限请求，等待用户批准或拒绝
- **权限持久化**: 批准的权限可以应用到当前 turn 或整个 session

### 2. 权限规范化
- **路径规范化**: 使用 `normalize_additional_permissions` 处理路径权限
- **权限验证**: 确保请求至少包含一个有效权限
- **平台适配**: 处理不同平台的权限差异（如 macOS 特定权限）

### 3. 工具描述生成
- **动态描述**: `request_permissions_tool_description()` 生成工具描述
- **上下文感知**: 描述说明权限适用范围（当前 turn 或 session）

## 具体技术实现

### 核心数据结构

```rust
pub struct RequestPermissionsHandler;

// 来自 codex_protocol 的参数类型
pub struct RequestPermissionsArgs {
    pub permissions: RequestPermissionProfile,
}

pub struct RequestPermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
    pub macos: Option<MacosPermissions>,  // macOS 特定
}
```

### 工具描述

```rust
pub(crate) fn request_permissions_tool_description() -> String {
    "Request additional filesystem or network permissions from the user and wait for the client to grant a subset of the requested permission profile. Granted permissions apply automatically to later shell-like commands in the current turn, or for the rest of the session if the client approves them at session scope."
        .to_string()
}
```

### Handler 实现

```rust
#[async_trait]
impl ToolHandler for RequestPermissionsHandler {
    type Output = FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        let ToolInvocation {
            session,
            turn,
            call_id,
            payload,
            ..
        } = invocation;

        // 1. 提取 Function payload
        let arguments = match payload {
            ToolPayload::Function { arguments } => arguments,
            _ => return Err(FunctionCallError::RespondToModel(
                "request_permissions handler received unsupported payload".to_string()
            )),
        };

        // 2. 解析参数（带基础路径）
        let mut args: RequestPermissionsArgs =
            parse_arguments_with_base_path(&arguments, turn.cwd.as_path())?;

        // 3. 规范化权限
        args.permissions = normalize_additional_permissions(args.permissions.into())
            .map(codex_protocol::request_permissions::RequestPermissionProfile::from)
            .map_err(FunctionCallError::RespondToModel)?;

        // 4. 验证至少有一个权限
        if args.permissions.is_empty() {
            return Err(FunctionCallError::RespondToModel(
                "request_permissions requires at least one permission".to_string()
            ));
        }

        // 5. 发送权限请求并等待响应
        let response = session
            .request_permissions(turn.as_ref(), call_id, args)
            .await
            .ok_or_else(|| {
                FunctionCallError::RespondToModel(
                    "request_permissions was cancelled before receiving a response".to_string()
                )
            })?;

        // 6. 序列化响应
        let content = serde_json::to_string(&response).map_err(|err| {
            FunctionCallError::Fatal(format!(
                "failed to serialize request_permissions response: {err}"
            ))
        })?;

        Ok(FunctionToolOutput::from_text(content, Some(true)))
    }
}
```

## 关键代码路径与文件引用

### 本文件位置
`codex-rs/core/src/tools/handlers/request_permissions.rs`

### 依赖模块
```rust
use crate::sandboxing::normalize_additional_permissions;
use crate::tools::handlers::parse_arguments_with_base_path;
use codex_protocol::request_permissions::RequestPermissionsArgs;
```

### 调用路径
1. 模型调用 `request_permissions` 工具，提供需要的权限
2. `RequestPermissionsHandler::handle` 接收调用
3. 解析并规范化权限参数
4. 调用 `session.request_permissions()` 发送请求给用户
5. 用户通过客户端 UI 批准或拒绝权限
6. 返回权限响应给模型

### 相关模块
- `codex_protocol::request_permissions` - 协议定义
- `crate::sandboxing` - 权限规范化实现
- `crate::tools::handlers::parse_arguments_with_base_path` - 参数解析

## 依赖与外部交互

### 外部模块依赖
| 模块 | 用途 |
|-----|------|
| `codex_protocol::request_permissions` | 请求/响应类型定义 |
| `crate::sandboxing` | 权限规范化 |
| `crate::tools::handlers::parse_arguments_with_base_path` | 带基础路径的参数解析 |

### 会话交互
- 调用 `session.request_permissions()` 发送权限请求
- 等待用户响应（可能长时间阻塞）
- 返回的权限自动应用到后续命令

### 权限类型
| 权限类型 | 说明 |
|---------|------|
| `network` | 网络访问权限 |
| `file_system.read` | 文件系统读取权限 |
| `file_system.write` | 文件系统写入权限 |
| `macos` | macOS 特定权限（如辅助功能）|

## 风险、边界与改进建议

### 潜在风险
1. **权限提升攻击**: 如果权限请求描述被篡改，用户可能在不知情的情况下授予危险权限
2. **权限持久化风险**: Session 级别的权限授予可能影响后续所有操作
3. **取消处理**: 用户取消请求时，模型需要正确处理并重试或放弃

### 边界情况
1. **空权限请求**: 已处理，返回错误 "requires at least one permission"
2. **无效路径**: 由 `normalize_additional_permissions` 处理
3. **平台不兼容权限**: 如非 macOS 系统请求 macos 权限
4. **重复请求**: 同一权限多次请求的行为

### 改进建议

1. **增强权限描述**:
   ```rust
   // 添加权限影响说明
   pub(crate) fn request_permissions_tool_description() -> String {
       format!(
           "Request additional permissions...\n\n\
            Requested permissions will be shown to the user with details about \
            what files/directories will be accessible."
       )
   }
   ```

2. **添加权限预览**:
   ```rust
   // 在请求前显示权限影响预览
   let preview = generate_permission_preview(&args.permissions);
   session.send_permission_preview(turn, &preview).await;
   ```

3. **权限请求限制**:
   ```rust
   // 限制权限请求频率，防止滥用
   if session.recent_permission_requests_count() > MAX_REQUESTS_PER_TURN {
       return Err(FunctionCallError::RespondToModel(
           "Too many permission requests in this turn".to_string()
       ));
   }
   ```

4. **添加审计日志**:
   ```rust
   // 记录所有权限请求和授予
   session.audit_log().record_permission_request(&args, &response).await;
   ```

5. **添加配套测试文件**:
   当前没有 `request_permissions_tests.rs`，建议添加测试覆盖：
   - 基本权限请求流程
   - 空权限错误
   - 无效路径处理
   - 取消处理
   - 序列化错误处理

### 安全考虑
- 所有路径应通过 `normalize_additional_permissions` 规范化
- 用户应清楚了解授予的权限范围
- 考虑添加权限自动过期机制（如 30 分钟后失效）
- 敏感操作（如删除系统文件）应需要额外确认

### 缺失功能
- 没有权限撤销机制
- 没有权限使用审计
- 没有权限范围限制（如只读 vs 读写）
