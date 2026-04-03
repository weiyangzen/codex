# SandboxPolicy.ts 研究文档

## 场景与职责

`SandboxPolicy.ts` 定义了详细的沙箱策略数据结构，用于精确控制 Codex 执行命令时的安全权限。相比简化的 `SandboxMode`，`SandboxPolicy` 提供了更细粒度的控制，包括文件系统访问、网络访问和特殊路径处理。

## 功能点目的

该类型用于：
1. **细粒度控制**：提供比 SandboxMode 更详细的权限配置
2. **灵活策略**：支持多种沙箱配置场景
3. **外部沙箱集成**：支持已在外部沙箱中运行的场景
4. **安全与功能平衡**：允许精确配置所需的最小权限

## 具体技术实现

### 数据结构定义

```typescript
import type { AbsolutePathBuf } from "../AbsolutePathBuf";
import type { NetworkAccess } from "./NetworkAccess";
import type { ReadOnlyAccess } from "./ReadOnlyAccess";

export type SandboxPolicy = 
  | { "type": "dangerFullAccess" }                                          // 完全访问
  | { "type": "readOnly", access: ReadOnlyAccess, networkAccess: boolean }  // 只读
  | { "type": "externalSandbox", networkAccess: NetworkAccess }             // 外部沙箱
  | { 
      "type": "workspaceWrite",                                             // 工作区写入
      writableRoots: Array<AbsolutePathBuf>, 
      readOnlyAccess: ReadOnlyAccess, 
      networkAccess: boolean, 
      excludeTmpdirEnvVar: boolean, 
      excludeSlashTmp: boolean 
    };
```

### 变体详解

#### DangerFullAccess（完全访问）

```typescript
{ type: "dangerFullAccess" }
```

无任何限制，最高风险级别。

#### ReadOnly（只读）

```typescript
{ 
  type: "readOnly", 
  access: ReadOnlyAccess,      // 只读访问配置
  networkAccess: boolean       // 是否允许网络访问
}
```

限制文件系统访问为只读，可选网络访问。

#### ExternalSandbox（外部沙箱）

```typescript
{ 
  type: "externalSandbox", 
  networkAccess: NetworkAccess  // 网络访问配置
}
```

表示进程已在外部沙箱中运行，Codex 不额外施加限制。

#### WorkspaceWrite（工作区写入）

```typescript
{ 
  type: "workspaceWrite",
  writableRoots: AbsolutePathBuf[],      // 额外可写根目录
  readOnlyAccess: ReadOnlyAccess,        // 只读访问配置
  networkAccess: boolean,                // 是否允许网络访问
  excludeTmpdirEnvVar: boolean,          // 是否排除 TMPDIR
  excludeSlashTmp: boolean               // 是否排除 /tmp
}
```

允许写入工作区和指定的额外目录。

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Display, JsonSchema, TS)]
#[strum(serialize_all = "kebab-case")]
#[serde(tag = "type", rename_all = "kebab-case")]
#[ts(tag = "type")]
pub enum SandboxPolicy {
    /// 无任何限制
    #[serde(rename = "danger-full-access")]
    DangerFullAccess,

    /// 只读访问
    #[serde(rename = "read-only")]
    ReadOnly {
        access: ReadOnlyAccess,
        network_access: bool,
    },

    /// 已在外部沙箱中
    #[serde(rename = "external-sandbox")]
    ExternalSandbox {
        network_access: NetworkAccess,
    },

    /// 工作区可写
    #[serde(rename = "workspace-write")]
    WorkspaceWrite {
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

### 辅助方法

```rust
impl SandboxPolicy {
    /// 检查是否为完全访问模式
    pub fn is_danger_full_access(&self) -> bool {
        matches!(self, SandboxPolicy::DangerFullAccess)
    }

    /// 获取网络访问配置
    pub fn network_access(&self) -> NetworkAccess {
        match self {
            SandboxPolicy::DangerFullAccess => NetworkAccess::Enabled,
            SandboxPolicy::ReadOnly { network_access, .. } => {
                if *network_access { NetworkAccess::Enabled } else { NetworkAccess::Restricted }
            }
            SandboxPolicy::ExternalSandbox { network_access } => *network_access,
            SandboxPolicy::WorkspaceWrite { network_access, .. } => {
                if *network_access { NetworkAccess::Enabled } else { NetworkAccess::Restricted }
            }
        }
    }

    /// 获取可写根目录
    pub fn writable_roots(&self, cwd: &Path) -> Vec<WritableRoot> {
        // 根据策略变体返回相应的可写根目录
    }
}
```

### 与 SandboxMode 的关系

```rust
impl From<SandboxMode> for SandboxPolicy {
    fn from(mode: SandboxMode) -> Self {
        match mode {
            SandboxMode::ReadOnly => SandboxPolicy::ReadOnly {
                access: ReadOnlyAccess::default(),
                network_access: false,
            },
            SandboxMode::WorkspaceWrite => SandboxPolicy::WorkspaceWrite {
                writable_roots: vec![],
                read_only_access: ReadOnlyAccess::default(),
                network_access: false,
                exclude_tmpdir_env_var: false,
                exclude_slash_tmp: false,
            },
            SandboxMode::DangerFullAccess => SandboxPolicy::DangerFullAccess,
        }
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxPolicy.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- V1 协议：`codex-rs/app-server-protocol/src/protocol/v1.rs`

### 沙箱实现
- Linux 沙箱：`codex-rs/linux-sandbox/src/linux_run_main.rs`
- Landlock：`codex-rs/core/src/landlock.rs`
- Windows 沙箱：`codex-rs/windows-sandbox-rs/src/lib.rs`
- Seatbelt：`codex-rs/core/src/seatbelt.rs`

### 执行策略
- 执行模块：`codex-rs/core/src/exec_policy.rs`
- 沙箱模块：`codex-rs/core/src/sandboxing/mod.rs`

### 配置集成
- 配置类型：`codex-rs/core/src/config/types.rs`

### 测试覆盖
- 沙箱测试：`codex-rs/core/src/sandboxing/mod_tests.rs`
- 执行测试：`codex-rs/core/src/exec_tests.rs`

## 依赖与外部交互

### 上游依赖
- SandboxMode：简化的模式选择
- 用户配置：详细的沙箱配置
- 平台能力：不同平台支持不同的沙箱技术

### 下游消费
- 沙箱执行器：配置 Landlock/bwrap/Seatbelt/Windows Sandbox
- 权限检查：验证操作是否符合策略

### 策略映射到实现

| 策略变体 | Linux | macOS | Windows |
|---------|-------|-------|---------|
| DangerFullAccess | 无 | 无 | 无 |
| ReadOnly | Landlock/bwrap | Seatbelt | Windows Sandbox |
| ExternalSandbox | 信任外部 | 信任外部 | 信任外部 |
| WorkspaceWrite | Landlock/bwrap | Seatbelt | Windows Sandbox |

## 风险、边界与改进建议

### 边界情况
1. **路径解析**：writableRoots 中的路径必须是绝对路径
2. **权限继承**：子进程继承父进程的沙箱策略
3. **策略冲突**：多个策略同时应用时的优先级

### 潜在风险
1. **DangerFullAccess**：完全绕过沙箱保护
2. **路径遍历**：需要防范 ../ 等路径遍历攻击
3. **竞争条件**：策略检查和执行之间可能存在竞争

### 改进建议
1. **策略验证**：在应用前验证策略的有效性
2. **最小权限**：默认使用更严格的策略
3. **策略审计**：记录策略变更和使用情况
4. **动态调整**：支持运行时调整策略（在安全范围内）
5. **策略模板**：提供常见场景的策略模板
6. **可视化**：提供策略可视化工具帮助理解权限范围
