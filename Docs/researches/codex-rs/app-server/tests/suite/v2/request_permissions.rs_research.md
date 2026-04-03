# request_permissions.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**权限请求工具** (`request_permissions`) 的完整流程。该工具允许 AI 在执行需要额外权限的操作前，向用户请求临时或持久的权限授权。

测试场景覆盖：
1. **权限请求完整流程** - 从 AI 发起请求到用户授权/拒绝的端到端测试
2. **权限范围控制** - 验证不同授权范围 (Turn/Session) 的行为
3. **服务器请求响应机制** - 测试客户端与服务器之间的请求-响应交互

## 功能点目的

### 1. 权限请求工作流
当 AI 需要访问受限资源（如写入文件系统、网络访问）时：
1. AI 调用 `request_permissions` 工具
2. 服务器向客户端发送 `PermissionsRequestApproval` 服务器请求
3. 客户端展示权限请求 UI 给用户
4. 用户授权后，客户端发送响应
5. 服务器继续执行原操作

### 2. 权限数据结构
- **文件系统权限**: 读写路径列表
- **网络权限**: 允许/拒绝的主机列表
- **授权范围**: 
  - `Turn`: 仅当前回合有效
  - `Session`: 整个会话有效

### 3. 服务器请求解析
测试验证了服务器请求的正确序列化和反序列化：
- `ServerRequest::PermissionsRequestApproval` 的解析
- `PermissionsRequestApprovalResponse` 的构造
- `ServerRequestResolvedNotification` 的接收

## 具体技术实现

### 关键流程

```
测试用例: request_permissions_round_trip
1. 创建 mock Responses API 服务器
   - 配置返回 request_permissions 工具调用
   - 配置返回最终助手消息
2. 初始化 MCP 连接
3. 启动线程 (thread/start)
4. 开始回合 (turn/start) 触发 AI 响应
5. 接收 ServerRequest::PermissionsRequestApproval
6. 验证请求参数 (thread_id, turn_id, item_id, permissions)
7. 发送授权响应 (PermissionsRequestApprovalResponse)
8. 等待 serverRequest/resolved 通知
9. 等待 turn/completed 通知
```

### 核心数据结构

```rust
// AI 发起的权限请求参数
request_permissions 工具参数:
{
    "reason": "Select a workspace root",
    "permissions": {
        "file_system": {
            "write": [".", "../shared"]
        }
    }
}

// 服务器请求
ServerRequest::PermissionsRequestApproval {
    request_id: String,
    params: PermissionsRequestApprovalParams {
        thread_id: String,
        turn_id: String,
        item_id: String,
        reason: Option<String>,
        permissions: RequestPermissionProfile {
            network: Option<AdditionalNetworkPermissions>,
            file_system: Option<AdditionalFileSystemPermissions>,
        },
    },
}

// 客户端响应
PermissionsRequestApprovalResponse {
    permissions: GrantedPermissionProfile {
        network: Option<AdditionalNetworkPermissions>,
        file_system: Option<AdditionalFileSystemPermissions>,
    },
    scope: PermissionGrantScope,  // Turn 或 Session
}
```

### 权限范围

| 范围 | 说明 | 使用场景 |
|-----|------|---------|
| `Turn` | 仅当前回合有效 | 一次性操作授权 |
| `Session` | 整个会话有效 | 持久化授权偏好 |

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/request_permissions.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `read_stream_until_request_message()` - 读取服务器请求
  - `send_response()` - 发送客户端响应

- `codex-rs/app-server/tests/common/responses.rs`
  - `create_request_permissions_sse_response()` - 构造权限请求 SSE 响应
  - `create_final_assistant_message_sse_response()` - 构造最终消息 SSE 响应

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `PermissionsRequestApproval => "permissions/requestApproval"` (服务器请求)
  - `ServerRequestResolved => "serverRequest/resolved"` (通知)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `PermissionsRequestApprovalParams`
  - `PermissionsRequestApprovalResponse`
  - `GrantedPermissionProfile`
  - `PermissionGrantScope` (Turn/Session)
  - `AdditionalFileSystemPermissions`
  - `AdditionalNetworkPermissions`

### 核心实现
- `codex-rs/core/src/tools/request_permissions.rs` - 权限请求工具实现
- `codex-rs/app-server/src/codex_message_processor.rs` - 服务器请求处理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `app_test_support` | 测试辅助函数 |
| `tokio::time::timeout` | 异步超时控制 |
| `serde_json` | JSON 序列化 |

### SSE 响应构造
```rust
pub fn create_request_permissions_sse_response(call_id: &str) -> anyhow::Result<String> {
    let tool_call_arguments = serde_json::to_string(&json!({
        "reason": "Select a workspace root",
        "permissions": {
            "file_system": {
                "write": [".", "../shared"]
            }
        }
    }))?;
    
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "request_permissions", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

### 配置要求
```toml
approval_policy = "untrusted"  # 需要权限审批

[features]
request_permissions_tool = true  # 启用权限请求工具
```

## 风险、边界与改进建议

### 当前风险

1. **测试范围有限**
   - 仅测试了文件系统写入权限
   - 未测试网络权限、macOS 权限等
   - 建议: 扩展权限类型覆盖

2. **Session 范围未测试**
   - 仅测试了 `PermissionGrantScope::Turn`
   - 未验证 `Session` 范围的持久化行为
   - 建议: 添加 Session 范围测试

3. **拒绝场景未覆盖**
   - 仅测试了授权流程，未测试拒绝流程
   - 建议: 添加权限拒绝测试用例

### 边界情况

1. **空权限请求**
   - 未测试 AI 请求空权限集的行为
   - 建议: 添加边界测试

2. **无效路径**
   - 未测试包含无效/恶意路径的权限请求
   - 建议: 添加路径验证测试

3. **并发权限请求**
   - 未测试同一回合多个权限请求
   - 建议: 添加并发场景

4. **超时处理**
   - 未测试用户长时间不响应的超时行为
   - 建议: 添加超时测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn request_permissions_session_scope()  // Session 范围
   - async fn request_permissions_denied()  // 拒绝场景
   - async fn request_permissions_network()  // 网络权限
   - async fn request_permissions_timeout()  // 超时处理
   - async fn request_permissions_multiple()  // 并发请求
   ```

2. **安全测试**
   - 测试路径遍历攻击防护
   - 测试权限升级防护

3. **UI 集成测试**
   - 验证权限请求在客户端 UI 的正确展示
   - 测试复杂权限结构的渲染

### 相关测试文件
- `codex-rs/app-server/tests/suite/v2/request_user_input.rs` - 类似的用户输入请求测试
- `codex-rs/core/tests/suite/permissions.rs` - 核心权限测试
