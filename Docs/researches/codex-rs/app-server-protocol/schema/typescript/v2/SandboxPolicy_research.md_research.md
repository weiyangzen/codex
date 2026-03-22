# SandboxPolicy 研究文档

## 场景与职责

`SandboxPolicy` 是 Codex App Server Protocol v2 中用于定义细粒度沙箱策略的枚举类型。相比 `SandboxMode` 的高层抽象，`SandboxPolicy` 提供了更详细的沙箱配置选项，包括文件系统访问、网络访问和临时目录处理等。

该类型在 `TurnStartParams` 和 `ThreadStartParams` 中使用，允许用户在启动回合或线程时指定详细的沙箱策略。

## 功能点目的

1. **细粒度控制**：提供比 `SandboxMode` 更详细的沙箱配置
2. **灵活配置**：支持自定义可写根目录和只读访问范围
3. **网络安全**：控制网络访问权限
4. **临时目录管理**：控制临时目录的访问权限

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
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

```typescript
// TypeScript 生成类型 (schema/typescript/v2/SandboxPolicy.ts)
export type SandboxPolicy = 
    | { "type": "dangerFullAccess" }
    | { "type": "readOnly", access: ReadOnlyAccess, networkAccess: boolean }
    | { "type": "externalSandbox", networkAccess: NetworkAccess }
    | { "type": "workspaceWrite", writableRoots: Array<AbsolutePathBuf>, readOnlyAccess: ReadOnlyAccess, networkAccess: boolean, excludeTmpdirEnvVar: boolean, excludeSlashTmp: boolean };
```

### 变体说明

| 变体 | 说明 | 字段 |
|------|------|------|
| `DangerFullAccess` | 完全访问，最危险 | 无 |
| `ReadOnly` | 只读模式 | `access`, `network_access` |
| `ExternalSandbox` | 外部沙箱 | `network_access` |
| `WorkspaceWrite` | 工作区可写 | `writable_roots`, `read_only_access`, `network_access`, `exclude_tmpdir_env_var`, `exclude_slash_tmp` |

### 子类型定义

```rust
// 只读访问配置
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ReadOnlyAccess {
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Restricted {
        #[serde(default = "default_include_platform_defaults")]
        include_platform_defaults: bool,
        #[serde(default)]
        readable_roots: Vec<AbsolutePathBuf>,
    },
    #[default]
    FullAccess,
}

// 网络访问配置
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum NetworkAccess {
    #[default]
    Restricted,
    Enabled,
}
```

### 核心协议映射

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
            SandboxPolicy::WorkspaceWrite { /* ... */ } => {
                codex_protocol::protocol::SandboxPolicy::WorkspaceWrite { /* ... */ }
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 1271-1381)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/SandboxPolicy.ts`

### 相关类型
- `ReadOnlyAccess`: 只读访问配置
- `NetworkAccess`: 网络访问配置
- `SandboxMode`: 高层沙箱模式抽象
- `TurnStartParams`: 包含 `sandbox_policy` 字段

### 使用场景
- `turn/start` 请求中的沙箱策略覆盖
- `thread/start` 请求中的初始沙箱配置
- 测试用例中验证沙箱策略转换

## 依赖与外部交互

### 内部依赖
- `ReadOnlyAccess`: 只读访问配置
- `NetworkAccess`: 网络访问配置
- `AbsolutePathBuf`: 绝对路径类型
- `codex_protocol::protocol::SandboxPolicy`: 核心协议类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**ReadOnly 策略**:
```json
{
    "type": "readOnly",
    "access": {
        "type": "restricted",
        "includePlatformDefaults": true,
        "readableRoots": ["/home/user/docs"]
    },
    "networkAccess": false
}
```

**WorkspaceWrite 策略**:
```json
{
    "type": "workspaceWrite",
    "writableRoots": ["/home/user/project"],
    "readOnlyAccess": {
        "type": "fullAccess"
    },
    "networkAccess": true,
    "excludeTmpdirEnvVar": true,
    "excludeSlashTmp": true
}
```

## 风险、边界与改进建议

### 当前限制
1. **复杂性**：相比 `SandboxMode`，配置更复杂
2. **验证缺失**：类型本身不验证路径的有效性和安全性
3. **平台差异**：不同平台的沙箱实现可能有差异

### 边界情况
1. **路径冲突**：`writable_roots` 和 `readable_roots` 可能有重叠
2. **空列表**：`writable_roots` 为空列表时的行为
3. **根目录访问**：`/` 或 `C:\` 等特殊路径的处理

### 测试覆盖

从 `v2.rs` 测试代码可以看到策略转换测试：

```rust
#[test]
fn test_sandbox_policy_roundtrip() {
    let v2_policy = SandboxPolicy::ExternalSandbox {
        network_access: NetworkAccess::Restricted,
    };
    let core_policy = v2_policy.to_core();
    assert!(matches!(
        core_policy,
        codex_protocol::protocol::SandboxPolicy::ExternalSandbox { .. }
    ));
    let back_to_v2 = SandboxPolicy::from(core_policy);
    assert_eq!(back_to_v2, v2_policy);
}

#[test]
fn test_sandbox_policy_readonly() {
    let v2_policy = SandboxPolicy::ReadOnly {
        access: ReadOnlyAccess::Restricted {
            include_platform_defaults: true,
            readable_roots: vec![],
        },
        network_access: false,
    };
    let core_policy = v2_policy.to_core();
    // ...
}

#[test]
fn test_sandbox_policy_workspace_write() {
    let v2_policy = SandboxPolicy::WorkspaceWrite {
        writable_roots: vec![PathBuf::from("/tmp")],
        read_only_access: ReadOnlyAccess::FullAccess,
        network_access: true,
        exclude_tmpdir_env_var: false,
        exclude_slash_tmp: false,
    };
    // ...
}
```

### 改进建议

1. **添加验证方法**：
   ```rust
   impl SandboxPolicy {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证路径有效性
           // 检查冲突
           // 验证安全性
       }
   }
   ```

2. **添加默认配置**：
   ```rust
   impl SandboxPolicy {
       pub fn safe_default() -> Self {
           SandboxPolicy::ReadOnly {
               access: ReadOnlyAccess::Restricted {
                   include_platform_defaults: true,
                   readable_roots: vec![],
               },
               network_access: false,
           }
       }
   }
   ```

3. **添加策略合并**：
   ```rust
   impl SandboxPolicy {
       pub fn merge(&self, other: &SandboxPolicy) -> SandboxPolicy {
           // 合并两个策略，取最严格的限制
       }
   }
   ```

4. **添加策略描述**：
   ```rust
   impl SandboxPolicy {
       pub fn description(&self) -> String {
           // 生成人类可读的策略描述
       }
   }
   ```

### 兼容性注意
- 使用 tagged union 模式确保可扩展性
- 使用 `#[serde(default)]` 确保向后兼容
- 与 `SandboxMode` 的转换确保两种抽象的一致性

### 与 SandboxMode 的关系

| 特性 | SandboxMode | SandboxPolicy |
|------|-------------|---------------|
| 抽象级别 | 高层 | 底层 |
| 配置复杂度 | 简单 | 详细 |
| 使用场景 | 配置文件 | 运行时覆盖 |
| 灵活性 | 有限 | 高 |

**转换关系**：
- `SandboxMode::ReadOnly` → `SandboxPolicy::ReadOnly`（默认配置）
- `SandboxMode::WorkspaceWrite` → `SandboxPolicy::WorkspaceWrite`（默认配置）
- `SandboxMode::DangerFullAccess` → `SandboxPolicy::DangerFullAccess`

### 使用建议

```rust
// 简单场景：使用 SandboxMode
let mode = SandboxMode::ReadOnly;

// 复杂场景：使用 SandboxPolicy
let policy = SandboxPolicy::WorkspaceWrite {
    writable_roots: vec!["/home/user/project".into()],
    read_only_access: ReadOnlyAccess::Restricted {
        include_platform_defaults: true,
        readable_roots: vec!["/home/user/docs".into()],
    },
    network_access: false,
    exclude_tmpdir_env_var: true,
    exclude_slash_tmp: true,
};
```
