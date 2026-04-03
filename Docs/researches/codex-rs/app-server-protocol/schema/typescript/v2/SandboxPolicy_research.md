# SandboxPolicy 研究文档

## 场景与职责

`SandboxPolicy` 是 Codex app-server-protocol v2 协议中的沙箱策略类型，用于精细控制代码执行环境的安全策略。与 `SandboxMode` 相比，`SandboxPolicy` 提供更细粒度的配置选项，包括可写根目录、只读访问范围、网络访问控制等。

在 Codex 的安全体系中，`SandboxPolicy` 承担以下职责：
1. **细粒度控制**：提供比 `SandboxMode` 更精细的权限配置
2. **灵活策略**：支持多种沙箱策略变体
3. **外部沙箱集成**：支持外部沙箱环境
4. **运行时安全**：在运行时强制执行安全策略

## 功能点目的

### 核心功能
- **DangerFullAccess**：完全访问，无限制
- **ReadOnly**：只读访问，可配置访问范围
- **WorkspaceWrite**：工作区可写，支持细粒度配置
- **ExternalSandbox**：外部沙箱环境集成

### 设计意图
- **细粒度**：支持精确控制每个权限维度
- **可扩展**：支持外部沙箱集成
- **类型安全**：使用标签联合确保类型安全
- **向后兼容**：支持从 `SandboxMode` 转换

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`SandboxPolicy.ts`）：
```typescript
export type SandboxPolicy = 
  | { "type": "dangerFullAccess" }
  | { "type": "readOnly", access: ReadOnlyAccess, networkAccess: boolean }
  | { "type": "externalSandbox", networkAccess: NetworkAccess }
  | { "type": "workspaceWrite", writableRoots: Array<AbsolutePathBuf>, readOnlyAccess: ReadOnlyAccess, networkAccess: boolean, excludeTmpdirEnvVar: boolean, excludeSlashTmp: boolean };
```

**Rust 定义**（`v2.rs` 行 1275-1305）：
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

### 变体说明

| 变体 | 字段 | 说明 |
|------|------|------|
| `DangerFullAccess` | 无 | 完全访问，无限制 |
| `ReadOnly` | `access`, `networkAccess` | 只读访问 |
| `ExternalSandbox` | `networkAccess` | 外部沙箱环境 |
| `WorkspaceWrite` | `writableRoots`, `readOnlyAccess`, `networkAccess`, `excludeTmpdirEnvVar`, `excludeSlashTmp` | 工作区可写 |

### 子类型定义

**ReadOnlyAccess**（行 1225-1239）：
```rust
pub enum ReadOnlyAccess {
    Restricted {
        include_platform_defaults: bool,
        readable_roots: Vec<AbsolutePathBuf>,
    },
    FullAccess,
}
```

**NetworkAccess**（行 1216-1222）：
```rust
pub enum NetworkAccess {
    Restricted,
    Enabled,
}
```

### 与核心类型的映射

**To Core**（行 1308-1342）：
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
            // ... 其他变体
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 1275-1305
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxPolicy.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/TurnStartParams.json`

### 使用位置
- **TurnStartParams**：`v2.rs` 行 3844 - 回合启动参数
- **Linux Sandbox**：`linux-sandbox/src/` - 沙箱实现
- **Windows Sandbox**：`windows-sandbox-rs/src/` - Windows 沙箱

### 相关类型
- `ReadOnlyAccess`：只读访问配置（行 1225-1239）
- `NetworkAccess`：网络访问配置（行 1216-1222）
- `SandboxMode`：高层沙箱模式抽象
- `CoreSandboxPolicy`：核心协议中的对应类型（`protocol/src/protocol.rs` 行 722）

## 依赖与外部交互

### 依赖项
- `ReadOnlyAccess`：只读访问类型
- `NetworkAccess`：网络访问类型
- `AbsolutePathBuf`：绝对路径类型
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreSandboxPolicy`（核心协议）：`protocol/src/protocol.rs`

### 下游使用
- `TurnStartParams`：回合启动时可覆盖沙箱策略
- `SandboxExecutor`：沙箱执行器
- `Landlock`, `Bubblewrap`：Linux 沙箱实现

### 协议集成
- 通过 `turn/start` 的 `sandboxPolicy` 参数指定
- 转换为 `CoreSandboxPolicy` 后传递给执行层

## 风险、边界与改进建议

### 潜在风险
1. **配置复杂性**：相比 `SandboxMode`，配置更复杂，容易出错
2. **安全漏洞**：不当配置可能导致沙箱绕过
3. **性能开销**：复杂的策略检查可能影响性能
4. **平台差异**：不同平台的策略实现可能不一致

### 边界情况
1. **路径冲突**：`writableRoots` 和 `readableRoots` 重叠
2. **循环依赖**：策略配置中的循环引用
3. **无效路径**：指向不存在位置的根目录
4. **权限竞争**：多个策略同时应用时的优先级

### 改进建议
1. **验证增强**：
   - 添加策略配置验证
   - 检查路径冲突和有效性
   - 验证策略一致性

2. **配置简化**：
   ```rust
   pub struct SandboxPolicyTemplate {
       pub name: String,
       pub description: String,
       pub policy: SandboxPolicy,
   }
   ```

3. **可视化工具**：
   - 提供策略可视化界面
   - 显示策略影响范围
   - 提供策略对比功能

4. **审计和监控**：
   - 记录策略变更历史
   - 监控策略违反尝试
   - 提供策略使用统计

5. **自动化策略**：
   - 基于代码分析自动推荐策略
   - 学习用户行为优化策略
   - 实现策略自适应调整
