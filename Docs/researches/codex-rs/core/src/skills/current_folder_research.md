# DIR codex-rs/core/src/skills 深度研究

## 概述

`codex-rs/core/src/skills` 是 Codex CLI 项目中负责**技能系统（Skill System）**的核心模块。技能系统允许用户通过 `SKILL.md` 文件定义可复用的 AI 辅助工作流，支持显式调用（通过 `$skill-name` 语法）和隐式调用（通过脚本执行自动检测）。

---

## 场景与职责

### 核心场景

1. **技能发现与加载**：从多个来源（系统、用户、仓库、插件）扫描并加载 `SKILL.md` 文件
2. **技能注入**：将选中技能的指令注入到 LLM 上下文中
3. **显式技能调用**：解析用户输入中的 `$skill-name` 或 `[skill-name](path)` 语法
4. **隐式技能调用**：检测用户执行的脚本是否属于某个技能，自动触发技能注入
5. **依赖管理**：处理技能声明的 MCP 服务器、环境变量、CLI 工具等依赖
6. **权限控制**：支持技能级别的网络、文件系统、macOS 权限配置
7. **远程技能**：支持从远程 API 下载和管理技能（预留功能）

### 职责边界

| 职责 | 说明 |
|------|------|
| 技能扫描 | 递归扫描配置的技能根目录，发现 `SKILL.md` 文件 |
| 元数据解析 | 解析 YAML frontmatter 和 `agents/openai.yaml` 元数据文件 |
| 缓存管理 | 按工作目录和配置缓存技能加载结果 |
| 技能选择 | 根据用户输入选择匹配的技能 |
| 指令注入 | 将技能内容包装为 `ResponseItem` 注入对话 |
| 依赖解析 | 收集并安装技能声明的 MCP 依赖 |
| 隐式调用 | 监控 shell 命令，检测技能脚本执行 |

---

## 功能点目的

### 1. 技能发现（loader.rs）

**目的**：从多个来源发现可用的技能文件。

**技能来源（按优先级排序）**：
- `SkillScope::Repo` - 仓库级技能（`.codex/skills/` 和 `.agents/skills/`）
- `SkillScope::User` - 用户级技能（`$CODEX_HOME/skills/` 和 `$HOME/.agents/skills/`）
- `SkillScope::System` - 系统内置技能（`$CODEX_HOME/skills/.system/`）
- `SkillScope::Admin` - 管理员配置技能（`/etc/codex/skills/`）

**关键限制**：
- 最大扫描深度：6 层（`MAX_SCAN_DEPTH = 6`）
- 每根目录最大目录数：2000（`MAX_SKILLS_DIRS_PER_ROOT = 2000`）
- 符号链接：仅对 User/Repo/Admin 技能跟随符号链接

### 2. 技能解析（loader.rs）

**目的**：解析 `SKILL.md` 文件的元数据和内容。

**文件格式**：
```markdown
---
name: skill-name
description: Skill description
metadata:
  short-description: Short desc
---

# Skill body content...
```

**元数据文件**（`agents/openai.yaml`）：
```yaml
interface:
  display_name: "Display Name"
  icon_small: "./assets/icon.png"
  brand_color: "#3B82F6"
  default_prompt: "Default prompt"
dependencies:
  tools:
    - type: env_var
      value: GITHUB_TOKEN
      description: "GitHub API token"
    - type: mcp
      value: github
      transport: streamable_http
      url: https://example.com/mcp
policy:
  allow_implicit_invocation: true
  products: [codex, chatgpt]
permissions:
  network:
    enabled: true
    allowed_domains: ["api.github.com"]
  file_system:
    read: ["./data"]
    write: ["./output"]
```

### 3. 技能管理（manager.rs）

**目的**：管理技能的生命周期和缓存。

**缓存策略**：
- `cache_by_cwd`：按工作目录缓存（用于 `skills_for_cwd`）
- `cache_by_config`：按配置缓存（用于 `skills_for_config`，避免角色/会话配置串扰）

**禁用技能**：通过配置层（User/SessionFlags）可以禁用特定路径的技能。

### 4. 技能注入（injection.rs）

**目的**：将选中的技能内容注入到 LLM 上下文中。

**注入格式**：
```xml
<skill>
<name>skill-name</name>
<path>/path/to/SKILL.md</path>
{skill_body_content}
</skill>
```

**提及语法**：
- `$skill-name` - 简单提及
- `[$skill-name](/path/to/skill)` - 带路径的链接提及
- `$$skill-name` - 插件提及（使用 `@` 符号）

### 5. 隐式调用（invocation_utils.rs）

**目的**：检测用户执行的命令是否属于某个技能，自动触发技能注入。

**检测规则**：
1. **脚本执行检测**：检测 `python`, `bash`, `node` 等解释器执行技能 `scripts/` 目录下的脚本
2. **文档读取检测**：检测 `cat`, `head`, `less` 等命令读取 `SKILL.md` 文件

**去重机制**：使用 `implicit_invocation_seen_skills` 集合避免重复注入。

### 6. 依赖管理（env_var_dependencies.rs + mcp/skill_dependencies.rs）

**目的**：处理技能声明的依赖项。

**环境变量依赖**：
- 从系统环境变量读取
- 缺失时通过 `request_user_input` 提示用户输入
- 会话级缓存（内存中）

**MCP 依赖**：
- 自动检测缺失的 MCP 服务器
- 提示用户安装
- 支持 OAuth 认证流程
- 自动配置到全局配置

### 7. 系统技能（system.rs + codex-skills crate）

**目的**：管理内置的系统技能。

**实现**：
- 使用 `include_dir` 嵌入技能文件
- 通过指纹标记避免重复安装
- 支持禁用捆绑技能（`skills.bundled.enabled = false`）

---

## 具体技术实现

### 关键数据结构

```rust
// model.rs
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub short_description: Option<String>,
    pub interface: Option<SkillInterface>,
    pub dependencies: Option<SkillDependencies>,
    pub policy: Option<SkillPolicy>,
    pub permission_profile: Option<PermissionProfile>,
    pub managed_network_override: Option<SkillManagedNetworkOverride>,
    pub path_to_skills_md: PathBuf,
    pub scope: SkillScope,
}

pub struct SkillLoadOutcome {
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillError>,
    pub disabled_paths: HashSet<PathBuf>,
    pub(crate) implicit_skills_by_scripts_dir: Arc<HashMap<PathBuf, SkillMetadata>>,
    pub(crate) implicit_skills_by_doc_path: Arc<HashMap<PathBuf, SkillMetadata>>,
}

pub struct SkillPolicy {
    pub allow_implicit_invocation: Option<bool>,
    pub products: Vec<Product>,
}

pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}

pub struct SkillToolDependency {
    pub r#type: String,  // "env_var", "mcp", "cli"
    pub value: String,
    pub description: Option<String>,
    pub transport: Option<String>,
    pub command: Option<String>,
    pub url: Option<String>,
}
```

### 关键流程

#### 技能加载流程

```
skill_roots() -> Vec<SkillRoot>
  ↓
load_skills_from_roots(roots) -> SkillLoadOutcome
  ↓
for each root:
  discover_skills_under_root(root)
    ↓
  BFS scan (max_depth=6, max_dirs=2000)
    ↓
  parse_skill_file(path) -> SkillMetadata
    ↓
  extract_frontmatter() -> YAML frontmatter
  load_skill_metadata() -> agents/openai.yaml
    ↓
  dedupe by path
  sort by scope priority + name
```

#### 技能选择流程

```
collect_explicit_skill_mentions(inputs, skills, disabled_paths, connector_slug_counts)
  ↓
1. Process structured UserInput::Skill selections (by path)
  ↓
2. Extract $mentions from text inputs
   - extract_tool_mentions(text) -> ToolMentions
   - Parse [$name](path) linked mentions
   - Skip common env vars (PATH, HOME, etc.)
  ↓
3. Match mentions to skills
   - Path matching: exact path match
   - Name matching: only if unambiguous (count == 1)
   - Skip if connector slug conflicts
  ↓
Return: Vec<SkillMetadata> (preserving skill order)
```

#### 隐式调用检测流程

```
maybe_emit_implicit_skill_invocation(session, turn_context, command, workdir)
  ↓
detect_implicit_skill_invocation_for_command(outcome, turn_context, command, workdir)
  ↓
tokenize_command(command) -> Vec<String>
  ↓
detect_skill_script_run(outcome, tokens, workdir)
  - Check if runner (python, bash, node, etc.)
  - Extract script path from tokens
  - Check if script is under skill's scripts/ dir
  ↓
detect_skill_doc_read(outcome, tokens, workdir)
  - Check if file reader command (cat, head, etc.)
  - Check if reading SKILL.md file
  ↓
Emit telemetry + analytics event (if not seen this turn)
```

### 协议与接口

#### 技能指令渲染协议（render.rs）

```
## Skills
A skill is a set of local instructions...

### Available skills
- skill-name: description (file: /path/to/SKILL.md)

### How to use skills
- Discovery: ...
- Trigger rules: ...
- How to use a skill (progressive disclosure): ...
```

包装在 XML 标签中：
```xml
<skills_instructions>
{content}
</skills_instructions>
```

#### 远程技能 API（remote.rs）

```rust
pub async fn list_remote_skills(
    config: &Config,
    auth: Option<&CodexAuth>,
    scope: RemoteSkillScope,      // WorkspaceShared, AllShared, Personal, Example
    product_surface: RemoteSkillProductSurface,  // Chatgpt, Codex, Api, Atlas
    enabled: Option<bool>,
) -> Result<Vec<RemoteSkillSummary>>

pub async fn export_remote_skill(
    config: &Config,
    auth: Option<&CodexAuth>,
    skill_id: &str,
) -> Result<RemoteSkillDownloadResult>
```

---

## 关键代码路径与文件引用

### 核心模块

| 文件 | 职责 | 关键函数/类型 |
|------|------|--------------|
| `mod.rs` | 模块导出 | `SkillsManager`, `SkillMetadata`, `SkillLoadOutcome` |
| `model.rs` | 数据模型 | `SkillMetadata`, `SkillPolicy`, `SkillDependencies`, `SkillLoadOutcome` |
| `manager.rs` | 技能管理 | `SkillsManager::skills_for_config()`, `SkillsManager::skills_for_cwd()` |
| `loader.rs` | 技能加载 | `load_skills_from_roots()`, `skill_roots()`, `parse_skill_file()` |
| `render.rs` | 技能渲染 | `render_skills_section()` |
| `injection.rs` | 技能注入 | `build_skill_injections()`, `collect_explicit_skill_mentions()` |
| `invocation_utils.rs` | 隐式调用 | `maybe_emit_implicit_skill_invocation()`, `detect_skill_script_run()` |
| `env_var_dependencies.rs` | 环境变量依赖 | `resolve_skill_dependencies_for_turn()`, `collect_env_var_dependencies()` |
| `remote.rs` | 远程技能 | `list_remote_skills()`, `export_remote_skill()` |
| `system.rs` | 系统技能 | `install_system_skills()`, `uninstall_system_skills()` |

### 测试文件

| 文件 | 测试内容 |
|------|----------|
| `loader_tests.rs` | 技能加载、解析、元数据、权限 |
| `manager_tests.rs` | 缓存、配置覆盖、禁用技能 |
| `injection_tests.rs` | 提及解析、技能选择、歧义处理 |
| `invocation_utils_tests.rs` | 隐式调用检测、脚本执行检测 |

### 调用方（上游依赖）

| 文件 | 使用方式 |
|------|----------|
| `codex.rs` | 调用 `render_skills_section()`, 管理技能注入 |
| `mentions.rs` | 使用 `build_skill_name_counts()`, `ToolMentionKind` |
| `mcp/skill_dependencies.rs` | 使用 `SkillMetadata`, `SkillToolDependency` 处理 MCP 依赖 |
| `instructions/mod.rs` | 导出 `SkillInstructions` 用于技能内容包装 |
| `state/service.rs` | 调用 `SkillsManager` 获取技能列表 |
| `thread_manager.rs` | 使用技能相关功能 |
| `tools/runtimes/mod.rs` | 集成技能执行 |

### 被调用方（下游依赖）

| 文件/模块 | 依赖方式 |
|----------|----------|
| `codex-skills` crate | 提供 `install_system_skills()`, `system_cache_root_dir()` |
| `config_loader` | 配置层栈解析 |
| `plugins/manager.rs` | 插件技能根目录 |
| `protocol` crate | `SkillScope`, `PermissionProfile` 等类型 |
| `analytics_client` | 技能调用埋点 |

---

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde_yaml` | 解析 YAML frontmatter 和元数据文件 |
| `toml` | 配置解析 |
| `dunce` | 路径规范化（跨平台） |
| `shlex` | shell 命令分词 |
| `zip` | 远程技能 ZIP 解压 |
| `include_dir` | 嵌入系统技能文件 |
| `codex_protocol` | 协议类型（`SkillScope`, `PermissionProfile` 等） |
| `codex_app_server_protocol` | 配置层类型 |

### 文件系统交互

| 路径 | 用途 |
|------|------|
| `$CODEX_HOME/skills/` | 用户技能根目录 |
| `$CODEX_HOME/skills/.system/` | 系统技能缓存 |
| `$HOME/.agents/skills/` | 用户技能（替代位置） |
| `$REPO/.codex/skills/` | 仓库技能 |
| `$REPO/.agents/skills/` | 仓库技能（替代位置） |
| `/etc/codex/skills/` | 管理员技能（Unix） |
| `*/SKILL.md` | 技能定义文件 |
| `*/agents/openai.yaml` | 技能元数据文件 |

### 配置集成

```toml
# config.toml
[skills.bundled]
enabled = true

[[skills.config]]
path = "/path/to/skill"
enabled = false
```

---

## 风险、边界与改进建议

### 已知风险

1. **路径遍历风险**
   - 缓解：`resolve_asset_path()` 严格限制图标路径必须在 `assets/` 下，禁止 `..`
   - 远程技能 ZIP 解压使用 `safe_join()` 验证路径组件

2. **缓存不一致**
   - 风险：文件系统变更后缓存可能过期
   - 缓解：`force_reload` 参数允许强制刷新

3. **歧义技能名**
   - 风险：同名技能导致选择错误
   - 缓解：名称冲突时禁用简单提及，要求使用路径链接

4. **隐式调用误触发**
   - 风险：执行非技能脚本时误触发
   - 缓解：严格检查脚本路径是否在技能 `scripts/` 目录下

### 边界情况

| 场景 | 行为 |
|------|------|
| 超过最大扫描深度 | 静默截断，记录警告日志 |
| 超过最大目录数 | 截断并设置 `truncated_by_dir_limit` 标志 |
| 符号链接循环 | `visited_dirs` HashSet 去重防止循环 |
| 系统技能加载失败 | 静默忽略（`scope != SkillScope::System` 时才记录错误） |
| 元数据文件解析失败 | `LoadedSkillMetadata::default()`，记录警告 |
| 空 frontmatter | `SkillParseError::MissingFrontmatter` |

### 改进建议

1. **性能优化**
   - 当前：每次启动全量扫描
   - 建议：添加文件系统监听（`file_watcher.rs`），增量更新缓存

2. **错误处理**
   - 当前：系统技能错误静默忽略
   - 建议：区分用户技能和系统技能的错误报告级别

3. **远程技能**
   - 当前：API 已定义但未完全集成
   - 建议：完成与 ChatGPT 技能市场的集成

4. **依赖管理**
   - 当前：MCP 依赖安装后需手动刷新
   - 建议：自动检测并热加载新 MCP 服务器

5. **权限细化**
   - 当前：技能权限在元数据中声明
   - 建议：运行时权限校验和沙箱隔离

6. **测试覆盖**
   - 当前：单元测试覆盖良好
   - 建议：添加集成测试验证端到端技能调用流程

---

## 附录：关键常量

```rust
const SKILLS_FILENAME: &str = "SKILL.md";
const AGENTS_DIR_NAME: &str = ".agents";
const SKILLS_METADATA_DIR: &str = "agents";
const SKILLS_METADATA_FILENAME: &str = "openai.yaml";
const SKILLS_DIR_NAME: &str = "skills";
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
const MAX_SCAN_DEPTH: usize = 6;
const MAX_SKILLS_DIRS_PER_ROOT: usize = 2000;
```

---

## 附录：技能作用域优先级

```rust
// 数值越小优先级越高
match scope {
    SkillScope::Repo => 0,    // 最高优先级
    SkillScope::User => 1,
    SkillScope::System => 2,
    SkillScope::Admin => 3,   // 最低优先级
}
```

---

*研究文档生成时间：2026-03-21*
*基于代码版本：codex-rs/core/src/skills/*
