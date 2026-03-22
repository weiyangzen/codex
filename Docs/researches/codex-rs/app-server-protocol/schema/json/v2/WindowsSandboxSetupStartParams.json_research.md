# WindowsSandboxSetupStartParams.json 研究文档

## 场景与职责

`WindowsSandboxSetupStartParams` 是 Codex App-Server Protocol v2 中用于启动 Windows 沙箱环境设置的请求参数结构。它是 `windowsSandbox/setupStart` RPC 方法的核心输入，仅在 Windows 平台有效。

**核心职责：**
- 指定沙箱设置模式（提升/非提升权限）
- 可选地指定工作目录
- 触发异步沙箱初始化流程

## 功能点目的

### 1. Windows 沙箱初始化
Windows 平台需要特殊的沙箱设置：
- 在 AI 执行命令前准备隔离环境
- 支持两种权限模式以适应不同需求
- 设置过程是异步的，需要后续通知

### 2. 权限模式选择
`mode` 字段决定沙箱的权限级别：
- `Elevated`: 管理员权限，可执行系统级操作
- `Unelevated`: 普通用户权限，更安全的默认选项

### 3. 工作目录配置
可选的 `cwd` 字段：
- 指定沙箱中的初始工作目录
- 必须是绝对路径（通过 `AbsolutePathBuf` 验证）
- 为 `None` 时使用默认目录

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupStartParams {
    pub mode: WindowsSandboxSetupMode,
    #[ts(optional = nullable)]
    pub cwd: Option<AbsolutePathBuf>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum WindowsSandboxSetupMode {
    Elevated,
    Unelevated,
}
```

### 路径验证

`cwd` 使用 `AbsolutePathBuf` 类型：
- 确保路径是绝对路径
- 路径会被规范化（normalized）
- 不保证路径存在或可被访问

### 关键流程

1. **接收请求**：服务器接收 `windowsSandbox/setupStart` 请求
2. **路径验证**：验证 `cwd` 是绝对路径（如果提供）
3. **启动设置**：在后台启动沙箱初始化
4. **返回响应**：立即返回 `WindowsSandboxSetupStartResponse`
5. **完成通知**：设置完成后发送 `windowsSandbox/setupCompleted` 通知

### 请求示例

```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "method": "windowsSandbox/setupStart",
  "params": {
    "mode": "unelevated",
    "cwd": "C:\\Users\\User\\Projects"
  }
}
```

## 关键代码路径与文件引用

### 定义位置
- `WindowsSandboxSetupStartParams`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4988`
- `WindowsSandboxSetupMode`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4980`

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:425-428`
  ```rust
  WindowsSandboxSetupStart => "windowsSandbox/setupStart" {
      params: v2::WindowsSandboxSetupStartParams,
      response: v2::WindowsSandboxSetupStartResponse,
  },
  ```

### 测试覆盖
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`
  - `windows_sandbox_setup_start_emits_completion_notification`: 成功场景
  - `windows_sandbox_setup_start_rejects_relative_cwd`: 路径验证

### 路径验证测试
```rust
async fn windows_sandbox_setup_start_rejects_relative_cwd() -> Result<()> {
    let request_id = mcp
        .send_raw_request(
            "windowsSandbox/setupStart",
            Some(serde_json::json!({
                "mode": "unelevated",
                "cwd": "relative-root",  // 相对路径应该被拒绝
            })),
        )
        .await?;

    let err = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_error_message(RequestId::Integer(request_id)),
    ).await??;

    assert_eq!(err.error.code, -32600);  // Invalid request
    assert!(err.error.message.contains("Invalid request"));
    Ok(())
}
```

### 响应类型
- `WindowsSandboxSetupStartResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4997`
  ```rust
  pub struct WindowsSandboxSetupStartResponse {
      pub started: bool,
  }
  ```

## 依赖与外部交互

### 上游依赖
- `AbsolutePathBuf`: 来自 `codex_utils_absolute_path` crate
  - 保证路径是绝对路径
  - 提供序列化/反序列化支持

### 下游消费
- Windows 特定的沙箱实现
- 系统权限管理服务

### 协议集成
- 作为 JSON-RPC 2.0 请求的 `params` 字段
- 方法名: `windowsSandbox/setupStart`
- 响应类型: `WindowsSandboxSetupStartResponse`
- 后续通知: `windowsSandbox/setupCompleted`

### 平台限制
- 仅在 Windows 平台有效
- 非 Windows 平台调用可能返回错误或未实现

## 风险、边界与改进建议

### 已知风险

1. **平台专有限制**
   - 此 RPC 仅在 Windows 平台有意义
   - 跨平台代码需要条件编译或运行时检查

2. **路径验证限制**
   - `AbsolutePathBuf` 只验证路径格式，不验证存在性
   - 无效路径可能在设置阶段才报错

3. **异步复杂性**
   - 设置是异步的，需要配合通知使用
   - 客户端需要正确处理通知丢失场景

### 边界情况

1. **重复调用**
   - 当前实现未明确禁止重复调用
   - 可能的行为：重置沙箱或返回错误

2. **模式切换**
   - 从 elevated 切换到 unelevated（或相反）的行为未明确
   - 可能需要先停止现有沙箱

3. **cwd 为 None**
   - 使用默认工作目录
   - 默认目录的行为依赖具体实现

### 改进建议

1. **幂等性保证**
   - 明确重复调用的行为
   - 考虑添加 `force` 参数控制是否重置现有沙箱

2. **预验证增强**
   - 在响应前验证 `cwd` 的存在性和可访问性
   - 提前发现配置错误

3. **进度追踪**
   - 添加 `request_id` 或 `setup_id` 字段
   - 允许客户端追踪特定设置请求

4. **取消支持**
   - 添加 `windowsSandbox/setupCancel` 方法
   - 允许客户端取消进行中的设置

5. **配置扩展**
   - 考虑添加更多配置选项：
     - 内存限制
     - 网络访问控制
     - 挂载点配置

6. **跨平台抽象**
   - 考虑设计通用的沙箱设置接口
   - 让 macOS/Linux 也能使用类似的流程（使用各自的沙箱技术）
