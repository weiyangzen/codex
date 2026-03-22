# SandboxMode 研究文档

## 场景与职责

`SandboxMode` 是 Codex App Server Protocol v2 中用于定义沙箱执行模式的枚举类型。它控制 Codex 执行命令和访问资源的权限级别，是安全模型的核心组件。

该类型在配置（`Config`）和回合启动参数（`TurnStartParams`）中使用，允许用户根据信任级别和安全需求选择不同的沙箱策略。

## 功能点目的

1. **安全级别控制**：提供三种不同严格程度的沙箱模式
2. **权限管理**：控制文件系统访问和网络访问权限
3. **灵活配置**：支持运行时切换沙箱模式
4. **安全默认**：默认使用最安全的只读模式

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[ts(rename_all = "kebab-case", export_to = "v2/")]
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}

impl SandboxMode {
    pub fn to_core(self) -> CoreSandboxMode {
        match self {
            SandboxMode::ReadOnly => CoreSandboxMode::ReadOnly,
            SandboxMode::WorkspaceWrite => CoreSandboxMode::WorkspaceWrite,
            SandboxMode::DangerFullAccess => CoreSandboxMode::DangerFullAccess,
        }
    }
}

impl From<CoreSandboxMode> for SandboxMode {
    fn from(value: CoreSandboxMode) -> Self {
        match value {
            CoreSandboxMode::ReadOnly => SandboxMode::ReadOnly,
            CoreSandboxMode::WorkspaceWrite => SandboxMode::WorkspaceWrite,
            CoreSandboxMode::DangerFullAccess => SandboxMode::DangerFullAccess,
        }
    }
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/SandboxMode.ts)
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```

### 变体说明

| 变体 | 值 | 说明 | 适用场景 |
|------|-----|------|----------|
| `ReadOnly` | `"read-only"` | 只读模式，最安全 | 默认模式，不信任的代码 |
| `WorkspaceWrite` | `"workspace-write"` | 工作区可写 | 日常开发，需要文件修改 |
| `DangerFullAccess` | `"danger-full-access"` | 完全访问，最危险 | 系统管理，完全信任 |

### 核心协议映射

```rust
// 与 codex_protocol::config_types::SandboxMode 的双向转换
impl SandboxMode {
    pub fn to_core(self) -> CoreSandboxMode {
        match self {
            SandboxMode::ReadOnly => CoreSandboxMode::ReadOnly,
            SandboxMode::WorkspaceWrite => CoreSandboxMode::WorkspaceWrite,
            SandboxMode::DangerFullAccess => CoreSandboxMode::DangerFullAccess,
        }
    }
}

impl From<CoreSandboxMode> for SandboxMode {
    fn from(value: CoreSandboxMode) -> Self {
        match value {
            CoreSandboxMode::ReadOnly => SandboxMode::ReadOnly,
            CoreSandboxMode::WorkspaceWrite => SandboxMode::WorkspaceWrite,
            CoreSandboxMode::DangerFullAccess => SandboxMode::DangerFullAccess,
        }
    }
}
```

### 使用上下文

```rust
// 在 Config 中使用
pub struct Config {
    pub sandbox_mode: Option<SandboxMode>,
    pub sandbox_workspace_write: Option<SandboxWorkspaceWrite>,
    // ...
}

// 在 TurnStartParams 中使用
pub struct TurnStartParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    pub sandbox_policy: Option<SandboxPolicy>,  // 更细粒度的控制
    // ...
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 298-325)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/SandboxMode.ts`

### 相关类型
- `SandboxPolicy`: 更细粒度的沙箱策略
- `SandboxWorkspaceWrite`: 工作区写入配置的详细设置
- `Config`: 包含 `sandbox_mode` 字段
- `ConfigRequirements`: 包含 `allowed_sandbox_modes` 字段

### 使用场景
- 配置文件中的 `sandbox_mode` 设置
- `turn/start` 请求中的运行时覆盖
- 配置要求中的允许沙箱模式限制

## 依赖与外部交互

### 内部依赖
- `codex_protocol::config_types::SandboxMode`: 核心协议类型
- `serde`: 序列化/反序列化（使用 `kebab-case` 命名）
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**配置文件示例**:
```toml
sandbox_mode = "read-only"
```

**API 请求示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "turn/start",
    "params": {
        "threadId": "thread-123",
        "input": [...],
        "sandbox": "workspace-write"
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **粒度较粗**：只有三种模式，无法细粒度控制
2. **无网络控制**：`SandboxMode` 本身不控制网络访问
3. **命名警告**：`DangerFullAccess` 的命名明确警告风险，但仍可能被误用

### 边界情况
1. **模式切换**：运行时切换沙箱模式的影响
2. **策略冲突**：`SandboxMode` 与 `SandboxPolicy` 的组合
3. **继承关系**：配置层级中的沙箱模式继承

### 与 SandboxPolicy 的关系

`SandboxMode` 是高层抽象，`SandboxPolicy` 提供更细粒度的控制：

```rust
pub enum SandboxPolicy {
    DangerFullAccess,
    ReadOnly {
        access: ReadOnlyAccess,
        network_access: bool,
    },
    ExternalSandbox {
        network_access: NetworkAccess,
    },
    WorkspaceWrite {
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

### 改进建议

1. **添加中间模式**：
   ```rust
   pub enum SandboxMode {
       ReadOnly,
       ReadOnlyWithNetwork,  // 新增：只读但允许网络
       WorkspaceWrite,
       WorkspaceWriteWithNetwork,  // 新增：工作区可写且允许网络
       DangerFullAccess,
   }
   ```

2. **添加自定义模式**：
   ```rust
   pub enum SandboxMode {
       // ...
       Custom(SandboxPolicy),  // 新增：使用自定义策略
   }
   ```

3. **添加模式描述**：
   ```rust
   impl SandboxMode {
       pub fn description(&self) -> &'static str {
           match self {
               SandboxMode::ReadOnly => "只能读取文件，无法修改",
               SandboxMode::WorkspaceWrite => "可以修改工作区文件",
               SandboxMode::DangerFullAccess => "完全系统访问，谨慎使用",
           }
       }
   }
   ```

### 兼容性注意
- 使用 `kebab-case` 命名（如 `"read-only"`）与配置文件保持一致
- 与 `SandboxPolicy` 的转换确保数据一致性
- 配置要求中的 `allowed_sandbox_modes` 可以限制可用模式

### 安全建议

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 查看代码/文档 | `ReadOnly` | 最安全，防止意外修改 |
| 日常开发 | `WorkspaceWrite` | 允许必要的文件修改 |
| 系统管理 | `DangerFullAccess` | 需要完全访问权限 |
| 运行未知代码 | `ReadOnly` | 防止恶意代码破坏系统 |
| CI/CD 环境 | `ReadOnly` 或 `WorkspaceWrite` | 根据需求选择 |

### 配置示例

```toml
# config.toml

# 默认使用只读模式
sandbox_mode = "read-only"

# 工作区写入的详细配置（当 sandbox_mode = "workspace-write" 时生效）
[sandbox_workspace_write]
writable_roots = ["/home/user/project"]
network_access = false
exclude_tmpdir_env_var = true
exclude_slash_tmp = true

# 定义多个配置文件
[profiles.safe]
model = "gpt-4o-mini"
sandbox_mode = "read-only"

[profiles.dev]
model = "gpt-4o"
sandbox_mode = "workspace-write"

[profiles.admin]
model = "o3-mini"
sandbox_mode = "danger-full-access"
approval_policy = "on_request"
```
