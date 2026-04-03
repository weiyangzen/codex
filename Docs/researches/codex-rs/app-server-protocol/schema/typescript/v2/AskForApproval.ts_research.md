# AskForApproval 类型研究文档

## 1. 场景与职责

### 使用场景
`AskForApproval` 是 Codex 系统中用于控制命令执行审批策略的核心类型。它定义了何时需要向用户请求执行权限，是 Codex 安全模型的关键组成部分。该类型在 App-Server Protocol v2 中用于配置审批策略，影响 shell 命令执行、工具调用等操作的权限控制。

### 主要职责
- **审批策略定义**：定义何时需要用户批准执行操作
- **安全级别控制**：提供从严格到宽松的不同安全级别
- **细粒度控制**：支持按操作类型单独配置审批策略
- **用户体验优化**：在安全和便利之间提供可配置的平衡

### 使用场景示例
```typescript
// 配置示例
const config: Config = {
    approvalPolicy: "on-request",  // 模型决定何时请求批准
};

// 严格配置（不信任任何命令）
const strictConfig: Config = {
    approvalPolicy: "untrusted",  // 只有已知安全的命令自动批准
};

// 细粒度配置
const granularConfig: Config = {
    approvalPolicy: {
        granular: {
            sandbox_approval: true,      // 需要沙箱审批
            rules: true,                 // 需要规则提示
            skill_approval: false,       // 不需要技能审批
            request_permissions: true,   // 需要权限请求
            mcp_elicitations: false,     // 不需要 MCP 提示
        }
    }
};
```

---

## 2. 功能点目的

### 2.1 预设策略模式

#### `"untrusted"` - 不信任模式
- **目的**：最高安全级别，仅自动批准已知安全的只读命令
- **行为**：
  - 只有被 `is_safe_command()` 判定为安全的命令自动批准
  - 所有其他命令都需要用户批准
- **适用场景**：敏感环境、不信任的代码库、高风险操作

#### `"on-failure"` - 失败时请求（已弃用）
- **目的**：所有命令自动批准，但失败时请求无沙箱执行
- **状态**：DEPRECATED
- **替代方案**：使用 `"on-request"` 或 `"never"`
- **警告**：此模式存在安全风险，不建议使用

#### `"on-request"` - 按需请求（默认）
- **目的**：由模型决定何时需要用户批准
- **行为**：模型根据上下文判断是否需要用户确认
- **适用场景**：一般使用场景，平衡安全和便利
- **默认性**：这是默认的审批策略

#### `"never"` - 从不请求
- **目的**：完全自动执行，不请求用户批准
- **行为**：所有命令自动批准
- **适用场景**：
  - 完全自动化的 CI/CD 场景
  - 沙箱环境
  - 用户明确信任的环境
- **警告**：使用此模式需确保有充分的沙箱保护

### 2.2 细粒度控制模式（Granular）
- **目的**：为不同类型的操作提供独立的审批控制
- **实验性**：标记为 `#[experimental("askForApproval.granular")]`
- **优势**：精确控制哪些操作需要审批

#### 细粒度字段说明
| 字段 | 类型 | 说明 |
|------|------|------|
| `sandbox_approval` | `boolean` | 是否允许 shell 命令审批请求，包括 `with_additional_permissions` 和 `require_escalated` 请求 |
| `rules` | `boolean` | 是否允许由 execpolicy `prompt` 规则触发的提示 |
| `skill_approval` | `boolean` | 是否允许由技能脚本执行触发的审批提示 |
| `request_permissions` | `boolean` | 是否允许由 `request_permissions` 工具触发的提示 |
| `mcp_elicitations` | `boolean` | 是否允许 MCP 提示 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
export type AskForApproval = 
    | "untrusted" 
    | "on-failure" 
    | "on-request" 
    | { 
        "granular": { 
            sandbox_approval: boolean, 
            rules: boolean, 
            skill_approval: boolean, 
            request_permissions: boolean, 
            mcp_elicitations: boolean, 
        } 
    } 
    | "never";
```

### 3.2 Rust 源类型定义
```rust
#[derive(
    Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS, ExperimentalApi,
)]
#[serde(rename_all = "kebab-case")]
#[ts(rename_all = "kebab-case", export_to = "v2/")]
pub enum AskForApproval {
    #[serde(rename = "untrusted")]
    #[ts(rename = "untrusted")]
    UnlessTrusted,
    OnFailure,
    OnRequest,
    #[experimental("askForApproval.granular")]
    Granular {
        sandbox_approval: bool,
        rules: bool,
        #[serde(default)]
        skill_approval: bool,
        #[serde(default)]
        request_permissions: bool,
        mcp_elicitations: bool,
    },
    Never,
}
```

### 3.3 核心协议定义
```rust
// codex-rs/protocol/src/protocol.rs:558-606
pub enum AskForApproval {
    /// 只有已知安全的命令自动批准
    #[serde(rename = "untrusted")]
    #[strum(serialize = "untrusted")]
    UnlessTrusted,

    /// DEPRECATED: 所有命令自动批准，失败时请求无沙箱执行
    OnFailure,

    /// 模型决定何时请求用户批准（默认）
    #[default]
    OnRequest,

    /// 细粒度控制
    Granular(GranularApprovalConfig),

    /// 从不请求批准
    Never,
}

pub struct GranularApprovalConfig {
    /// 是否允许 shell 命令审批请求
    pub sandbox_approval: bool,
    /// 是否允许 execpolicy `prompt` 规则触发的提示
    pub rules: bool,
    /// 是否允许技能脚本执行触发的审批提示
    #[serde(default)]
    pub skill_approval: bool,
    /// 是否允许 `request_permissions` 工具触发的提示
    #[serde(default)]
    pub request_permissions: bool,
    /// 是否允许 MCP 提示
    pub mcp_elicitations: bool,
}
```

### 3.4 序列化特性
| 特性 | 说明 |
|------|------|
| `rename_all = "kebab-case"` | 变体使用 kebab-case（如 `"on-request"`） |
| `#[serde(rename = "untrusted")]` | `UnlessTrusted` 映射为 `"untrusted"` |
| `#[serde(default)]` | `skill_approval` 和 `request_permissions` 默认为 `false` |
| `ExperimentalApi` | `Granular` 变体标记为实验性 |

### 3.5 类型转换
```rust
impl AskForApproval {
    pub fn to_core(self) -> CoreAskForApproval {
        match self {
            AskForApproval::UnlessTrusted => CoreAskForApproval::UnlessTrusted,
            AskForApproval::OnFailure => CoreAskForApproval::OnFailure,
            AskForApproval::OnRequest => CoreAskForApproval::OnRequest,
            AskForApproval::Granular { ... } => CoreAskForApproval::Granular(...),
            AskForApproval::Never => CoreAskForApproval::Never,
        }
    }
}

impl From<CoreAskForApproval> for AskForApproval {
    fn from(value: CoreAskForApproval) -> Self {
        // 反向转换
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:201-265` | App-Server v2 定义 |
| protocol.rs | `codex-rs/protocol/src/protocol.rs:558-606` | 核心协议定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| AskForApproval.ts | `codex-rs/app-server-protocol/schema/typescript/v2/AskForApproval.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/AskForApproval.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| Config | `v2.rs:699` | 配置中的审批策略 |
| ThreadStartParams | `v2.rs:2471` | 线程启动时的审批策略 |
| ThreadResumeParams | `v2.rs:2537` | 线程恢复时的审批策略 |
| ThreadForkParams | `v2.rs:2591` | 线程分叉时的审批策略 |
| TurnStartParams | 相关文件 | 回合开始时的审批策略 |

### 4.4 代码引用链
```
Config::approval_policy (Option<AskForApproval>)
    ├── UnlessTrusted  →  仅安全命令自动批准
    ├── OnFailure      →  已弃用
    ├── OnRequest      →  模型决定（默认）
    ├── Granular       →  细粒度控制（实验性）
    │       ├── sandbox_approval: bool
    │       ├── rules: bool
    │       ├── skill_approval: bool
    │       ├── request_permissions: bool
    │       └── mcp_elicitations: bool
    └── Never          →  从不请求
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖
`AskForApproval` 是基础枚举类型，不依赖其他自定义类型（除核心协议外）。

### 5.2 上游依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `ts-rs` | Rust crate | 生成 TypeScript 类型 |
| `schemars` | Rust crate | 生成 JSON Schema |
| `serde` | Rust crate | 序列化/反序列化 |
| `strum` | Rust crate | 字符串枚举转换 |
| `ExperimentalApi` | 内部宏 | 实验性 API 标记 |

### 5.3 外部交互
| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| Config API | `config/read`, `config/write` | 配置的读写操作 |
| Thread API | `thread/start`, `thread/resume` | 线程生命周期中的审批策略 |
| Safety System | 内部调用 | 安全系统根据此策略决定是否请求批准 |
| Exec Policy | 内部调用 | 执行策略根据此策略应用规则 |
| MCP System | 内部调用 | MCP 提示控制 |

### 5.4 安全系统集成
```
AskForApproval
    ↓
Safety / Guardian System
    ├─ UnlessTrusted → is_safe_command() 检查
    ├─ OnRequest → 模型判断
    ├─ Granular → 按类型检查
    │   ├─ sandbox_approval → Shell 命令审批
    │   ├─ rules → ExecPolicy 规则
    │   ├─ skill_approval → 技能脚本
    │   ├─ request_permissions → 权限请求工具
    │   └── mcp_elicitations → MCP 提示
    └── Never → 自动批准
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：`"never"` 模式的安全隐患
- **问题**：`"never"` 模式完全禁用审批，可能导致未授权操作
- **影响**：在不受信任的环境中可能导致数据丢失或安全漏洞
- **缓解**：
  - 仅在充分沙箱保护的环境中使用
  - 提供明确的安全警告
  - 考虑添加使用确认

#### 风险 2：`"on-failure"` 已弃用但仍可用
- **问题**：`"on-failure"` 存在安全风险但仍在枚举中
- **影响**：用户可能无意中使用不安全的策略
- **缓解**：
  - 在文档中明确标记为弃用
  - 考虑在未来版本中移除
  - 使用时发出警告

#### 风险 3：细粒度配置的复杂性
- **问题**：`Granular` 配置复杂，用户可能配置错误
- **影响**：预期需要审批的操作被自动批准
- **缓解**：
  - 提供配置验证
  - 提供预设配置模板
  - 添加配置解释工具

#### 风险 4：实验性 API 不稳定
- **问题**：`Granular` 变体标记为实验性
- **影响**：API 可能在未来版本中变更
- **缓解**：
  - 客户端做好版本兼容
  - 关注协议更新

### 6.2 边界情况

| 场景 | 行为 | 说明 |
|------|------|------|
| `Granular` 中所有字段为 `false` | 等同于 `"never"` | 无审批请求 |
| `Granular` 中所有字段为 `true` | 最严格模式 | 所有操作都需审批 |
| 配置为 `null` | 使用默认值 `"on-request"` | 遵循配置层级 |
| 无效字符串值 | 反序列化错误 | 严格的枚举验证 |

### 6.3 改进建议

#### 建议 1：移除或隔离 `"on-failure"`
```rust
// 选项 1：完全移除
pub enum AskForApproval {
    UnlessTrusted,
    // OnFailure,  // 已移除
    OnRequest,
    Granular { ... },
    Never,
}

// 选项 2：标记为废弃并警告
#[deprecated(since = "2.0", note = "使用 OnRequest 或 Never 替代")]
OnFailure,
```

#### 建议 2：添加配置验证
```rust
impl AskForApproval {
    pub fn validate(&self) -> Result<(), ValidationError> {
        match self {
            AskForApproval::Never => {
                warn!("使用 'never' 审批策略，确保环境已充分沙箱保护");
            }
            AskForApproval::Granular { sandbox_approval: false, rules: false, .. } => {
                warn!("细粒度配置禁用了主要审批机制");
            }
            _ => {}
        }
        Ok(())
    }
}
```

#### 建议 3：预设配置模板
```rust
pub enum ApprovalPreset {
    /// 最高安全：只有只读命令自动批准
    Strict,
    /// 平衡：模型决定
    Balanced,
    /// 仅沙箱：只在需要脱离沙箱时审批
    SandboxOnly,
    /// 完全自动：需要充分沙箱保护
    FullyAutomatic,
}

impl From<ApprovalPreset> for AskForApproval {
    fn from(preset: ApprovalPreset) -> Self {
        match preset {
            ApprovalPreset::Strict => AskForApproval::UnlessTrusted,
            ApprovalPreset::Balanced => AskForApproval::OnRequest,
            ApprovalPreset::SandboxOnly => AskForApproval::Granular {
                sandbox_approval: true,
                rules: false,
                skill_approval: false,
                request_permissions: false,
                mcp_elicitations: false,
            },
            ApprovalPreset::FullyAutomatic => AskForApproval::Never,
        }
    }
}
```

#### 建议 4：增强细粒度配置
```rust
pub struct GranularApprovalConfig {
    // 现有字段
    pub sandbox_approval: bool,
    pub rules: bool,
    pub skill_approval: bool,
    pub request_permissions: bool,
    pub mcp_elicitations: bool,
    
    // 新增：按命令类型
    pub read_commands: ApprovalMode,      // 只读命令
    pub write_commands: ApprovalMode,     // 写操作命令
    pub network_commands: ApprovalMode,   // 网络相关命令
    pub destructive_commands: ApprovalMode, // 破坏性命令
}

pub enum ApprovalMode {
    Auto,      // 自动批准
    Prompt,    // 提示用户
    Deny,      // 拒绝执行
}
```

#### 建议 5：审批策略审计日志
```rust
pub struct ApprovalDecision {
    pub timestamp: i64,
    pub policy: AskForApproval,
    pub operation: OperationType,
    pub decision: Decision,
    pub reason: String,
}

pub enum Decision {
    AutoApproved,
    Prompted,  // 请求用户
    Denied,    // 拒绝（基于策略）
}
```

### 6.4 实验性状态说明
- `Granular` 变体标记为 `#[experimental("askForApproval.granular")]`
- 根据 `AGENTS.md` 指南，实验性 API 使用 `#[experimental("...")]` 标记
- 建议在使用时注意：
  1. 实现版本检查
  2. 准备降级方案
  3. 关注协议更新
