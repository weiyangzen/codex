# 研究文档：openai.yaml

## 文件基本信息

- **目标文件**: `codex-rs/skills/src/assets/samples/openai-docs/agents/openai.yaml`
- **文件类型**: YAML 配置文件
- **所属技能**: openai-docs（OpenAI 文档查询技能）
- **技能类型**: 系统级 Skill（System Skill）
- **安装路径**: `$CODEX_HOME/skills/.system/openai-docs/`

---

## 1. 场景与职责

### 1.1 核心定位

`openai.yaml` 是 **openai-docs Skill** 的元数据配置文件，位于 `agents/` 子目录下。它是 Codex CLI 内置的三个系统级技能之一（另外两个是 `skill-creator` 和 `skill-installer`），专门用于：

1. **UI 展示配置**: 定义技能在 Codex 用户界面中的显示名称、描述、图标等视觉元素
2. **MCP 依赖声明**: 声明该技能依赖的外部 MCP（Model Context Protocol）服务器
3. **默认提示词**: 提供技能被触发时的默认上下文提示

### 1.2 使用场景

当用户在 Codex 中执行以下操作时，该配置文件被读取和处理：

| 场景 | 触发方式 | 配置作用 |
|------|----------|----------|
| 显式调用技能 | 用户输入 `$openai-docs` | 加载 `default_prompt` 作为上下文 |
| 隐式触发 | 用户询问 OpenAI 相关问题 | 根据 `interface` 配置显示技能信息 |
| 技能列表展示 | 查看可用技能 | 使用 `display_name`, `icon_small`, `icon_large` |
| MCP 依赖安装 | 首次使用技能时 | 根据 `dependencies` 自动安装 `openaiDeveloperDocs` |

### 1.3 在技能架构中的位置

```
openai-docs Skill 结构:
├── SKILL.md                    # 技能主文档（指令内容）
├── agents/
│   └── openai.yaml            # ← 本文件：UI 元数据 + MCP 依赖配置
├── assets/
│   ├── openai-small.svg       # 小图标（16x16 或 24x24）
│   └── openai.png             # 大图标（64x64 或更大）
├── references/
│   ├── latest-model.md        # 模型选择参考
│   ├── upgrading-to-gpt-5p4.md # GPT-5.4 升级指南
│   └── gpt-5p4-prompting-guide.md # Prompt 优化指南
└── LICENSE.txt                # Apache 2.0 许可证
```

---

## 2. 功能点目的

### 2.1 配置结构解析

```yaml
interface:
  display_name: "OpenAI Docs"                                    # UI 显示名称
  short_description: "Reference official OpenAI docs, including upgrade guidance"  # 简短描述
  icon_small: "./assets/openai-small.svg"                       # 小图标路径（相对路径）
  icon_large: "./assets/openai.png"                             # 大图标路径
  default_prompt: "Look up official OpenAI docs, load relevant GPT-5.4 upgrade references when applicable, and answer with concise, cited guidance."  # 默认提示词

dependencies:
  tools:
    - type: "mcp"                                               # 依赖类型：MCP 服务器
      value: "openaiDeveloperDocs"                              # MCP 服务器标识
      description: "OpenAI Developer Docs MCP server"           # 描述
      transport: "streamable_http"                              # 传输协议
      url: "https://developers.openai.com/mcp"                  # MCP 服务器 URL
```

### 2.2 各字段功能目的

#### 2.2.1 `interface` 部分

| 字段 | 类型 | 目的 | 使用位置 |
|------|------|------|----------|
| `display_name` | string | 技能在 UI 中的显示名称 | 技能列表、技能切换视图、技能弹窗 |
| `short_description` | string | 技能的简短描述（25-64 字符） | 技能列表、提示工具 |
| `icon_small` | path | 小图标路径，用于紧凑显示 | 技能芯片、列表项 |
| `icon_large` | path | 大图标路径，用于详细视图 | 技能详情页、弹窗 |
| `default_prompt` | string | 技能被触发时注入的默认提示 | 模型上下文 |

#### 2.2.2 `dependencies` 部分

| 字段 | 类型 | 目的 | 处理逻辑 |
|------|------|------|----------|
| `type` | string | 依赖类型标识 | 当前仅支持 `"mcp"` |
| `value` | string | MCP 服务器名称/标识 | 用于生成工具名称（如 `mcp__openaiDeveloperDocs__search_openai_docs`） |
| `description` | string | 依赖描述 | 用于日志和用户提示 |
| `transport` | string | 传输协议 | `"streamable_http"` 或 `"stdio"` |
| `url` | string | MCP 服务器 URL | Streamable HTTP 传输必需 |

### 2.3 功能流程

```
用户输入 "$openai-docs" 或询问 OpenAI 相关问题
           │
           ▼
┌─────────────────────┐
│ 技能管理系统 (SkillsManager) │
│  - 从 $CODEX_HOME/skills/.system/openai-docs/agents/openai.yaml 读取配置
└─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ 解析 openai.yaml    │
│  - 提取 interface 信息用于 UI 展示
│  - 提取 dependencies 用于 MCP 依赖检查
└─────────────────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
┌─────────┐  ┌─────────────────┐
│ UI 渲染  │  │ MCP 依赖检查     │
│ - 图标   │  │ - 检查 openaiDeveloperDocs 是否已安装
│ - 名称   │  │ - 如未安装，提示用户安装
│ - 描述   │  │ - 安装命令: codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp
└─────────┘  └─────────────────┘
           │
           ▼
┌─────────────────────┐
│ 技能注入 (SkillInjection) │
│  - 加载 SKILL.md 内容
│  - 注入 default_prompt 到模型上下文
└─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ MCP 工具调用         │
│  - mcp__openaiDeveloperDocs__search_openai_docs
│  - mcp__openaiDeveloperDocs__fetch_openai_doc
│  - mcp__openaiDeveloperDocs__list_openai_docs
└─────────────────────┘
```

---

## 3. 具体技术实现

### 3.1 配置文件加载流程

#### 3.1.1 系统技能安装

在 `codex-rs/skills/src/lib.rs` 中，系统技能在 Codex 启动时被安装：

```rust
// 编译时嵌入的技能目录
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");

pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // 1. 计算嵌入目录的指纹（用于缓存验证）
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    // 2. 如果指纹匹配，跳过安装
    if marker_matches(&marker_path, expected_fingerprint) {
        return Ok(());
    }
    
    // 3. 清理旧版本并写入新内容
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
    
    // 目标路径: $CODEX_HOME/skills/.system/openai-docs/agents/openai.yaml
}
```

#### 3.1.2 技能元数据加载

在 `codex-rs/core/src/skills/loader.rs` 中，`openai.yaml` 被解析为技能元数据：

```rust
const SKILLS_METADATA_DIR: &str = "agents";
const SKILLS_METADATA_FILENAME: &str = "openai.yaml";

fn load_skill_metadata(skill_path: &Path) -> LoadedSkillMetadata {
    let skill_dir = skill_path.parent()?;
    let metadata_path = skill_dir
        .join(SKILLS_METADATA_DIR)
        .join(SKILLS_METADATA_FILENAME);
    
    if !metadata_path.exists() {
        return LoadedSkillMetadata::default();
    }
    
    // 解析 YAML 为 SkillMetadataFile 结构
    let parsed: SkillMetadataFile = serde_yaml::from_str(&contents)?;
    
    // 提取 interface, dependencies, policy, permissions
    LoadedSkillMetadata {
        interface: resolve_interface(interface, skill_dir),
        dependencies: resolve_dependencies(dependencies),
        policy: resolve_policy(policy),
        permission_profile,
        managed_network_override,
    }
}
```

### 3.2 数据结构定义

#### 3.2.1 YAML 解析结构（loader.rs）

```rust
#[derive(Debug, Default, Deserialize)]
struct SkillMetadataFile {
    #[serde(default)]
    interface: Option<Interface>,
    #[serde(default)]
    dependencies: Option<Dependencies>,
    #[serde(default)]
    policy: Option<Policy>,
    #[serde(default)]
    permissions: Option<SkillPermissionProfile>,
}

#[derive(Debug, Default, Deserialize)]
struct Interface {
    display_name: Option<String>,
    short_description: Option<String>,
    icon_small: Option<PathBuf>,
    icon_large: Option<PathBuf>,
    brand_color: Option<String>,
    default_prompt: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct Dependencies {
    #[serde(default)]
    tools: Vec<DependencyTool>,
}

#[derive(Debug, Default, Deserialize)]
struct DependencyTool {
    #[serde(rename = "type")]
    kind: Option<String>,
    value: Option<String>,
    description: Option<String>,
    transport: Option<String>,
    command: Option<String>,
    url: Option<String>,
}
```

#### 3.2.2 内部模型定义（model.rs）

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillMetadata {
    pub name: String,                              // "openai-docs"
    pub description: String,                       // 来自 SKILL.md frontmatter
    pub short_description: Option<String>,         // 来自 openai.yaml
    pub interface: Option<SkillInterface>,         // 解析后的 interface
    pub dependencies: Option<SkillDependencies>,   // 解析后的 dependencies
    pub policy: Option<SkillPolicy>,
    pub permission_profile: Option<PermissionProfile>,
    pub managed_network_override: Option<SkillManagedNetworkOverride>,
    pub path_to_skills_md: PathBuf,
    pub scope: SkillScope,                         // System
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillInterface {
    pub display_name: Option<String>,              // "OpenAI Docs"
    pub short_description: Option<String>,         // "Reference official OpenAI docs..."
    pub icon_small: Option<PathBuf>,               // ./assets/openai-small.svg
    pub icon_large: Option<PathBuf>,               // ./assets/openai.png
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,            // 默认提示词
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillToolDependency {
    pub r#type: String,                            // "mcp"
    pub value: String,                             // "openaiDeveloperDocs"
    pub description: Option<String>,               // "OpenAI Developer Docs MCP server"
    pub transport: Option<String>,                 // "streamable_http"
    pub command: Option<String>,                   // None (stdio 类型使用)
    pub url: Option<String>,                       // "https://developers.openai.com/mcp"
}
```

### 3.3 MCP 依赖处理

在 `codex-rs/core/src/mcp/skill_dependencies.rs` 中处理 MCP 依赖：

```rust
pub(crate) fn collect_missing_mcp_dependencies(
    mentioned_skills: &[SkillMetadata],
    installed: &HashMap<String, McpServerConfig>,
) -> HashMap<String, McpServerConfig> {
    for skill in mentioned_skills {
        let Some(dependencies) = skill.dependencies.as_ref() else { continue };
        
        for tool in &dependencies.tools {
            if !tool.r#type.eq_ignore_ascii_case("mcp") {
                continue;
            }
            
            // 生成规范化的 MCP 键
            let dependency_key = canonical_mcp_dependency_key(tool)?;
            
            // 检查是否已安装
            if installed_keys.contains(&dependency_key) {
                continue;
            }
            
            // 转换为 McpServerConfig
            let config = mcp_dependency_to_server_config(tool)?;
            missing.insert(tool.value.clone(), config);
        }
    }
}

fn mcp_dependency_to_server_config(
    dependency: &SkillToolDependency,
) -> Result<McpServerConfig, String> {
    let transport = dependency.transport.as_deref().unwrap_or("streamable_http");
    
    if transport.eq_ignore_ascii_case("streamable_http") {
        let url = dependency.url.as_ref()
            .ok_or("missing url for streamable_http dependency")?;
        
        return Ok(McpServerConfig {
            transport: McpServerTransportConfig::StreamableHttp {
                url: url.clone(),
                bearer_token_env_var: None,
                http_headers: None,
                env_http_headers: None,
            },
            enabled: true,
            required: false,
            // ... 其他字段
        });
    }
    // ... stdio 类型处理
}
```

### 3.4 图标路径解析

```rust
fn resolve_asset_path(
    skill_dir: &Path,
    field: &'static str,
    path: Option<PathBuf>,
) -> Option<PathBuf> {
    let path = path?;
    
    // 必须是相对路径
    if path.is_absolute() {
        return None;
    }
    
    // 必须位于 assets/ 目录下
    let mut components = path.components();
    match components.next() {
        Some(Component::Normal(component)) if component == "assets" => {}
        _ => return None,
    }
    
    // 检查路径安全性（防止目录遍历）
    for component in components {
        match component {
            Component::ParentDir => return None,  // 拒绝 ".."
            _ => {}
        }
    }
    
    Some(skill_dir.join(path))
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心处理链

| 阶段 | 文件路径 | 关键函数/结构 |
|------|----------|---------------|
| **编译时嵌入** | `codex-rs/skills/src/lib.rs` | `SYSTEM_SKILLS_DIR`, `install_system_skills()` |
| **构建脚本** | `codex-rs/skills/build.rs` | `visit_dir()` - 监控文件变更 |
| **技能加载** | `codex-rs/core/src/skills/loader.rs` | `load_skill_metadata()`, `resolve_interface()`, `resolve_dependencies()` |
| **数据模型** | `codex-rs/core/src/skills/model.rs` | `SkillMetadata`, `SkillInterface`, `SkillDependencies`, `SkillToolDependency` |
| **MCP 依赖** | `codex-rs/core/src/mcp/skill_dependencies.rs` | `collect_missing_mcp_dependencies()`, `mcp_dependency_to_server_config()` |
| **技能管理** | `codex-rs/core/src/skills/manager.rs` | `SkillsManager::skills_for_config()` |
| **技能注入** | `codex-rs/core/src/skills/injection.rs` | `build_skill_injections()` |

### 4.2 相关测试文件

| 测试文件 | 测试内容 |
|----------|----------|
| `codex-rs/core/src/skills/loader_tests.rs` | 技能加载、YAML 解析、路径解析测试 |
| `codex-rs/core/src/mcp/skill_dependencies_tests.rs` | MCP 依赖收集、配置转换测试 |
| `codex-rs/core/src/skills/injection_tests.rs` | 技能注入、提及解析测试 |
| `codex-rs/core/src/skills/manager_tests.rs` | 技能管理器缓存、配置处理测试 |

### 4.3 相关 Skill 文档

| 文件 | 说明 |
|------|------|
| `codex-rs/skills/src/assets/samples/openai-docs/SKILL.md` | 技能主文档，包含使用指南和指令 |
| `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md` | openai.yaml 格式规范文档 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/latest-model.md` | 模型选择参考 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/upgrading-to-gpt-5p4.md` | GPT-5.4 升级指南 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/gpt-5p4-prompting-guide.md` | Prompt 优化指南 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
openai.yaml
    │
    ├── 编译时嵌入 ← codex-rs/skills/src/lib.rs (include_dir 宏)
    │
    ├── YAML 解析 ← serde_yaml (loader.rs)
    │
    ├── 技能元数据模型 ← codex-rs/core/src/skills/model.rs
    │
    ├── 技能加载器 ← codex-rs/core/src/skills/loader.rs
    │
    └── MCP 依赖处理 ← codex-rs/core/src/mcp/skill_dependencies.rs
```

### 5.2 外部依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| `openaiDeveloperDocs` MCP Server | 外部服务 | OpenAI 官方文档 MCP 服务器，提供文档搜索/获取能力 |
| `https://developers.openai.com/mcp` | HTTP Endpoint | MCP Streamable HTTP 传输端点 |
| `codex mcp add` | CLI 命令 | 用于安装 MCP 依赖的命令 |

### 5.3 MCP 工具映射

`openai.yaml` 中声明的依赖会映射为以下 MCP 工具：

| 依赖字段 | 生成的工具前缀 | 可用工具 |
|----------|----------------|----------|
| `value: "openaiDeveloperDocs"` | `mcp__openaiDeveloperDocs__` | `search_openai_docs` |
| | | `fetch_openai_doc` |
| | | `list_openai_docs` |

### 5.4 运行时文件布局

```
$CODEX_HOME/
└── skills/
    └── .system/
        └── openai-docs/
            ├── SKILL.md                           # 技能主文档
            ├── agents/
            │   └── openai.yaml                   # ← 本配置文件
            ├── assets/
            │   ├── openai-small.svg             # 小图标
            │   └── openai.png                   # 大图标
            ├── references/
            │   ├── latest-model.md              # 模型参考
            │   ├── upgrading-to-gpt-5p4.md      # 升级指南
            │   └── gpt-5p4-prompting-guide.md   # Prompt 指南
            └── LICENSE.txt                      # 许可证
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| MCP 服务器不可用 | 技能无法获取最新文档，回退到 references/ 中的静态文件 | SKILL.md 中定义了回退策略 |
| 图标路径解析失败 | UI 中不显示图标，但不影响功能 | `resolve_asset_path()` 返回 None 时优雅降级 |
| YAML 解析错误 | 整个技能元数据加载失败 | `load_skill_metadata()` 使用 `LoadedSkillMetadata::default()` 容错 |
| 网络连接问题 | MCP 服务器连接失败 | 用户可手动运行安装命令，支持权限升级重试 |

### 6.2 边界限制

| 限制项 | 当前值 | 说明 |
|--------|--------|------|
| `display_name` 最大长度 | 64 字符 | `MAX_NAME_LEN` |
| `short_description` 最大长度 | 1024 字符 | `MAX_SHORT_DESCRIPTION_LEN` |
| `default_prompt` 最大长度 | 1024 字符 | `MAX_DEFAULT_PROMPT_LEN` |
| 图标路径 | 必须位于 `assets/` 目录下 | 安全限制，防止目录遍历 |
| 依赖类型 | 仅支持 `"mcp"` | 未来可能扩展其他类型 |
| 传输协议 | `"streamable_http"` 或 `"stdio"` | Streamable HTTP 需要 `url`，stdio 需要 `command` |

### 6.3 改进建议

#### 6.3.1 配置验证增强

当前 YAML 解析错误时直接返回默认值，建议增加警告日志：

```rust
// 当前实现
Err(error) => {
    tracing::warn!("ignoring {path}: invalid {label}: {error}");
    return LoadedSkillMetadata::default();
}

// 建议：增加更详细的字段级验证
```

#### 6.3.2 多语言支持

当前 `display_name` 和 `short_description` 仅支持单一语言，建议增加 i18n 支持：

```yaml
interface:
  display_name:
    en: "OpenAI Docs"
    zh: "OpenAI 文档"
```

#### 6.3.3 版本声明

建议增加技能版本声明，便于后续更新管理：

```yaml
metadata:
  version: "1.0.0"
  min_codex_version: "1.0.0"
```

#### 6.3.4 依赖版本约束

当前 MCP 依赖没有版本约束，建议增加：

```yaml
dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      version: ">=1.0.0"
```

#### 6.3.5 图标格式验证

当前仅验证路径安全性，建议增加格式验证：

```rust
// 验证图标格式（SVG、PNG 等）
fn validate_icon_format(path: &Path) -> Result<(), String> {
    match path.extension().and_then(|e| e.to_str()) {
        Some("svg") | Some("png") | Some("jpg") => Ok(()),
        _ => Err("unsupported icon format".to_string()),
    }
}
```

### 6.4 测试建议

| 测试类型 | 测试内容 |
|----------|----------|
| 单元测试 | YAML 解析、字段验证、路径解析 |
| 集成测试 | 完整技能加载流程、MCP 依赖安装 |
| 端到端测试 | 用户触发技能、UI 展示、工具调用 |
| 安全测试 | 路径遍历攻击防护、恶意 YAML 处理 |

---

## 7. 附录

### 7.1 完整配置示例

参考 `skill-creator/references/openai_yaml.md` 中的完整示例：

```yaml
interface:
  display_name: "Optional user-facing name"
  short_description: "Optional user-facing description"
  icon_small: "./assets/small-400px.png"
  icon_large: "./assets/large-logo.svg"
  brand_color: "#3B82F6"
  default_prompt: "Optional surrounding prompt to use the skill with"

dependencies:
  tools:
    - type: "mcp"
      value: "github"
      description: "GitHub MCP server"
      transport: "streamable_http"
      url: "https://api.githubcopilot.com/mcp/"

policy:
  allow_implicit_invocation: true
```

### 7.2 相关协议与规范

- **MCP (Model Context Protocol)**: https://modelcontextprotocol.io/
- **OpenAI Developer Docs MCP**: https://developers.openai.com/mcp
- **Skill 规范文档**: `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md`

### 7.3 调试命令

```bash
# 查看已安装的 MCP 服务器
codex mcp list

# 手动安装 openaiDeveloperDocs MCP 服务器
codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp

# 触发 openai-docs 技能
codex "$openai-docs what is the latest GPT model?"
```

---

*研究完成时间: 2026-03-23*
*研究范围: codex-rs/skills/src/assets/samples/openai-docs/agents/openai.yaml 及其完整上下文依赖*
