# WindowsSandboxSetupStartParams.ts Research Document

## 场景与职责

`WindowsSandboxSetupStartParams` 是 App-Server Protocol v2 中的客户端请求参数类型，用于启动 Windows 沙盒环境的设置流程。该类型在以下场景中发挥关键作用：

1. **沙盒初始化**: 在需要执行可能不安全的代码前，预先设置 Windows 沙盒环境
2. **权限提升请求**: 请求以管理员权限设置沙盒（`elevated` 模式）
3. **工作目录配置**: 指定沙盒的工作目录，用于文件系统隔离
4. **NUX 流程**: 新用户首次使用沙盒功能时的引导设置
5. **动态模式切换**: 根据任务需求动态选择不同的沙盒安全级别

## 功能点目的

该参数类型的核心目的是：

- **异步设置启动**: 触发沙盒环境的异步初始化流程
- **模式选择**: 允许客户端指定所需的沙盒安全级别
- **环境配置**: 配置沙盒的工作目录等环境参数
- **用户体验优化**: 支持在后台预先设置沙盒，减少执行命令时的等待时间
- **错误隔离**: 通过预先设置，将沙盒配置错误与命令执行错误分离

## 具体技术实现

### TypeScript 类型定义

```typescript
export type WindowsSandboxSetupStartParams = { 
  mode: WindowsSandboxSetupMode, 
  cwd?: AbsolutePathBuf | null, 
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupStartParams {
    pub mode: WindowsSandboxSetupMode,
    #[ts(optional = nullable)]
    pub cwd: Option<AbsolutePathBuf>,
}
```

### 字段说明

| 字段 | 类型 | 必需 | 说明 |
|-----|------|------|------|
| `mode` | `WindowsSandboxSetupMode` | 是 | 沙盒设置模式（`"elevated"` 或 `"unelevated"`） |
| `cwd` | `AbsolutePathBuf \| null` | 否 | 沙盒的工作目录，可选，默认为当前目录 |

### WindowsSandboxSetupMode

```typescript
export type WindowsSandboxSetupMode = "elevated" | "unelevated";
```

- **`elevated`**: 提升权限模式，需要管理员权限
- **`unelevated`**: 非提升权限模式，使用受限令牌

### AbsolutePathBuf

```typescript
// 来自 ../AbsolutePathBuf.ts
export type AbsolutePathBuf = string; // 经过验证的绝对路径
```

- 确保路径是绝对路径（以驱动器号或 `\\` 开头）
- 路径格式验证在反序列化时进行

### 请求-响应流程

```
客户端发送: WindowsSandboxSetupStartParams
    │
    ├── mode: "elevated" | "unelevated"
    └── cwd?: "/path/to/workdir"
    │
    ▼
服务器验证参数
    │
    ▼
服务器响应: WindowsSandboxSetupStartResponse
    │
    └── started: boolean
    │
    ▼
服务器异步执行设置
    │
    ▼
服务器通知: WindowsSandboxSetupCompletedNotification
    │
    ├── success: true → 设置完成
    └── success: false → 设置失败，error 字段包含原因
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4985-4992) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/WindowsSandboxSetupStartParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupStartParams.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 `windowsSandbox/setup` 方法的参数类型 |
| `codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts` | 包含在客户端请求联合类型中 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理沙盒设置启动请求 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 应用服务器触发沙盒设置 |
| `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs` | 集成测试 |

### 相关类型

| 类型 | 说明 |
|-----|------|
| `WindowsSandboxSetupStartResponse` | 启动请求的响应类型 |
| `WindowsSandboxSetupCompletedNotification` | 设置完成的通知类型 |
| `WindowsSandboxSetupMode` | 沙盒模式枚举 |
| `AbsolutePathBuf` | 绝对路径类型 |

## 依赖与外部交互

### 内部依赖

- **`WindowsSandboxSetupMode`**: 沙盒设置模式枚举
- **`AbsolutePathBuf`**: 绝对路径类型，确保路径格式正确
- **`WindowsSandboxSetupStartResponse`**: 对应的响应类型

### 协议依赖

- 属于 **Client Request** 类别（客户端 → 服务器）
- 对应 RPC 方法: `windowsSandbox/setup`
- 与 `WindowsSandboxSetupStartResponse` 形成同步请求-响应
- 与 `WindowsSandboxSetupCompletedNotification` 形成异步通知

### Windows 系统交互

```rust
// 伪代码示意
pub async fn start_windows_sandbox_setup(params: WindowsSandboxSetupStartParams) -> Result<bool, Error> {
    let cwd = params.cwd.unwrap_or_else(|| std::env::current_dir()?);
    
    match params.mode {
        Elevated => {
            // 检查管理员权限
            // 配置 AppContainer
            // 设置文件系统重定向
        }
        Unelevated => {
            // 创建受限令牌
            // 配置基础沙盒策略
        }
    }
    
    // 异步执行设置
    tokio::spawn(async move {
        let result = do_setup(mode, cwd).await;
        send_completed_notification(result).await;
    });
    
    Ok(true) // 设置已启动
}
```

## 风险、边界与改进建议

### 潜在风险

1. **路径遍历**: `cwd` 参数可能包含恶意路径（如 `C:\Windows\System32`）
2. **权限提升滥用**: `elevated` 模式可能被滥用获取管理员权限
3. **资源耗尽**: 频繁的沙盒设置请求可能耗尽系统资源
4. **并发冲突**: 多个并发的沙盒设置请求可能相互干扰

### 边界情况

1. **路径不存在**: `cwd` 指定的路径不存在
2. **路径不可访问**: `cwd` 路径存在但当前用户无访问权限
3. **沙盒已在设置中**: 重复发送设置请求
4. **模式冲突**: 请求的模式与当前已设置的沙盒模式不同
5. **非 Windows 平台**: 在非 Windows 系统上调用此方法

### 改进建议

1. **路径验证增强**: 添加更严格的路径验证：
   ```rust
   impl WindowsSandboxSetupStartParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if let Some(ref cwd) = self.cwd {
               // 验证路径存在
               if !cwd.exists() {
                   return Err(ValidationError::PathNotFound);
               }
               // 验证路径可写
               if !is_writable(cwd) {
                   return Err(ValidationError::PathNotWritable);
               }
               // 验证路径不在系统关键目录
               if is_system_directory(cwd) {
                   return Err(ValidationError::SystemDirectory);
               }
           }
           Ok(())
       }
   }
   ```

2. **添加超时配置**: 允许客户端指定设置超时：
   ```typescript
   export type WindowsSandboxSetupStartParams = {
     mode: WindowsSandboxSetupMode,
     cwd?: AbsolutePathBuf | null,
     timeoutMs?: number, // 新增：设置超时时间
   };
   ```

3. **强制模式检查**: 添加选项强制重新设置即使已有沙盒：
   ```typescript
   export type WindowsSandboxSetupStartParams = {
     mode: WindowsSandboxSetupMode,
     cwd?: AbsolutePathBuf | null,
     force?: boolean, // 新增：强制重新设置
   };
   ```

4. **预检模式**: 添加仅检查而不实际设置的模式：
   ```typescript
   export type WindowsSandboxSetupStartParams = {
     mode: WindowsSandboxSetupMode,
     cwd?: AbsolutePathBuf | null,
     dryRun?: boolean, // 新增：预检模式
   };
   ```

5. **并发控制**: 实现设置请求的排队和去重：
   ```rust
   pub struct SandboxSetupQueue {
       pending: HashMap<WindowsSandboxSetupMode, SetupTask>,
       // 相同模式的请求合并，不同模式的请求排队
   }
   ```

6. **回退策略配置**: 允许配置失败时的自动回退：
   ```typescript
   export type WindowsSandboxSetupStartParams = {
     mode: WindowsSandboxSetupMode,
     cwd?: AbsolutePathBuf | null,
     fallbackMode?: WindowsSandboxSetupMode, // 失败时尝试的模式
   };
   ```

### 测试覆盖

- 集成测试: `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`
- 建议添加：
  - 路径验证测试（无效路径、系统目录、不可写路径）
  - 并发设置请求测试
  - 权限被拒绝场景测试
  - 非 Windows 平台的优雅降级测试
  - 设置超时测试
  - 资源清理测试（设置失败后的资源释放）
