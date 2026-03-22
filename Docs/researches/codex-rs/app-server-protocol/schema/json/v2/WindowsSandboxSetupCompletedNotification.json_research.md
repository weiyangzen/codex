# WindowsSandboxSetupCompletedNotification.json 研究文档

## 场景与职责

`WindowsSandboxSetupCompletedNotification` 是 Codex App-Server Protocol v2 中的服务器通知类型，专门用于 Windows 平台。当 Windows 沙箱环境设置完成（成功或失败）时发送此通知。

**核心职责：**
- 通知客户端 Windows 沙箱设置操作已完成
- 报告设置结果（成功或失败）
- 在失败时提供错误信息
- 标识设置模式（提升/非提升权限）

## 功能点目的

### 1. Windows 沙箱生命周期管理
Windows 平台使用特殊的沙箱机制：
- 需要预先设置沙箱环境
- 支持两种模式：提升权限（elevated）和非提升权限（unelevated）
- 设置是异步操作，需要通知机制

### 2. 异步完成通知
`windowsSandbox/setupStart` 是异步 RPC：
- 立即返回 `WindowsSandboxSetupStartResponse`（仅确认启动）
- 实际设置完成后发送此通知
- 客户端通过此通知了解设置结果

### 3. 安全状态报告
通知包含关键安全信息：
- `mode`: 使用的设置模式
- `success`: 是否成功
- `error`: 失败时的错误描述

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupCompletedNotification {
    pub mode: WindowsSandboxSetupMode,
    pub success: bool,
    pub error: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum WindowsSandboxSetupMode {
    Elevated,
    Unelevated,
}
```

### 设置模式说明

| 模式 | 描述 | 使用场景 |
|------|------|----------|
| `Elevated` | 提升权限模式 | 需要管理员权限的操作 |
| `Unelevated` | 非提升权限模式 | 普通用户权限操作 |

### 关键流程

1. **启动设置**：
   - 客户端发送 `windowsSandbox/setupStart` 请求
   - 服务器返回 `WindowsSandboxSetupStartResponse`（`started: true`）

2. **异步设置**：
   - 服务器在后台执行沙箱设置
   - 根据 `mode` 参数使用相应的权限级别

3. **完成通知**：
   - 设置完成后发送 `windowsSandbox/setupCompleted` 通知
   - 包含结果状态和可选错误信息

### 通知示例

**成功场景：**
```json
{
  "jsonrpc": "2.0",
  "method": "windowsSandbox/setupCompleted",
  "params": {
    "mode": "unelevated",
    "success": true,
    "error": null
  }
}
```

**失败场景：**
```json
{
  "jsonrpc": "2.0",
  "method": "windowsSandbox/setupCompleted",
  "params": {
    "mode": "elevated",
    "success": false,
    "error": "Failed to initialize Windows Sandbox: access denied"
  }
}
```

## 关键代码路径与文件引用

### 定义位置
- `WindowsSandboxSetupCompletedNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:5004`
- `WindowsSandboxSetupMode`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4980`

### 通知注册
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:934`
  ```rust
  WindowsSandboxSetupCompleted => "windowsSandbox/setupCompleted" (v2::WindowsSandboxSetupCompletedNotification),
  ```

### 测试覆盖
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs:20-64`
  ```rust
  async fn windows_sandbox_setup_start_emits_completion_notification() -> Result<()> {
      // ... 测试代码
      let payload: WindowsSandboxSetupCompletedNotification = serde_json::from_value(
          notification
              .params
              .context("missing windowsSandbox/setupCompleted params")?,
      )?;
      assert_eq!(payload.mode, WindowsSandboxSetupMode::Unelevated);
      Ok(())
  }
  ```

### 相关类型
- `WindowsSandboxSetupStartParams`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4988`
- `WindowsSandboxSetupStartResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4997`

## 依赖与外部交互

### 上游依赖
- Windows 平台特定的沙箱实现
- 系统权限管理（UAC）

### 下游消费
- Windows 客户端接收通知并更新 UI
- 通知用户沙箱准备状态
- 在失败时提供错误反馈

### 协议集成
- JSON-RPC 2.0 通知格式
- 方法名: `windowsSandbox/setupCompleted`
- 参数: `WindowsSandboxSetupCompletedNotification`

### 平台限制
- 仅适用于 Windows 平台
- Unix 平台无此通知（测试文件使用 `#![cfg(unix)]` 跳过）

## 风险、边界与改进建议

### 已知风险

1. **平台专有限制**
   - 此通知仅在 Windows 平台有意义
   - 跨平台客户端需要条件处理

2. **超时问题**
   - 沙箱设置可能耗时较长
   - 客户端需要考虑超时和重试策略

3. **权限问题**
   - Elevated 模式可能因 UAC 设置失败
   - 错误信息需要清晰指导用户

### 边界情况

1. **重复通知**
   - 如果设置过程被中断后重试，可能收到多个通知
   - 客户端需要通过其他机制去重

2. **部分成功**
   - 某些设置可能部分成功
   - 当前设计无法表达部分成功状态

3. **取消操作**
   - 当前无取消设置操作的机制
   - 客户端只能等待完成通知

### 改进建议

1. **进度报告**
   - 考虑添加进度通知（如 `windowsSandbox/setupProgress`）
   - 对于长时间设置提供更好的用户体验

2. **错误分类**
   - 将 `error` 从字符串改为结构化错误类型
   - 包含错误代码、可恢复性等信息

3. **重试支持**
   - 在通知中添加 `can_retry` 字段
   - 指导客户端是否可以安全重试

4. **平台抽象**
   - 考虑统一的沙箱设置抽象
   - 让非 Windows 平台也能使用类似的设置流程

5. **状态查询**
   - 添加 `windowsSandbox/status` 查询接口
   - 允许客户端在错过通知时查询状态
