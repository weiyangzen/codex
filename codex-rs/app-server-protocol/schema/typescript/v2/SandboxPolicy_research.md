# SandboxPolicy 研究文档

## 1. 场景与职责

`SandboxPolicy` 是 Codex app-server-protocol v2 协议中的沙箱策略类型，用于精细控制代码执行环境的安全策略。与 `SandboxMode` 相比，`SandboxPolicy` 提供更细粒度的配置选项，包括可写根目录、只读访问范围、网络访问控制等。

### 使用场景
- **精细化权限控制**：需要精确控制文件系统和网络访问范围
- **多根目录写入**：需要在多个特定目录进行写入操作
- **外部沙箱集成**：与 Docker、Windows Sandbox 等外部沙箱集成
- **企业安全策略**：满足严格的企业安全合规要求

## 2. 功能点目的

该类型的核心目的是：
1. **细粒度控制**：提供比 `SandboxMode` 更精细的权限配置
2. **灵活配置**：支持多目录、网络、临时文件等复杂场景
3. **外部集成**：支持与外部沙箱技术的集成

### 策略变体对比
| 变体 | 描述 | 典型使用场景 |
|------|------|--------------|
| `dangerFullAccess` | 无限制访问 | 完全信任的环境 |
| `readOnly` | 只读 + 可选网络 | 代码分析、安全审查 |
| `externalSandbox` | 外部沙箱 + 网络配置 | Docker、VM 沙箱 |
| `workspaceWrite` | 工作区写入 + 详细配置 | 代码生成、构建任务 |

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
import type { AbsolutePathBuf } from "../AbsolutePathBuf";
import type { NetworkAccess } from "./NetworkAccess";
import type { ReadOnlyAccess } from "./ReadOnlyAccess";

export type SandboxPolicy = 
  | { "type": "dangerFullAccess" } 
  | { "type": "readOnly", access: ReadOnlyAccess, networkAccess: boolean } 
  | { "type": "externalSandbox", networkAccess: NetworkAccess } 
  | { "type": "workspaceWrite", 
      writableRoots: Array<AbsolutePathBuf>, 
      readOnlyAccess: ReadOnlyAccess, 
      networkAccess: boolean, 
      excludeTmpdirEnvVar: boolean, 
      excludeSlashTmp: boolean };
```

### 字段说明

#### `dangerFullAccess`
无字段，表示完全访问权限。

#### `readOnly`
| 字段 | 类型 | 说明 |
|------|------|------|
| `access` | `ReadOnlyAccess` | 只读访问范围配置 |
| `networkAccess` | `boolean` | 是否允许网络访问 |

#### `externalSandbox`
| 字段 | 类型 | 说明 |
|------|------|------|
| `networkAccess` | `NetworkAccess` | 网络访问配置（受限或启用） |

#### `workspaceWrite`
| 字段 | 类型 | 说明 |
|------|------|------|
| `writableRoots` | `Array<AbsolutePathBuf>` | 可写入的根目录列表 |
| `readOnlyAccess` | `ReadOnlyAccess` | 只读访问范围配置 |
| `networkAccess` | `boolean` | 是否允许网络访问 |
| `excludeTmpdirEnvVar` | `boolean` | 是否排除 TMPDIR 环境变量目录 |
| `excludeSlashTmp` | `boolean` | 是否排除 /tmp 目录 |

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum SandboxPolicy {
    DangerFullAccess,
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    ReadOnly {
        #[serde(default)]
        access: ReadOnlyAccess,
        #[serde(default)]
        network_access: bool,
    },
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    ExternalSandbox {
        #[serde(default)]
        network_access: NetworkAccess,
    },
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    WorkspaceWrite {
        #[serde(default)]
        writable_roots: Vec<AbsolutePathBuf>,
        #[serde(default)]
        read_only_access: ReadOnlyAccess,
        #[serde(default)]
        network_access: bool,
        #[serde(default)]
        exclude_tmpdir_env_var: bool,
        #[serde(default)]
        exclude_slash_tmp: bool,
    },
}
```

### 类型转换实现
```rust
impl SandboxPolicy {
    pub fn to_core(&self) -> codex_protocol::protocol::SandboxPolicy {
        match self {
            SandboxPolicy::DangerFullAccess => {
                codex_protocol::protocol::SandboxPolicy::DangerFullAccess
            }
            SandboxPolicy::ReadOnly { access, network_access } => {
                codex_protocol::protocol::SandboxPolicy::ReadOnly {
                    access: access.to_core(),
                    network_access: *network_access,
                }
            }
            SandboxPolicy::ExternalSandbox { network_access } => {
                codex_protocol::protocol::SandboxPolicy::ExternalSandbox {
                    network_access: match network_access {
                        NetworkAccess::Restricted => CoreNetworkAccess::Restricted,
                        NetworkAccess::Enabled => CoreNetworkAccess::Enabled,
                    },
                }
            }
            SandboxPolicy::WorkspaceWrite { ... } => { ... }
        }
    }
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1271-1381)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/SandboxPolicy.ts`

### 使用位置

#### Windows 沙箱实现
- **审计**: `codex-rs/windows-sandbox-rs/src/audit.rs` (行 217-271)
- **身份**: `codex-rs/windows-sandbox-rs/src/identity.rs` (行 104-126)
- **提升实现**: `codex-rs/windows-sandbox-rs/src/elevated_impl.rs` (行 237-254)
- **编排器**: `codex-rs/windows-sandbox-rs/src/setup_orchestrator.rs` (行 82-368)

#### 应用服务器
- **消息处理器**: `codex-rs/app-server/src/codex_message_processor.rs`

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json`

## 5. 依赖与外部交互

### 导入依赖
| 类型 | 来源 | 说明 |
|------|------|------|
| `AbsolutePathBuf` | `../AbsolutePathBuf` | 绝对路径类型 |
| `NetworkAccess` | `./NetworkAccess` | 网络访问配置 |
| `ReadOnlyAccess` | `./ReadOnlyAccess` | 只读访问配置 |

### 被依赖类型
- 工具执行配置、会话配置等

### 核心协议映射
- `codex_protocol::protocol::SandboxPolicy` ↔ `SandboxPolicy`

## 6. 风险、边界与改进建议

### 潜在风险
1. **配置复杂性**：相比 `SandboxMode`，配置更复杂，容易出错
2. **路径遍历**：`writableRoots` 需要验证防止路径遍历攻击
3. **默认安全**：`#[serde(default)]` 可能导致意外的宽松配置

### 边界情况
- **空 writableRoots**：`workspaceWrite` 变体中可写根目录为空
- **路径重叠**：可写目录与只读目录的范围重叠
- **符号链接**：需要处理符号链接的解析和限制

### 改进建议
1. **验证增强**：
   - 验证所有路径为绝对路径
   - 检测并阻止路径遍历
   - 验证目录存在性和权限

2. **配置合并**：
   ```typescript
   // 支持配置继承和合并
   interface SandboxPolicyConfig {
     base?: SandboxPolicy;
     overrides?: Partial<SandboxPolicy>;
   }
   ```

3. **审计日志**：
   - 记录所有策略变更
   - 记录危险操作的策略上下文

4. **可视化工具**：
   - 提供策略可视化，显示实际的访问范围
   - 冲突检测和警告

5. **模板支持**：
   ```typescript
   const templates: Record<string, SandboxPolicy> = {
     "node-project": {
       type: "workspaceWrite",
       writableRoots: ["/workspace", "/tmp/node-cache"],
       networkAccess: true,
       // ...
     }
   };
   ```

### 使用示例
```typescript
// 只读模式，允许网络
const readOnlyPolicy: SandboxPolicy = {
  type: "readOnly",
  access: { type: "full" },
  networkAccess: true
};

// 工作区写入模式
const workspacePolicy: SandboxPolicy = {
  type: "workspaceWrite",
  writableRoots: ["/home/user/project", "/tmp/build"],
  readOnlyAccess: { type: "full" },
  networkAccess: true,
  excludeTmpdirEnvVar: false,
  excludeSlashTmp: false
};

// 外部沙箱
const externalPolicy: SandboxPolicy = {
  type: "externalSandbox",
  networkAccess: "restricted"
};
```

### 与 SandboxMode 的关系
```
SandboxMode (高层抽象)
├── "read-only" → SandboxPolicy::ReadOnly
├── "workspace-write" → SandboxPolicy::WorkspaceWrite
└── "danger-full-access" → SandboxPolicy::DangerFullAccess

SandboxPolicy (底层实现)  <-- 本类型
├── DangerFullAccess
├── ReadOnly { access, network_access }
├── ExternalSandbox { network_access }
└── WorkspaceWrite { writable_roots, read_only_access, network_access, ... }
```
