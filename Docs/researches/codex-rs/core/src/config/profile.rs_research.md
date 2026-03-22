# ConfigProfile 研究文档

## 场景与职责

`profile.rs` 定义了 Codex 的配置 Profile 结构 `ConfigProfile`，它是用户在 `config.toml` 中定义的配置单元。一个 Profile 包含模型选择、审批策略、沙箱模式、个性化设置等常见配置选项。

主要使用场景：
- **多环境配置**：用户可定义 `default`、`work`、`personal` 等不同 profile
- **快速切换**：通过 CLI 或 TUI 快速切换不同配置组合
- **配置继承**：基础配置与 profile 特定配置的合并
- **API 暴露**：将内部配置转换为 App Server 协议类型

## 功能点目的

### 1. 配置 Profile 定义 (`ConfigProfile`)
集中定义用户可配置的所有选项：
- **模型相关**：model, model_provider, service_tier, reasoning_effort
- **行为策略**：approval_policy, sandbox_mode, personality
- **功能开关**：tools_view_image, include_apply_patch_tool
- **路径配置**：model_instructions_file, js_repl_node_path, zsh_path
- **实验性功能**：experimental_use_unified_exec_tool, features

### 2. 协议转换 (`From<ConfigProfile> for codex_app_server_protocol::Profile`)
将内部配置类型转换为 API 暴露类型，用于：
- App Server 协议通信
- 配置读取 API 响应

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct ConfigProfile {
    // 模型选择
    pub model: Option<String>,
    pub service_tier: Option<ServiceTier>,
    pub model_provider: Option<String>,
    
    // 审批与审查
    pub approval_policy: Option<AskForApproval>,
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    
    // 沙箱与安全
    pub sandbox_mode: Option<SandboxMode>,
    
    // 模型行为
    pub model_reasoning_effort: Option<ReasoningEffort>,
    pub plan_mode_reasoning_effort: Option<ReasoningEffort>,
    pub model_reasoning_summary: Option<ReasoningSummary>,
    pub model_verbosity: Option<Verbosity>,
    pub personality: Option<Personality>,
    
    // 路径配置
    pub model_catalog_json: Option<AbsolutePathBuf>,
    pub model_instructions_file: Option<AbsolutePathBuf>,
    pub js_repl_node_path: Option<AbsolutePathBuf>,
    pub js_repl_node_module_dirs: Option<Vec<AbsolutePathBuf>>,
    pub zsh_path: Option<AbsolutePathBuf>,
    
    // 工具配置
    pub include_apply_patch_tool: Option<bool>,
    pub experimental_use_unified_exec_tool: Option<bool>,
    pub experimental_use_freeform_apply_patch: Option<bool>,
    pub tools_view_image: Option<bool>,
    pub tools: Option<ToolsToml>,
    
    // 其他功能
    pub web_search: Option<WebSearchMode>,
    pub analytics: Option<AnalyticsConfigToml>,
    pub windows: Option<WindowsToml>,
    pub features: Option<FeaturesToml>,
    pub oss_provider: Option<String>,
    
    // 已弃用
    #[schemars(skip)]
    pub experimental_instructions_file: Option<AbsolutePathBuf>,
}
```

### 协议转换实现

```rust
impl From<ConfigProfile> for codex_app_server_protocol::Profile {
    fn from(config_profile: ConfigProfile) -> Self {
        Self {
            model: config_profile.model,
            model_provider: config_profile.model_provider,
            approval_policy: config_profile.approval_policy,
            model_reasoning_effort: config_profile.model_reasoning_effort,
            model_reasoning_summary: config_profile.model_reasoning_summary,
            model_verbosity: config_profile.model_verbosity,
            chatgpt_base_url: config_profile.chatgpt_base_url,
        }
    }
}
```

**注意**：协议转换仅包含部分字段，其他字段在内部使用或通过其他 API 暴露。

## 关键代码路径与文件引用

### 本文件内容

| 定义 | 行号 | 描述 |
|------|------|------|
| `ConfigProfile` struct | 20-65 | 配置 Profile 结构定义 |
| `From<ConfigProfile>` impl | 67-79 | 协议类型转换实现 |

### 调用方

| 文件 | 使用方式 | 用途 |
|------|---------|------|
| `codex-rs/core/src/config/mod.rs` | `ConfigBuilder` | 构建配置时解析 profile |
| `codex-rs/core/src/config/types.rs` | 嵌套使用 | `ConfigToml` 包含 profiles 字段 |
| `codex-rs/app-server/src/config_api.rs` | API 响应 | 返回 profile 配置 |

### 依赖类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `AskForApproval` | `crate::protocol` | 审批策略 |
| `ApprovalsReviewer` | `crate::config::types` | 审批审查者 |
| `Personality` | `codex_protocol::config_types` | 个性化设置 |
| `ReasoningEffort` | `codex_protocol::openai_models` | 推理努力程度 |
| `SandboxMode` | `codex_protocol::config_types` | 沙箱模式 |
| `ServiceTier` | `codex_protocol::config_types` | 服务层级 |
| `Verbosity` | `codex_protocol::config_types` | 输出详细程度 |
| `WebSearchMode` | `codex_protocol::config_types` | 网页搜索模式 |
| `AbsolutePathBuf` | `codex_utils_absolute_path` | 绝对路径类型 |

## 依赖与外部交互

### 配置层级

```
config.toml
├── [profile.default]          ← ConfigProfile
│   ├── model = "gpt-5"
│   ├── approval_policy = "on-request"
│   └── ...
├── [profile.work]             ← ConfigProfile
│   ├── model = "gpt-5"
│   ├── approval_policy = "never"
│   └── ...
└── ...
```

### 配置解析流程

```
TOML 配置文件
      ↓
serde::Deserialize<ConfigToml>
      ↓
ConfigToml.profiles: BTreeMap<String, ConfigProfile>
      ↓
ConfigBuilder 选择当前激活的 profile
      ↓
ConfigProfile 字段应用到 Config
      ↓
From<ConfigProfile> for codex_app_server_protocol::Profile
      ↓
API 响应 / 内部使用
```

## 风险、边界与改进建议

### 已知问题

1. **字段冗余**
   - `experimental_instructions_file` 已弃用，但仍保留在结构中
   - 建议：考虑在后续版本中移除

2. **协议转换字段不完整**
   - 仅 6 个字段被转换到协议类型
   - 其他字段需要通过其他方式暴露
   - 代码位置：第 67-79 行

3. **缺少验证逻辑**
   - 结构本身不包含字段验证
   - 验证分散在 `ConfigBuilder` 各处

### 边界情况

1. **空 Profile**
   - 所有字段为 `Option`，空 profile 是合法的
   - 依赖默认值处理

2. **路径字段**
   - 使用 `AbsolutePathBuf` 确保路径绝对性
   - 但序列化时不验证路径存在性

3. **Feature 覆盖**
   - `features` 字段允许 profile 级别的功能开关
   - 与全局 `features` 的合并逻辑在别处处理

### 改进建议

1. **添加验证方法**
   ```rust
   impl ConfigProfile {
       pub fn validate(&self) -> Result<(), Vec<String>> {
           let mut errors = Vec::new();
           
           // 验证 model_provider 引用存在的 provider
           if let Some(ref provider) = self.model_provider {
               // 验证逻辑
           }
           
           // 验证路径存在性（如需要）
           if let Some(ref path) = self.model_instructions_file {
               if !path.exists() {
                   errors.push(format!("model_instructions_file not found: {}", path));
               }
           }
           
           if errors.is_empty() { Ok(()) } else { Err(errors) }
       }
   }
   ```

2. **完善协议转换**
   ```rust
   // 考虑添加更多字段到协议类型
   impl From<ConfigProfile> for codex_app_server_protocol::Profile {
       fn from(config_profile: ConfigProfile) -> Self {
           Self {
               // 现有字段...
               sandbox_mode: config_profile.sandbox_mode,
               personality: config_profile.personality,
               tools: config_profile.tools.map(|t| t.into()),
               // ...
           }
       }
   }
   ```

3. **文档生成**
   ```rust
   // 使用 schemars 生成 JSON Schema 时添加字段说明
   #[derive(..., JsonSchema)]
   #[schemars(description = "User-configurable profile for Codex")]
   pub struct ConfigProfile {
       /// The model identifier to use for this profile
       pub model: Option<String>,
       
       /// When to ask for approval before executing commands
       pub approval_policy: Option<AskForApproval>,
       
       // ...
   }
   ```

4. **Profile 继承**
   ```rust
   pub struct ConfigProfile {
       // 现有字段...
       
       /// Inherit settings from another profile
       pub extends: Option<String>,
   }
   
   impl ConfigProfile {
       pub fn merge_with_base(base: &ConfigProfile, child: &ConfigProfile) -> ConfigProfile {
           // 合并逻辑：child 非 None 字段覆盖 base
       }
   }
   ```

5. **测试覆盖**
   - 当前无专门测试文件
   - 建议创建 `profile_tests.rs` 测试：
     - 序列化/反序列化
     - 协议转换
     - 字段验证

### 相关配置类型关系

```
ConfigToml
├── profiles: BTreeMap<String, ConfigProfile>
├── default_profile: Option<String>
└── ...

ConfigProfile
├── model: Option<String>
├── approval_policy: Option<AskForApproval>
├── sandbox_mode: Option<SandboxMode>
├── features: Option<FeaturesToml>
└── ...

// 与 PermissionsToml 的关系
// Profile 可引用 PermissionProfile
```
