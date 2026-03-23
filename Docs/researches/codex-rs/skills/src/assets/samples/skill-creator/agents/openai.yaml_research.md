# openai.yaml 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/skills/src/assets/samples/skill-creator/agents/openai.yaml`
- **文件类型**: YAML 配置文件
- **所属 Skill**: `skill-creator` (技能创建器)
- **所属 Crate**: `codex-skills`

---

## 场景与职责

### 1.1 定位与用途

`openai.yaml` 是 Skill Creator 技能的 **Agent 元数据配置文件**，位于 `agents/` 子目录下。该文件是 OpenAI 产品特定的扩展配置，主要服务于：

1. **UI 展示**: 为 Codex TUI/GUI 提供技能列表和芯片(chips)展示所需的元数据
2. **人机交互**: 提供人类可读的显示名称、描述和默认提示词
3. **产品集成**: 作为 OpenAI 产品生态中技能发现和使用的基础设施

### 1.2 所属 Skill 的职责

Skill Creator 是一个**系统级技能**（System Skill），其核心职责是：

- **指导用户创建有效技能**: 提供创建技能的完整流程指导
- **提供初始化工具**: 通过 `init_skill.py` 脚本自动化创建技能模板
- **提供验证工具**: 通过 `quick_validate.py` 验证技能结构正确性
- **提供生成工具**: 通过 `generate_openai_yaml.py` 生成本配置文件

### 1.3 在技能体系中的位置

```
Skill 加载层级（由高到低优先级）:
├── Repo Scope (.agents/skills/)
├── User Scope (~/.agents/skills/, ~/.codex/skills/)
├── System Scope (~/.codex/skills/.system/) ← skill-creator 所在位置
└── Admin Scope (/etc/codex/skills/)
```

`skill-creator` 作为**嵌入式系统技能**，在编译时通过 `include_dir!` 宏嵌入到 `codex-skills` crate 中，运行时由 `install_system_skills()` 函数解压到 `CODEX_HOME/skills/.system/` 目录。

---

## 功能点目的

### 2.1 配置字段解析

| 字段 | 类型 | 目的 |
|------|------|------|
| `interface.display_name` | string | UI 技能列表中显示的人类可读标题 |
| `interface.short_description` | string | UI 中快速扫描用的简短描述（25-64字符） |
| `interface.icon_small` | path | 小图标路径（相对技能目录），用于列表展示 |
| `interface.icon_large` | path | 大图标路径（相对技能目录），用于详情展示 |

### 2.2 与其他技能配置文件的对比

```yaml
# skill-creator/agents/openai.yaml (本文件)
interface:
  display_name: "Skill Creator"
  short_description: "Create or update a skill"
  icon_small: "./assets/skill-creator-small.svg"
  icon_large: "./assets/skill-creator.png"

# openai-docs/agents/openai.yaml (对比：包含依赖和默认提示)
interface:
  display_name: "OpenAI Docs"
  short_description: "Reference official OpenAI docs..."
  icon_small: "./assets/openai-small.svg"
  icon_large: "./assets/openai.png"
  default_prompt: "Look up official OpenAI docs..."
dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"

# skill-installer/agents/openai.yaml (对比：极简配置)
interface:
  display_name: "Skill Installer"
  short_description: "Install curated skills from openai/skills..."
  icon_small: "./assets/skill-installer-small.svg"
  icon_large: "./assets/skill-installer.png"
```

### 2.3 字段设计决策

**为何没有 `default_prompt`？**
- Skill Creator 是一个**指导型技能**，而非**执行型技能**
- 用户通常通过明确指令（如"帮我创建一个处理 PDF 的技能"）触发，不需要默认提示词
- 对比 openai-docs 技能需要 `default_prompt` 来引导查询文档的行为

**为何没有 `dependencies`？**
- Skill Creator 是纯本地工具技能，不依赖外部 MCP 服务器
- 所有功能通过本地 Python 脚本（`init_skill.py`, `quick_validate.py` 等）实现

**为何没有 `policy`？**
- 默认 `allow_implicit_invocation: true` 已满足需求
- Skill Creator 需要在用户提及技能创建时被自动触发

---

## 具体技术实现

### 3.1 数据结构定义

#### 3.1.1 Rust 协议层 (`codex-protocol`)

```rust
// codex-rs/protocol/src/protocol.rs:2956-2969
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS)]
pub struct SkillInterface {
    #[ts(optional)]
    pub display_name: Option<String>,
    #[ts(optional)]
    pub short_description: Option<String>,
    #[ts(optional)]
    pub icon_small: Option<PathBuf>,
    #[ts(optional)]
    pub icon_large: Option<PathBuf>,
    #[ts(optional)]
    pub brand_color: Option<String>,
    #[ts(optional)]
    pub default_prompt: Option<String>,
}
```

#### 3.1.2 Rust 核心层 (`codex-core`)

```rust
// codex-rs/core/src/skills/model.rs:56-63
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,
}
```

#### 3.1.3 Loader 解析结构 (`codex-core`)

```rust
// codex-rs/core/src/skills/loader.rs:98-106
#[derive(Debug, Default, Deserialize)]
struct Interface {
    display_name: Option<String>,
    short_description: Option<String>,
    icon_small: Option<PathBuf>,
    icon_large: Option<PathBuf>,
    brand_color: Option<String>,
    default_prompt: Option<String>,
}
```

### 3.2 加载与解析流程

#### 3.2.1 文件定位

```rust
// codex-rs/core/src/skills/loader.rs:135-137
const SKILLS_METADATA_DIR: &str = "agents";
const SKILLS_METADATA_FILENAME: &str = "openai.yaml";
```

解析器在加载 `SKILL.md` 后，会查找同级目录下的 `agents/openai.yaml`。

#### 3.2.2 解析入口

```rust
// codex-rs/core/src/skills/loader.rs:602-655
fn load_skill_metadata(skill_path: &Path) -> LoadedSkillMetadata {
    let skill_dir = skill_path.parent()?;
    let metadata_path = skill_dir
        .join(SKILLS_METADATA_DIR)
        .join(SKILLS_METADATA_FILENAME);
    if !metadata_path.exists() {
        return LoadedSkillMetadata::default();  // 可选文件，不存在返回默认值
    }
    // 解析 YAML -> SkillMetadataFile -> LoadedSkillMetadata
}
```

#### 3.2.3 接口解析逻辑

```rust
// codex-rs/core/src/skills/loader.rs:693-722
fn resolve_interface(interface: Option<Interface>, skill_dir: &Path) -> Option<SkillInterface> {
    let interface = interface?;
    let interface = SkillInterface {
        display_name: resolve_str(interface.display_name, MAX_NAME_LEN, "interface.display_name"),
        short_description: resolve_str(interface.short_description, MAX_SHORT_DESCRIPTION_LEN, ...),
        icon_small: resolve_asset_path(skill_dir, "interface.icon_small", interface.icon_small),
        icon_large: resolve_asset_path(skill_dir, "interface.icon_large", interface.icon_large),
        brand_color: resolve_color_str(interface.brand_color, "interface.brand_color"),
        default_prompt: resolve_str(interface.default_prompt, MAX_DEFAULT_PROMPT_LEN, ...),
    };
    // 只有当至少有一个字段存在时才返回 Some
    let has_fields = interface.display_name.is_some() || ...;
    if has_fields { Some(interface) } else { None }
}
```

### 3.3 图标路径解析规则

```rust
// codex-rs/core/src/skills/loader.rs:783-829
fn resolve_asset_path(skill_dir: &Path, field: &'static str, path: Option<PathBuf>) -> Option<PathBuf> {
    let path = path?;
    
    // 规则1: 必须是相对路径
    if path.is_absolute() { return None; }
    
    // 规则2: 必须位于 assets/ 目录下
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::Normal(component) => normalized.push(component),
            Component::ParentDir => return None,  // 禁止 .. 
            _ => return None,
        }
    }
    
    // 验证第一级目录是 "assets"
    let mut components = normalized.components();
    match components.next() {
        Some(Component::Normal(component)) if component == "assets" => {}
        _ => return None,
    }
    
    Some(skill_dir.join(normalized))
}
```

### 3.4 长度限制约束

```rust
// codex-rs/core/src/skills/loader.rs:138-147
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
const MAX_SHORT_DESCRIPTION_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEFAULT_PROMPT_LEN: usize = MAX_DESCRIPTION_LEN;
```

### 3.5 生成工具实现

#### 3.5.1 生成脚本

`scripts/generate_openai_yaml.py` 提供程序化生成本文件的能力：

```python
# 关键函数
write_openai_yaml(skill_dir, skill_name, raw_overrides)
  ├── read_frontmatter_name(skill_dir)  # 从 SKILL.md 读取 name
  ├── format_display_name(skill_name)   # 格式化显示名
  ├── generate_short_description(display_name)  # 生成描述
  └── 写入 agents/openai.yaml
```

#### 3.5.2 显示名格式化规则

```python
ACRONYMS = {"GH", "MCP", "API", "CI", "CLI", "LLM", "PDF", "PR", "UI", "URL", "SQL"}
BRANDS = {"openai": "OpenAI", "github": "GitHub", "sqlite": "SQLite", ...}
SMALL_WORDS = {"and", "or", "to", "up", "with"}

def format_display_name(skill_name):
    # skill-creator -> "Skill Creator"
    # gh-address-comments -> "GH Address Comments"
    # openai-docs -> "OpenAI Docs"
```

#### 3.5.3 短描述生成规则

```python
def generate_short_description(display_name):
    description = f"Help with {display_name} tasks"
    # 长度约束: 25-64 字符
    # 不足 25: 追加 " and workflows" 或 " with guidance"
    # 超过 64: 逐步裁剪至 "{display_name} helper" 或 "{display_name} tools"
```

---

## 关键代码路径与文件引用

### 4.1 核心加载路径

```
Skill 加载调用链:
codex_core::skills::SkillsManager::skills_for_config()
    └── skill_roots_for_config()
        └── codex_core::skills::loader::skill_roots()
            └── load_skills_from_roots()
                └── discover_skills_under_root()
                    └── parse_skill_file()
                        ├── extract_frontmatter()  # 解析 SKILL.md
                        └── load_skill_metadata()  # 解析 openai.yaml
                            └── resolve_interface()
```

### 4.2 关键文件引用

| 文件路径 | 角色 |
|---------|------|
| `codex-rs/core/src/skills/loader.rs` | 主加载器，解析 `openai.yaml` |
| `codex-rs/core/src/skills/model.rs` | `SkillInterface` 核心模型定义 |
| `codex-rs/protocol/src/protocol.rs` | 协议层 `SkillInterface` 定义（JSON Schema/TS 生成） |
| `codex-rs/tui/src/chatwidget/skills.rs` | TUI 中技能展示和提及处理 |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 聊天输入框技能芯片展示 |

### 4.3 系统技能安装路径

```rust
// codex-rs/skills/src/lib.rs:12
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");

// 运行时解压到:
// $CODEX_HOME/skills/.system/
//   └── skill-creator/
//       ├── agents/openai.yaml ← 本文件
//       ├── assets/
//       ├── references/
//       ├── scripts/
//       ├── SKILL.md
//       └── license.txt
```

### 4.4 构建时集成

```rust
// codex-rs/skills/build.rs
fn main() {
    let samples_dir = Path::new("src/assets/samples");
    println!("cargo:rerun-if-changed={}", samples_dir.display());
    visit_dir(samples_dir);  // 监听所有样本文件变更
}
```

---

## 依赖与外部交互

### 5.1 编译时依赖

| 依赖 | 用途 |
|------|------|
| `include_dir` | 将 `samples/` 目录嵌入二进制 |
| `codex-utils-absolute-path` | 路径规范化与安全校验 |

### 5.2 运行时依赖

| 依赖 | 用途 |
|------|------|
| `serde_yaml` | YAML 解析 |
| `tracing` | 警告日志（如字段验证失败） |

### 5.3 上游调用方

```rust
// codex-rs/core/src/skills/manager.rs:43-56
impl SkillsManager {
    pub fn new(codex_home: PathBuf, plugins_manager: Arc<PluginsManager>, bundled_skills_enabled: bool) -> Self {
        // ...
        if !bundled_skills_enabled {
            uninstall_system_skills(&manager.codex_home);
        } else if let Err(err) = install_system_skills(&manager.codex_home) {
            tracing::error!("failed to install system skills: {err}");
        }
        manager
    }
}
```

### 5.4 下游消费方

1. **TUI 层**: 使用 `SkillInterface` 渲染技能列表芯片
2. **App Server**: 通过 `SkillMetadata` 协议暴露给客户端
3. **提示词组装**: `default_prompt` 被注入到系统提示词中

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 图标路径遍历风险

**风险**: 虽然 `resolve_asset_path` 已阻止 `..` 和绝对路径，但如果 `assets/` 目录本身被符号链接到敏感位置，仍可能产生意外访问。

**缓解**: 图标文件仅在 UI 展示时读取，不执行，风险较低。

#### 6.1.2 YAML 解析失败静默处理

```rust
// loader.rs:626-638
match serde_yaml::from_str(&contents) {
    Ok(parsed) => parsed,
    Err(error) => {
        tracing::warn!("ignoring {path}: invalid {label}: {error}");
        return LoadedSkillMetadata::default();  // 静默失败
    }
}
```

**风险**: 格式错误的 `openai.yaml` 会被静默忽略，用户可能 unaware 配置未生效。

#### 6.1.3 长度截断无反馈

```rust
// resolve_str 中超过长度限制仅记录 warning 日志
if value.chars().count() > max_len {
    tracing::warn!("ignoring {field}: exceeds maximum length...");
    return None;
}
```

**风险**: 用户可能不知道其配置被忽略。

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| 文件不存在 | 返回 `LoadedSkillMetadata::default()`（所有字段 None） |
| 空 YAML 文件 | 同上 |
| 字段值为空字符串 | 被忽略（`resolve_str` 返回 None） |
| 图标路径非 `assets/` 下 | 被忽略，记录 warning |
| `brand_color` 非 `#RRGGBB` 格式 | 被忽略，记录 warning |
| 描述长度 < 25 或 > 64 | `generate_openai_yaml.py` 自动调整；手动配置超限被忽略 |

### 6.3 改进建议

#### 6.3.1 配置验证增强

建议增加严格的验证模式（如 `--strict` 标志），将 warning 提升为 error：

```rust
pub enum MetadataLoadMode {
    Lenient,   // 当前行为：静默忽略错误
    Strict,    // 新行为：YAML 错误返回 Err
}
```

#### 6.3.2 图标格式校验

当前仅校验路径位置，建议增加格式校验：

```rust
fn validate_icon_format(path: &Path) -> bool {
    matches!(path.extension(), Some(ext) if 
        ext.eq_ignore_ascii_case("png") ||
        ext.eq_ignore_ascii_case("svg") ||
        ext.eq_ignore_ascii_case("jpg")
    )
}
```

#### 6.3.3 生成工具增强

`generate_openai_yaml.py` 当前仅支持有限的接口字段，建议：

1. 支持 `dependencies` 的交互式添加
2. 支持 `policy.allow_implicit_invocation` 配置
3. 添加 `--validate` 模式验证现有文件

#### 6.3.4 文档一致性

`references/openai_yaml.md` 中列出的完整示例包含 `dependencies` 和 `policy`，但 `skill-creator` 实际未使用。建议在 SKILL.md 中增加注释说明何时需要这些字段。

#### 6.3.5 版本控制

建议为 `openai.yaml` 增加版本字段，便于未来格式演进：

```yaml
version: "1.0"  # 新增
interface:
  ...
```

---

## 附录：完整字段规范

基于 `references/openai_yaml.md` 和代码实现，完整字段规范如下：

```yaml
# agents/openai.yaml 完整规范

interface:
  display_name: string        # 人类可读标题（UI 展示）
  short_description: string   # 简短描述（25-64 字符）
  icon_small: string          # 小图标路径（相对技能目录，必须位于 assets/ 下）
  icon_large: string          # 大图标路径（相对技能目录，必须位于 assets/ 下）
  brand_color: string         # 品牌色（#RRGGBB 格式）
  default_prompt: string      # 默认提示词（提及技能时注入）

dependencies:
  tools:
    - type: string            # 依赖类型（当前仅支持 "mcp"）
      value: string           # 依赖标识符
      description: string     # 人类可读描述
      transport: string       # 传输类型（如 "streamable_http"）
      url: string             # MCP 服务器 URL
      command: string         # 本地命令（如 stdio MCP）

policy:
  allow_implicit_invocation: boolean  # 是否允许隐式调用（默认 true）
  products: array            # 限制特定产品可用（如 ["chatgpt", "codex"]）
```

---

## 参考链接

- 所属 Skill 文档: `codex-rs/skills/src/assets/samples/skill-creator/SKILL.md`
- 字段定义参考: `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md`
- 生成工具: `codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py`
- 初始化工具: `codex-rs/skills/src/assets/samples/skill-creator/scripts/init_skill.py`
- 验证工具: `codex-rs/skills/src/assets/samples/skill-creator/scripts/quick_validate.py`
