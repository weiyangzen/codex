# 研究文档：codex-rs/skills/src/assets/samples/openai-docs/agents

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`codex-rs/skills/src/assets/samples/openai-docs/agents/` 是 **OpenAI Docs Skill** 的元数据配置目录，存储该技能的 UI 元数据和工具依赖声明。该目录是 Codex CLI 项目内置系统技能（System Skill）的一部分。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **UI 元数据声明** | 定义技能在 UI 中的展示名称、描述、图标和默认提示词 |
| **工具依赖声明** | 声明技能依赖的外部 MCP（Model Context Protocol）服务器 |
| **产品集成配置** | 为 OpenAI 官方产品文档查询功能提供配置支持 |

### 1.3 在系统架构中的位置

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex CLI 应用层                          │
├─────────────────────────────────────────────────────────────────┤
│  Skills Manager (core/src/skills/manager.rs)                    │
│     └── 加载和管理所有技能（用户/系统/仓库级）                    │
├─────────────────────────────────────────────────────────────────┤
│  System Skills (codex-rs/skills/src/assets/samples/)            │
│     ├── openai-docs/          ← 本研究对象                       │
│     │   ├── SKILL.md          # 技能主文档（指令内容）            │
│     │   ├── agents/                                           │
│     │   │   └── openai.yaml   # UI 元数据和依赖配置              │
│     │   ├── assets/           # 图标资源                        │
│     │   └── references/       # 参考文档（模型升级指南等）        │
│     ├── skill-creator/                                          │
│     └── skill-installer/                                        │
├─────────────────────────────────────────────────────────────────┤
│  Runtime ($CODEX_HOME/skills/.system/)                          │
│     └── 编译时嵌入的技能在运行时解压至此                          │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 使用场景

当用户询问以下类型问题时，Codex 会自动触发 `openai-docs` 技能：

- OpenAI API 使用方法查询
- 模型选择建议（"应该使用哪个模型？"）
- GPT-5.4 升级指导
- Prompt 优化建议
- OpenAI 产品功能咨询

---

## 功能点目的

### 2.1 openai.yaml 文件结构

```yaml
interface:
  display_name: "OpenAI Docs"                    # UI 展示名称
  short_description: "Reference official OpenAI docs..."  # 简短描述
  icon_small: "./assets/openai-small.svg"        # 小图标路径
  icon_large: "./assets/openai.png"              # 大图标路径
  default_prompt: "Look up official OpenAI docs..."  # 默认提示词

dependencies:
  tools:
    - type: "mcp"                                # 工具类型：MCP 服务器
      value: "openaiDeveloperDocs"               # MCP 服务器标识
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"               # 传输协议
      url: "https://developers.openai.com/mcp"   # MCP 服务器 URL
```

### 2.2 功能模块详解

#### 2.2.1 Interface 配置

| 字段 | 用途 | 约束 |
|------|------|------|
| `display_name` | 技能列表和芯片中显示的人类可读名称 | 最大 64 字符 |
| `short_description` | 快速扫描用的简短 UI 描述 | 25-64 字符 |
| `icon_small` | 小图标资源路径（相对技能目录） | 必须位于 `./assets/` 下 |
| `icon_large` | 大图标/Logo 资源路径 | 必须位于 `./assets/` 下 |
| `default_prompt` | 调用技能时插入的默认提示词 | 最大 1024 字符 |

#### 2.2.2 Dependencies 配置

| 字段 | 用途 | 说明 |
|------|------|------|
| `type` | 依赖类别 | 目前仅支持 `mcp` |
| `value` | 工具/依赖标识符 | MCP 服务器名称 |
| `description` | 人类可读的依赖说明 | - |
| `transport` | 连接类型 | `streamable_http` 或 `stdio` |
| `url` | MCP 服务器 URL | Streamable HTTP 传输必需 |
| `command` | 命令行启动命令 | Stdio 传输必需 |

### 2.3 与其他组件的协作

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Skill Loader  │────▶│  openai.yaml     │────▶│  Skills Manager │
│  (loader.rs)    │     │  (元数据解析)     │     │  (manager.rs)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                              │
         ▼                                              ▼
┌─────────────────┐                           ┌──────────────────┐
│  SkillMetadata  │                           │  SkillInterface  │
│  (model.rs)     │                           │  (UI 渲染)       │
└─────────────────┘                           └──────────────────┘
                                                       │
         ┌─────────────────────────────────────────────┘
         ▼
┌──────────────────────────────────────────────────────────────┐
│              MCP Dependency Installer                          │
│         (skill_dependencies.rs)                                │
│  - 检查缺失的 MCP 服务器                                        │
│  - 自动安装 openaiDeveloperDocs                                │
│  - 处理 OAuth 认证流程                                          │
└──────────────────────────────────────────────────────────────┘
```

---

## 具体技术实现

### 3.1 元数据加载流程

#### 3.1.1 文件解析入口

**文件**: `codex-rs/core/src/skills/loader.rs`

```rust
// 关键常量定义
const SKILLS_METADATA_DIR: &str = "agents";
const SKILLS_METADATA_FILENAME: &str = "openai.yaml";

// 元数据加载流程
fn load_skill_metadata(skill_path: &Path) -> LoadedSkillMetadata {
    let skill_dir = skill_path.parent()?;
    let metadata_path = skill_dir
        .join(SKILLS_METADATA_DIR)
        .join(SKILLS_METADATA_FILENAME);
    
    if !metadata_path.exists() {
        return LoadedSkillMetadata::default();
    }
    
    // 解析 YAML 文件
    let parsed: SkillMetadataFile = serde_yaml::from_str(&contents)?;
    
    // 解析各个部分
    LoadedSkillMetadata {
        interface: resolve_interface(parsed.interface, skill_dir),
        dependencies: resolve_dependencies(parsed.dependencies),
        policy: resolve_policy(parsed.policy),
        permission_profile,
        managed_network_override,
    }
}
```

#### 3.1.2 YAML 结构定义

```rust
#[derive(Debug, Default, Deserialize)]
struct SkillMetadataFile {
    interface: Option<Interface>,
    dependencies: Option<Dependencies>,
    policy: Option<Policy>,
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

### 3.2 资源路径解析

**文件**: `codex-rs/core/src/skills/loader.rs` (resolve_asset_path 函数)

```rust
fn resolve_asset_path(
    skill_dir: &Path,
    field: &'static str,
    path: Option<PathBuf>,
) -> Option<PathBuf> {
    let path = path?;
    
    // 1. 图标必须是相对路径
    if path.is_absolute() {
        tracing::warn!("ignoring {field}: icon must be a relative assets path");
        return None;
    }
    
    // 2. 规范化路径组件（禁止 ..）
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::Normal(component) => normalized.push(component),
            Component::ParentDir => {
                tracing::warn!("ignoring {field}: icon path must not contain '..'");
                return None;
            }
            _ => return None,
        }
    }
    
    // 3. 必须位于 assets/ 目录下
    let mut components = normalized.components();
    match components.next() {
        Some(Component::Normal(component)) if component == "assets" => {}
        _ => {
            tracing::warn!("ignoring {field}: icon path must be under assets/");
            return None;
        }
    }
    
    Some(skill_dir.join(normalized))
}
```

### 3.3 MCP 依赖处理

**文件**: `codex-rs/core/src/mcp/skill_dependencies.rs`

#### 3.3.1 依赖收集流程

```rust
pub(crate) fn collect_missing_mcp_dependencies(
    mentioned_skills: &[SkillMetadata],
    installed: &HashMap<String, McpServerConfig>,
) -> HashMap<String, McpServerConfig> {
    let mut missing = HashMap::new();
    let installed_keys: HashSet<String> = installed
        .iter()
        .map(|(name, config)| canonical_mcp_server_key(name, config))
        .collect();
    
    for skill in mentioned_skills {
        let Some(dependencies) = skill.dependencies.as_ref() else {
            continue;
        };
        
        for tool in &dependencies.tools {
            if !tool.r#type.eq_ignore_ascii_case("mcp") {
                continue;
            }
            
            // 生成规范化的依赖键
            let dependency_key = canonical_mcp_dependency_key(tool)?;
            
            // 检查是否已安装
            if installed_keys.contains(&dependency_key) {
                continue;
            }
            
            // 转换为 MCP 服务器配置
            let config = mcp_dependency_to_server_config(tool)?;
            missing.insert(tool.value.clone(), config);
        }
    }
    
    missing
}
```

#### 3.3.2 依赖键生成逻辑

```rust
fn canonical_mcp_dependency_key(dependency: &SkillToolDependency) 
    -> Result<String, String> {
    let transport = dependency.transport.as_deref().unwrap_or("streamable_http");
    
    if transport.eq_ignore_ascii_case("streamable_http") {
        let url = dependency.url.as_ref()
            .ok_or("missing url for streamable_http dependency")?;
        return Ok(canonical_mcp_key("streamable_http", url, &dependency.value));
    }
    
    if transport.eq_ignore_ascii_case("stdio") {
        let command = dependency.command.as_ref()
            .ok_or("missing command for stdio dependency")?;
        return Ok(canonical_mcp_key("stdio", command, &dependency.value));
    }
    
    Err(format!("unsupported transport {transport}"))
}
```

#### 3.3.3 配置转换

```rust
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
            // ... 其他默认配置
        });
    }
    
    // stdio 传输类型处理类似...
}
```

### 3.4 嵌入式技能分发

**文件**: `codex-rs/skills/src/lib.rs`

```rust
// 编译时嵌入技能目录
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!(
    "$CARGO_MANIFEST_DIR/src/assets/samples"
);

// 安装系统技能到运行时目录
pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    let dest_system = system_cache_root_dir_abs(&codex_home)?;
    
    // 检查指纹标记，避免重复安装
    let marker_path = dest_system.join(SYSTEM_SKILLS_MARKER_FILENAME);
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    if read_marker(&marker_path)? == expected_fingerprint {
        return Ok(());  // 已是最新版本
    }
    
    // 清理并重新安装
    if dest_system.exists() {
        fs::remove_dir_all(&dest_system)?;
    }
    
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
    fs::write(&marker_path, format!("{expected_fingerprint}\n"))?;
    
    Ok(())
}
```

### 3.5 技能注入流程

**文件**: `codex-rs/core/src/skills/injection.rs`

当用户显式提及 `$openai-docs` 技能时：

```rust
pub(crate) async fn build_skill_injections(
    mentioned_skills: &[SkillMetadata],
    otel: Option<&SessionTelemetry>,
    analytics_client: &AnalyticsEventsClient,
    tracking: TrackEventsContext,
) -> SkillInjections {
    for skill in mentioned_skills {
        match fs::read_to_string(&skill.path_to_skills_md).await {
            Ok(contents) => {
                // 注入技能指令到对话上下文
                result.items.push(ResponseItem::from(SkillInstructions {
                    name: skill.name.clone(),
                    path: skill.path_to_skills_md.to_string_lossy().into_owned(),
                    contents,  // SKILL.md 完整内容
                }));
            }
            Err(err) => {
                result.warnings.push(format!(
                    "Failed to load skill {name}: {err}"
                ));
            }
        }
    }
    
    // 触发 MCP 依赖安装
    maybe_prompt_and_install_mcp_dependencies(...).await;
    
    result
}
```

---

## 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/skills/src/assets/samples/openai-docs/agents/openai.yaml` | **本研究对象**：UI 元数据和 MCP 依赖配置 |
| `codex-rs/skills/src/assets/samples/openai-docs/SKILL.md` | 技能主文档（指令内容） |
| `codex-rs/core/src/skills/loader.rs` | 技能元数据加载和解析 |
| `codex-rs/core/src/skills/model.rs` | 技能数据模型定义 |
| `codex-rs/core/src/skills/manager.rs` | 技能生命周期管理 |
| `codex-rs/core/src/mcp/skill_dependencies.rs` | MCP 依赖收集和自动安装 |
| `codex-rs/core/src/skills/injection.rs` | 技能注入对话上下文 |
| `codex-rs/skills/src/lib.rs` | 嵌入式系统技能分发 |

### 4.2 相关参考文档

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/skills/src/assets/samples/openai-docs/references/latest-model.md` | 当前模型映射表 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/upgrading-to-gpt-5p4.md` | GPT-5.4 升级指南 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/gpt-5p4-prompting-guide.md` | Prompt 优化指南 |
| `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md` | openai.yaml 格式规范 |

### 4.3 测试文件

| 文件路径 | 测试内容 |
|---------|---------|
| `codex-rs/core/tests/suite/skills.rs` | 技能加载和注入集成测试 |
| `codex-rs/core/src/skills/loader_tests.rs` | 元数据加载单元测试 |
| `codex-rs/core/src/mcp/skill_dependencies_tests.rs` | MCP 依赖处理测试 |

### 4.4 代码调用链

```
用户输入 "$openai-docs"
    │
    ▼
codex-rs/core/src/skills/injection.rs
    └── collect_explicit_skill_mentions()
        └── extract_tool_mentions()  # 提取 $skill-name 提及
    │
    ▼
codex-rs/core/src/skills/manager.rs
    └── skills_for_config()
        └── skill_roots()            # 确定技能根目录
        └── load_skills_from_roots() # 加载所有技能
            │
            ▼
        codex-rs/core/src/skills/loader.rs
            └── discover_skills_under_root()
                └── parse_skill_file()     # 解析 SKILL.md
                └── load_skill_metadata()  # 加载 agents/openai.yaml
                    │
                    ├── resolve_interface()       # 解析 UI 元数据
                    ├── resolve_dependencies()    # 解析工具依赖
                    └── resolve_asset_path()      # 解析资源路径
    │
    ▼
codex-rs/core/src/mcp/skill_dependencies.rs
    └── maybe_prompt_and_install_mcp_dependencies()
        └── collect_missing_mcp_dependencies()  # 检查缺失依赖
        └── maybe_install_mcp_dependencies()    # 自动安装 MCP 服务器
    │
    ▼
codex-rs/core/src/skills/injection.rs
    └── build_skill_injections()
        └── 将 SKILL.md 内容注入对话上下文
```

---

## 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex-rs/core/src/skills/` | 技能系统的核心实现 |
| `codex-rs/core/src/mcp/` | MCP 客户端和依赖管理 |
| `codex-rs/skills/` | 嵌入式系统技能分发 |
| `codex-rs/protocol/` | 协议类型定义（SkillScope, SkillMetadata 等） |

### 5.2 外部依赖

| 外部服务 | 交互方式 | 用途 |
|---------|---------|------|
| **OpenAI Developer Docs MCP** | Streamable HTTP | 查询官方 OpenAI 文档 |
| URL: `https://developers.openai.com/mcp` | | 提供 search/fetch/list 工具 |

### 5.3 MCP 工具暴露

当 `openaiDeveloperDocs` MCP 服务器连接成功后，以下工具可用于该技能：

| 工具名称 | 功能 |
|---------|------|
| `mcp__openaiDeveloperDocs__search_openai_docs` | 搜索最相关的文档页面 |
| `mcp__openaiDeveloperDocs__fetch_openai_doc` | 获取特定文档的精确章节 |
| `mcp__openaiDeveloperDocs__list_openai_docs` | 浏览或发现页面（无明确查询时使用） |

### 5.4 配置依赖

```yaml
# 技能元数据配置 (agents/openai.yaml)
dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

### 5.5 运行时依赖检查流程

```
1. 技能被触发（用户提及 $openai-docs）
   │
   ▼
2. SkillDependenciesResolver 检查 dependencies.tools
   │
   ▼
3. 对每个 MCP 类型依赖：
   a. 生成 canonical key: `mcp__streamable_http__<url>`
   b. 检查是否已在 installed MCP servers 中
   c. 如缺失，生成 McpServerConfig
   │
   ▼
4. 如有缺失依赖：
   a. 提示用户安装（非全访问模式）
   b. 或自动安装（全访问模式）
   c. 执行 OAuth 认证（如需要）
   d. 刷新 MCP 服务器连接
```

---

## 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 网络依赖风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| MCP 服务器不可达 | 技能无法获取最新文档 | 使用 references/ 中的离线指南作为后备 |
| OAuth 认证失败 | 无法连接 MCP 服务器 | 提供降级到网页搜索的选项 |
| 网络超时 | 用户体验下降 | 设置合理的超时和重试机制 |

#### 6.1.2 配置风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| YAML 格式错误 | 技能元数据无法加载 | loader.rs 中已实现容错（Fail open） |
| 资源路径错误 | 图标无法显示 | resolve_asset_path 严格校验路径格式 |
| 依赖声明错误 | MCP 服务器无法安装 | 依赖键生成逻辑有完善的错误处理 |

#### 6.1.3 安全风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 路径遍历攻击 | 访问非预期文件 | 禁止 `..` 组件，强制 `assets/` 前缀 |
| 绝对路径注入 | 绕过资源目录限制 | 拒绝任何绝对路径 |
| MCP 服务器欺骗 | 连接到恶意服务器 | 仅支持预配置的官方 MCP 服务器 |

### 6.2 边界条件

#### 6.2.1 元数据字段约束

```rust
// 来自 loader.rs 的约束常量
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
const MAX_SHORT_DESCRIPTION_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEFAULT_PROMPT_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEPENDENCY_TYPE_LEN: usize = MAX_NAME_LEN;
const MAX_DEPENDENCY_TRANSPORT_LEN: usize = MAX_NAME_LEN;
const MAX_DEPENDENCY_VALUE_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEPENDENCY_DESCRIPTION_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEPENDENCY_COMMAND_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEPENDENCY_URL_LEN: usize = MAX_DESCRIPTION_LEN;
```

#### 6.2.2 技能扫描限制

```rust
const MAX_SCAN_DEPTH: usize = 6;           // 最大扫描深度
const MAX_SKILLS_DIRS_PER_ROOT: usize = 2000;  // 每根目录最大目录数
```

#### 6.2.3 资源路径约束

- 图标路径必须是相对路径
- 图标必须位于 `./assets/` 目录下
- 禁止路径中包含 `..` 组件
- 支持子目录（如 `./assets/icons/small.png`）

### 6.3 改进建议

#### 6.3.1 功能增强

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 支持多 MCP 服务器依赖 | 中 | 当前仅支持单工具依赖，可扩展为列表 |
| 依赖版本约束 | 低 | 添加 `version` 字段声明兼容版本 |
| 条件依赖 | 低 | 根据平台/环境选择不同依赖 |
| 离线模式增强 | 中 | 当 MCP 不可用时，完全依赖本地 references |

#### 6.3.2 可观测性增强

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 依赖安装指标 | 中 | 添加 MCP 依赖安装成功/失败指标 |
| 技能使用分析 | 低 | 追踪 openai-docs 技能触发频率 |
| 缓存命中率 | 低 | 监控技能元数据缓存效果 |

#### 6.3.3 配置验证增强

```yaml
# 建议添加的验证规则
# 1. URL 格式验证
# 2. 图标文件存在性检查
# 3. 依赖循环检测
# 4. 品牌颜色格式验证（#RRGGBB）
```

#### 6.3.4 文档改进

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 添加配置示例 | 高 | 在 openai_yaml.md 中补充更多示例 |
| 故障排查指南 | 中 | 添加 MCP 连接失败的排查步骤 |
| 版本变更日志 | 低 | 记录 agents/openai.yaml 格式变更 |

### 6.4 测试建议

| 测试类型 | 覆盖内容 |
|---------|---------|
| 单元测试 | YAML 解析、路径解析、依赖键生成 |
| 集成测试 | MCP 依赖安装流程、技能注入流程 |
| E2E 测试 | 完整用户场景（提及技能 → 安装依赖 → 使用工具） |
| 边界测试 | 超长字段、特殊字符、路径遍历尝试 |

---

## 附录

### A. 相关协议和常量

```rust
// SkillScope 定义（protocol crate）
pub enum SkillScope {
    Repo,    // 仓库级技能
    User,    // 用户级技能
    System,  // 系统级技能（如 openai-docs）
    Admin,   // 管理员级技能
}

// 技能提及语法
const TOOL_MENTION_SIGIL: char = '$';
// 使用方式: "$openai-docs" 或 "[$openai-docs](skill://path)"
```

### B. 文件完整列表

```
codex-rs/skills/src/assets/samples/openai-docs/
├── agents/
│   └── openai.yaml              # 本研究对象（563 bytes）
├── assets/
│   ├── openai-small.svg         # 小图标（1091 bytes）
│   └── openai.png               # 大图标（1429 bytes）
├── references/
│   ├── gpt-5p4-prompting-guide.md   # Prompt 优化指南（18KB）
│   ├── latest-model.md              # 模型选择参考（1.8KB）
│   └── upgrading-to-gpt-5p4.md      # 升级指南（8.6KB）
├── LICENSE.txt                  # 许可证（10KB）
└── SKILL.md                     # 技能主文档（6.9KB）
```

### C. 变更历史追踪

该目录文件由 `skill-creator` 技能管理更新，使用 `generate_openai_yaml.py` 脚本生成 `openai.yaml` 文件。

---

*文档生成时间: 2026-03-22*
*研究对象版本: 基于 codex-rs 最新主干代码*
