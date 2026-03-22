# config_requirements.rs 研究文档

## 场景与职责

`config_requirements.rs` 是 Codex 配置系统的**核心需求定义与约束模块**，负责：

1. **需求来源追踪**：记录每个配置项的来源（MDM、云端、系统文件、用户文件等）
2. **配置约束系统**：定义并强制执行配置值的允许范围（如允许的沙箱模式、审批策略等）
3. **多层配置合并**：支持从多个来源合并配置，处理优先级冲突
4. **TOML 序列化/反序列化**：定义配置文件的 Rust 数据结构

### 在架构中的位置
```
配置加载流程：
TOML/MDM/云端 ──> ConfigRequirementsToml ──> ConfigRequirementsWithSources ──> ConfigRequirements
                                                    │
                                                    v
                                            Constrained<T> (约束验证)
```

## 功能点目的

### 1. 需求来源追踪 (`RequirementSource`)
```rust
pub enum RequirementSource {
    Unknown,
    MdmManagedPreferences { domain: String, key: String },
    CloudRequirements,
    SystemRequirementsToml { file: AbsolutePathBuf },
    LegacyManagedConfigTomlFromFile { file: AbsolutePathBuf },
    LegacyManagedConfigTomlFromMdm,
}
```

**目的**：
- 为每个配置项提供可追溯的来源信息
- 在配置冲突时，根据来源优先级决定胜出者
- 在错误消息中显示配置来源，帮助用户定位问题

### 2. 带约束的配置值 (`ConstrainedWithSource<T>`)
```rust
pub struct ConstrainedWithSource<T> {
    pub value: Constrained<T>,  // 约束包装器
    pub source: Option<RequirementSource>,  // 来源信息
}
```

**目的**：
- 将配置值与约束验证器绑定
- 在运行时验证配置变更是否合法
- 保留配置来源用于错误报告

### 3. 配置需求结构 (`ConfigRequirements`)
```rust
pub struct ConfigRequirements {
    pub approval_policy: ConstrainedWithSource<AskForApproval>,
    pub sandbox_policy: ConstrainedWithSource<SandboxPolicy>,
    pub web_search_mode: ConstrainedWithSource<WebSearchMode>,
    pub feature_requirements: Option<Sourced<FeatureRequirementsToml>>,
    pub mcp_servers: Option<Sourced<BTreeMap<String, McpServerRequirement>>>,
    pub exec_policy: Option<Sourced<RequirementsExecPolicy>>,
    pub enforce_residency: ConstrainedWithSource<Option<ResidencyRequirement>>,
    pub network: Option<Sourced<NetworkConstraints>>,
}
```

**目的**：
- 定义系统支持的所有可约束配置项
- 提供默认值（如沙箱默认为 ReadOnly）
- 支持可选功能（如 MCP 服务器、网络约束）

### 4. TOML 配置结构 (`ConfigRequirementsToml`)
```rust
pub struct ConfigRequirementsToml {
    pub allowed_approval_policies: Option<Vec<AskForApproval>>,
    pub allowed_sandbox_modes: Option<Vec<SandboxModeRequirement>>,
    pub allowed_web_search_modes: Option<Vec<WebSearchModeRequirement>>,
    pub feature_requirements: Option<FeatureRequirementsToml>,
    pub mcp_servers: Option<BTreeMap<String, McpServerRequirement>>,
    pub apps: Option<AppsRequirementsToml>,
    pub rules: Option<RequirementsExecPolicyToml>,
    pub enforce_residency: Option<ResidencyRequirement>,
    pub network: Option<NetworkRequirementsToml>,
    pub guardian_developer_instructions: Option<String>,
}
```

**目的**：
- 定义 `requirements.toml` 文件的结构
- 支持 serde 反序列化
- 与内部 `ConfigRequirements` 分离，支持转换和验证

### 5. 多层配置合并 (`ConfigRequirementsWithSources`)
```rust
pub struct ConfigRequirementsWithSources {
    pub allowed_approval_policies: Option<Sourced<Vec<AskForApproval>>>,
    // ... 其他字段
}
```

**目的**：
- 收集来自多个来源的配置
- 实现 `merge_unset_fields` 方法，按优先级合并
- 支持应用级别的启用/禁用配置 (`apps`)

## 具体技术实现

### 关键数据结构关系

```
ConfigRequirementsToml (原始 TOML)
         │
         ▼
ConfigRequirementsWithSources (带来源的聚合)
         │ merge_unset_fields()
         ▼
ConfigRequirements (带约束的运行时表示)
         │
         ▼
ConstrainedWithSource<T> ──> Constrained<T> (约束验证)
```

### 约束验证机制

```rust
impl TryFrom<ConfigRequirementsWithSources> for ConfigRequirements {
    type Error = ConstraintError;
    
    fn try_from(toml: ConfigRequirementsWithSources) -> Result<Self, Self::Error> {
        // 1. 处理 approval_policy
        let approval_policy = match allowed_approval_policies {
            Some(Sourced { value: policies, source }) => {
                let initial_value = policies.first().copied().unwrap();
                let constrained = Constrained::new(initial_value, move |candidate| {
                    if policies.contains(candidate) { Ok(()) }
                    else { Err(ConstraintError::InvalidValue { ... }) }
                })?;
                ConstrainedWithSource::new(constrained, Some(source))
            }
            None => ConstrainedWithSource::new(
                Constrained::allow_any_from_default(), None
            ),
        };
        // ... 类似处理其他字段
    }
}
```

### 应用启用/禁用合并逻辑

```rust
pub(crate) fn merge_enablement_settings_descending(
    base: &mut AppsRequirementsToml,
    incoming: AppsRequirementsToml,
) {
    for (app_id, incoming_requirement) in incoming.apps {
        let base_requirement = base.apps.entry(app_id).or_default();
        let higher_precedence = base_requirement.enabled;
        let lower_precedence = incoming_requirement.enabled;
        // 任一来源禁用即禁用，都启用才启用
        base_requirement.enabled = 
            if higher_precedence == Some(false) || lower_precedence == Some(false) {
                Some(false)
            } else {
                higher_precedence.or(lower_precedence)
            };
    }
}
```

### 沙箱模式映射

```rust
pub enum SandboxModeRequirement {
    #[serde(rename = "read-only")]
    ReadOnly,
    #[serde(rename = "workspace-write")]
    WorkspaceWrite,
    #[serde(rename = "danger-full-access")]
    DangerFullAccess,
    #[serde(rename = "external-sandbox")]
    ExternalSandbox,
}
```

**关键约束**：`ReadOnly` 必须始终包含在允许列表中，否则返回错误。

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/config/src/config_requirements.rs` (1623 行)

### 直接依赖
| 依赖 | 路径 | 用途 |
|------|------|------|
| `Constrained` | `codex-rs/config/src/constraint.rs` | 约束验证核心 |
| `ConstraintError` | `codex-rs/config/src/constraint.rs` | 错误类型 |
| `RequirementsExecPolicy` | `codex-rs/config/src/requirements_exec_policy.rs` | 执行策略 |
| `SandboxPolicy` | `codex-rs/protocol/src/protocol.rs` | 沙箱策略 |
| `AskForApproval` | `codex-rs/protocol/src/protocol.rs` | 审批模式 |
| `WebSearchMode` | `codex-rs/protocol/src/config_types.rs` | 搜索模式 |
| `AbsolutePathBuf` | `codex-rs/utils/absolute-path/src/lib.rs` | 绝对路径 |

### 调用方
- `codex-rs/core/src/config_loader/mod.rs` - 配置加载器
- `codex-rs/core/src/config/mod.rs` - 配置服务
- `codex-rs/core/src/config/service.rs` - 配置服务实现
- `codex-rs/tui_app_server/src/debug_config.rs` - 调试配置

## 依赖与外部交互

### 外部 Crate
- `serde` / `toml`：TOML 序列化
- `codex_protocol`：协议类型定义
- `codex_execpolicy`：执行策略
- `codex_utils_absolute_path`：路径处理

### 内部模块
- `constraint.rs`：约束系统
- `requirements_exec_policy.rs`：执行策略规则
- `state.rs`：配置层状态

### 协议/接口
- TOML 配置文件格式（`requirements.toml`）
- MDM 托管配置（macOS/iOS）
- 云端配置 API

## 风险、边界与改进建议

### 潜在风险

1. **复杂合并逻辑**：
   - `merge_unset_fields` 使用宏实现，难以调试
   - 新增字段时需要手动更新宏，容易遗漏

2. **默认值硬编码**：
   - 沙箱默认 `ReadOnly`，审批默认 `UnlessTrusted`
   - 这些默认值分散在代码中，难以统一管理

3. **错误消息质量**：
   - 某些错误消息包含 `Debug` 格式的值，可读性较差
   - 例如：`allowed: "[ReadOnly, WorkspaceWrite]"`

### 边界条件

1. **空列表处理**：
   ```rust
   // allowed_sandbox_modes = [] 会导致错误
   // 因为必须包含 ReadOnly
   ```

2. **优先级冲突**：
   - 系统配置 vs 用户配置 vs 项目配置
   - MDM 配置通常具有最高优先级

3. **向后兼容性**：
   - 支持 `features` 和 `feature_requirements` 别名
   - 遗留的 `managed_config.toml` 格式

### 改进建议

1. **配置验证器**：
   ```rust
   // 建议：添加独立的验证阶段
   pub fn validate(&self) -> Result<(), Vec<ValidationError>> {
       // 检查必填字段、互斥配置等
   }
   ```

2. **默认值集中管理**：
   ```rust
   // 建议：定义 Defaults 常量
   pub mod defaults {
       pub const DEFAULT_SANDBOX_MODE: SandboxMode = SandboxMode::ReadOnly;
       pub const DEFAULT_APPROVAL_POLICY: AskForApproval = AskForApproval::UnlessTrusted;
   }
   ```

3. **更好的错误消息**：
   ```rust
   // 建议：使用 Display 而非 Debug
   allowed: policies.iter().map(|p| p.to_string()).join(", ")
   ```

4. **配置 Schema 文档**：
   - 当前依赖代码和测试了解配置格式
   - 建议生成 JSON Schema 或文档

5. **性能优化**：
   - `policy_fingerprint` 每次比较都重新计算
   - 可缓存指纹结果

### 测试覆盖

当前测试（约 50 个测试用例）：
- 合并逻辑测试（`merge_unset_fields_*`）
- 反序列化测试（`deserialize_*`）
- 约束验证测试（`constraint_error_*`）
- 应用启用/禁用测试（`merge_enablement_*`）

建议补充：
- 模糊测试（Fuzzing）配置解析
- 性能基准测试（大规模配置合并）
- 边界条件测试（空值、极大值）
