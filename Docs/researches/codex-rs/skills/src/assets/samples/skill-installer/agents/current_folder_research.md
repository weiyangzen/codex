# skill-installer/agents 目录深度研究文档

## 目录

- [1. 场景与职责](#1-场景与职责)
- [2. 功能点目的](#2-功能点目的)
- [3. 具体技术实现](#3-具体技术实现)
  - [3.1 关键流程](#31-关键流程)
  - [3.2 数据结构](#32-数据结构)
  - [3.3 协议与配置格式](#33-协议与配置格式)
- [4. 关键代码路径与文件引用](#4-关键代码路径与文件引用)
- [5. 依赖与外部交互](#5-依赖与外部交互)
- [6. 风险、边界与改进建议](#6-风险边界与改进建议)

---

## 1. 场景与职责

`codex-rs/skills/src/assets/samples/skill-installer/agents/` 目录是 **Skill Installer** 系统技能的元数据配置目录，包含该技能的 UI 界面配置和标识信息。

### 1.1 在整体架构中的位置

```
codex-rs/skills/src/assets/samples/          # 系统预装技能样本目录
├── skill-installer/                         # Skill Installer 技能包
│   ├── agents/                              # 【本目录】UI/产品元数据配置
│   │   └── openai.yaml                      # OpenAI 产品特定的界面配置
│   ├── assets/                              # 图标资源
│   ├── scripts/                             # 安装脚本工具
│   ├── SKILL.md                             # 技能主文档（前端内容）
│   └── LICENSE.txt                          # Apache 2.0 许可证
├── skill-creator/                           # 另一个系统技能（Skill Creator）
└── openai-docs/                             # OpenAI 文档技能
```

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **UI 元数据提供** | 定义技能在 Codex UI 中的显示名称、描述、图标 |
| **产品集成配置** | 提供 OpenAI 产品特定的扩展配置（如品牌色、默认提示词） |
| **界面一致性** | 确保技能在技能列表、芯片提示、详情页中呈现一致 |

### 1.3 调用方与被调用方

**调用方（消费者）：**
- `codex-rs/core/src/skills/loader.rs` - 技能加载器，解析 `agents/openai.yaml`
- `codex-rs/core/src/skills/manager.rs` - 技能管理器，管理技能生命周期
- Codex TUI/GUI 前端 - 展示技能列表和详情

**被调用方（依赖）：**
- 无直接代码依赖，但依赖同级目录资源：
  - `../assets/skill-installer-small.svg` - 小图标
  - `../assets/skill-installer.png` - 大图标
  - `../SKILL.md` - 技能主文档

---

## 2. 功能点目的

### 2.1 openai.yaml 功能目的

`openai.yaml` 是技能的**扩展元数据文件**，与 `SKILL.md` 中的 YAML frontmatter 共同构成完整的技能描述：

| 文件 | 用途 | 受众 |
|------|------|------|
| `SKILL.md` frontmatter | 技能名称、描述、短描述 | LLM/Agent 理解技能用途 |
| `agents/openai.yaml` | 界面显示、图标、品牌配置 | UI 渲染/产品集成 |

### 2.2 Skill Installer 技能的业务目的

Skill Installer 是一个**系统级技能**，允许用户：

1. **列出可安装技能** - 从 `openai/skills` 仓库的 `.curated` 或 `.experimental` 目录获取技能列表
2. **安装精选技能** - 通过技能名称从精选列表安装
3. **安装第三方技能** - 从任意 GitHub 仓库路径安装技能

### 2.3 UI 配置的具体作用

```yaml
interface:
  display_name: "Skill Installer"           # 在技能列表中显示的名称
  short_description: "Install curated skills..."  # 技能卡片描述
  icon_small: "./assets/skill-installer-small.svg"  # 16x16 或 24x24 图标
  icon_large: "./assets/skill-installer.png"        # 更大尺寸图标
```

这些配置使 Skill Installer 在 Codex UI 中以专业、一致的方式呈现，而非仅显示文件名或内部标识符。

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 技能加载流程（涉及本目录）

```
1. Codex 启动
   └── SkillsManager::new()
       └── install_system_skills(codex_home)
           └── 将 embedded skills（包括 skill-installer）复制到
               $CODEX_HOME/skills/.system/

2. 技能扫描
   └── load_skills_from_roots(roots)
       └── discover_skills_under_root(root, scope, outcome)
           └── 遍历目录，查找 SKILL.md
               └── 发现 skill-installer/SKILL.md
                   └── parse_skill_file(path, scope)
                       ├── 解析 SKILL.md frontmatter
                       └── load_skill_metadata(path)  
                           └── 检查并解析 agents/openai.yaml ← 【本目录文件被读取】
```

#### 3.1.2 openai.yaml 解析流程

```rust
// codex-rs/core/src/skills/loader.rs

fn load_skill_metadata(skill_path: &Path) -> LoadedSkillMetadata {
    // 1. 确定元数据文件路径: <skill_dir>/agents/openai.yaml
    let metadata_path = skill_dir
        .join(SKILLS_METADATA_DIR)  // "agents"
        .join(SKILLS_METADATA_FILENAME);  // "openai.yaml"
    
    // 2. 检查文件存在性
    if !metadata_path.exists() {
        return LoadedSkillMetadata::default();
    }
    
    // 3. 读取并解析 YAML
    let contents = fs::read_to_string(&metadata_path)?;
    let parsed: SkillMetadataFile = serde_yaml::from_str(&contents)?;
    
    // 4. 解析 interface 字段
    let interface = resolve_interface(parsed.interface, skill_dir);
}

fn resolve_interface(interface: Option<Interface>, skill_dir: &Path) -> Option<SkillInterface> {
    let interface = interface?;
    Some(SkillInterface {
        display_name: resolve_str(interface.display_name, ...),
        short_description: resolve_str(interface.short_description, ...),
        // 图标路径解析：相对于技能目录，必须在 assets/ 下
        icon_small: resolve_asset_path(skill_dir, "interface.icon_small", interface.icon_small),
        icon_large: resolve_asset_path(skill_dir, "interface.icon_large", interface.icon_large),
        brand_color: resolve_color_str(interface.brand_color, ...),
        default_prompt: resolve_str(interface.default_prompt, ...),
    })
}
```

#### 3.1.3 图标路径安全校验流程

```rust
fn resolve_asset_path(skill_dir: &Path, field: &'static str, path: Option<PathBuf>) -> Option<PathBuf> {
    let path = path?;
    
    // 规则 1: 必须是相对路径
    if path.is_absolute() {
        tracing::warn!("ignoring {field}: icon must be a relative assets path");
        return None;
    }
    
    // 规则 2: 规范化路径，拒绝 .. 遍历
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
    
    // 规则 3: 必须在 assets/ 目录下
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

### 3.2 数据结构

#### 3.2.1 openai.yaml 结构定义

```rust
// codex-rs/core/src/skills/loader.rs

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
```

#### 3.2.2 内存模型（SkillMetadata）

```rust
// codex-rs/core/src/skills/model.rs

pub struct SkillMetadata {
    pub name: String,                          // 来自 SKILL.md
    pub description: String,                   // 来自 SKILL.md
    pub short_description: Option<String>,     // 来自 SKILL.md
    pub interface: Option<SkillInterface>,     // ← 来自 agents/openai.yaml
    pub dependencies: Option<SkillDependencies>,
    pub policy: Option<SkillPolicy>,
    pub permission_profile: Option<PermissionProfile>,
    pub managed_network_override: Option<SkillManagedNetworkOverride>,
    pub path_to_skills_md: PathBuf,
    pub scope: SkillScope,
}

pub struct SkillInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,
}
```

### 3.3 协议与配置格式

#### 3.3.1 openai.yaml 完整格式规范

```yaml
interface:
  display_name: "Optional user-facing name"           # 最大 64 字符
  short_description: "Optional user-facing description" # 最大 1024 字符
  icon_small: "./assets/small-400px.png"              # 相对路径，必须在 assets/ 下
  icon_large: "./assets/large-logo.svg"               # 相对路径，必须在 assets/ 下
  brand_color: "#3B82F6"                              # 必须是 #RRGGBB 格式
  default_prompt: "Optional surrounding prompt..."    # 最大 1024 字符

dependencies:
  tools:
    - type: "mcp"
      value: "github"
      description: "GitHub MCP server"
      transport: "streamable_http"
      url: "https://api.githubcopilot.com/mcp/"

policy:
  allow_implicit_invocation: true

permissions:
  network:
    enabled: true
    allowed_domains: ["api.github.com"]
    denied_domains: []
  file_system:
    read: ["./data"]
    write: ["./output"]
  macos:
    # macOS Seatbelt 扩展配置
```

#### 3.3.2 Skill Installer 实际配置

```yaml
# codex-rs/skills/src/assets/samples/skill-installer/agents/openai.yaml
interface:
  display_name: "Skill Installer"
  short_description: "Install curated skills from openai/skills or other repos"
  icon_small: "./assets/skill-installer-small.svg"
  icon_large: "./assets/skill-installer.png"
```

**注意：** Skill Installer 的 `openai.yaml` 仅配置了 `interface` 部分，未配置 `dependencies`、`policy` 或 `permissions`，这意味着：
- 该技能执行时继承当前 turn 的 sandbox 策略
- 没有额外的网络或文件系统权限声明
- 允许隐式调用（`allow_implicit_invocation` 默认为 true）

---

## 4. 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `openai.yaml` | YAML 配置 | Skill Installer 的 UI 元数据配置 |

### 4.2 相关资源文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `../assets/skill-installer-small.svg` | SVG 图标 | 16x16/24x24 小图标 |
| `../assets/skill-installer.png` | PNG 图标 | 大图标 |
| `../SKILL.md` | Markdown | 技能主文档，包含 frontmatter |
| `../scripts/install-skill-from-github.py` | Python 脚本 | 技能安装实现 |
| `../scripts/list-skills.py` | Python 脚本 | 技能列表获取 |
| `../scripts/github_utils.py` | Python 模块 | GitHub API 工具函数 |

### 4.3 核心代码引用路径

| 代码路径 | 功能 |
|----------|------|
| `codex-rs/core/src/skills/loader.rs:602-655` | `load_skill_metadata()` 解析 openai.yaml |
| `codex-rs/core/src/skills/loader.rs:693-722` | `resolve_interface()` 处理界面配置 |
| `codex-rs/core/src/skills/loader.rs:783-829` | `resolve_asset_path()` 图标路径安全校验 |
| `codex-rs/core/src/skills/model.rs:56-63` | `SkillInterface` 结构定义 |
| `codex-rs/core/src/skills/loader.rs:133-136` | 常量定义：`SKILLS_METADATA_DIR`、`SKILLS_METADATA_FILENAME` |
| `codex-rs/skills/src/lib.rs:12` | 系统技能嵌入：`include_dir!` 包含 samples 目录 |
| `codex-rs/skills/src/lib.rs:47-78` | `install_system_skills()` 安装系统技能到缓存目录 |

### 4.4 常量定义

```rust
// codex-rs/core/src/skills/loader.rs

const SKILLS_FILENAME: &str = "SKILL.md";
const AGENTS_DIR_NAME: &str = ".agents";        // 仓库级技能目录
const SKILLS_METADATA_DIR: &str = "agents";     // 技能元数据子目录
const SKILLS_METADATA_FILENAME: &str = "openai.yaml";  // 元数据文件名

// 长度限制常量
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
const MAX_SHORT_DESCRIPTION_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEFAULT_PROMPT_LEN: usize = MAX_DESCRIPTION_LEN;
```

---

## 5. 依赖与外部交互

### 5.1 编译时依赖

| 依赖 | 用途 |
|------|------|
| `include_dir` crate | 将技能样本目录嵌入二进制 |
| `serde_yaml` | YAML 解析 |
| `serde` | 反序列化 |

### 5.2 运行时依赖

| 依赖 | 用途 |
|------|------|
| `$CODEX_HOME` 环境变量 | 确定技能安装目标目录（默认 `~/.codex`） |
| GitHub API | `list-skills.py` 和 `install-skill-from-github.py` 调用 GitHub API |
| `GITHUB_TOKEN` / `GH_TOKEN` | 可选，用于私有仓库访问 |

### 5.3 Skill Installer 脚本的外部交互

```
┌─────────────────────────────────────────────────────────────────┐
│                     Skill Installer 技能                         │
│  ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────┐ │
│  │ list-skills │  │ install-skill-from  │  │  github_utils   │ │
│  │   .py       │  │    -github.py       │  │     .py         │ │
│  └──────┬──────┘  └──────────┬──────────┘  └─────────────────┘ │
│         │                    │                                   │
│         └────────────────────┘                                   │
│                    │                                             │
│         ┌──────────▼──────────┐                                  │
│         │   GitHub API        │                                  │
│         │  api.github.com     │                                  │
│         │  codeload.github.com│                                  │
│         └─────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.4 与 Skill Creator 的对比

| 特性 | Skill Installer | Skill Creator |
|------|-----------------|---------------|
| `openai.yaml` 内容 | 仅 `interface` | 仅 `interface` |
| 图标 | SVG + PNG | SVG + PNG |
| 脚本功能 | 安装/列出技能 | 创建/初始化技能 |
| 依赖外部服务 | GitHub API | 无（本地文件操作） |
| 网络权限 | 需要（下载技能） | 不需要 |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 安全风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 路径遍历 | 低 | `resolve_asset_path()` 已校验 `..` 和绝对路径，但需确保所有调用点都使用此函数 |
| 图标资源缺失 | 低 | 若 `assets/` 中的图标被删除，UI 会回退到默认显示 |
| GitHub API 限流 | 中 | 未认证请求有 60次/小时 限制，需文档说明 `GITHUB_TOKEN` 的使用 |

#### 6.1.2 功能边界

| 边界 | 说明 |
|------|------|
| 仅支持 GitHub | `install-skill-from-github.py` 明确检查 `netloc != "github.com"` 时报错 |
| 安装冲突 | 若目标目录已存在同名技能，安装会中止（非覆盖） |
| 沙箱限制 | 脚本需要网络访问，在 sandbox 环境中运行时需要权限提升 |
| 重启要求 | 安装后需要重启 Codex 才能加载新技能 |

### 6.2 改进建议

#### 6.2.1 配置增强

```yaml
# 建议添加 policy 配置以明确调用行为
policy:
  allow_implicit_invocation: false  # Skill Installer 通常需要显式调用
```

#### 6.2.2 错误处理改进

- 当前 `openai.yaml` 解析失败时静默忽略（返回 `LoadedSkillMetadata::default()`）
- 建议对系统技能（`SkillScope::System`）增加更严格的校验，解析失败时记录 error 而非 warn

#### 6.2.3 文档改进

- `skill-installer/agents/openai.yaml` 缺少注释说明各字段用途
- 建议参考 `skill-creator/references/openai_yaml.md` 添加字段说明

#### 6.2.4 测试覆盖

- 当前测试主要覆盖技能加载器（`loader_tests.rs`）
- 建议增加系统技能端到端测试，验证：
  - `openai.yaml` 解析后的 `SkillInterface` 字段正确性
  - 图标路径解析和存在性校验
  - 技能安装脚本的集成测试

### 6.3 维护注意事项

1. **图标更新**：修改 `assets/` 中的图标后，需要同步更新 `openai.yaml` 中的路径（若文件名变化）
2. **版本兼容性**：`openai.yaml` 格式变更需同步更新 `loader.rs` 中的解析逻辑
3. **国际化**：当前 `display_name` 和 `short_description` 为英文，未来若支持 i18n 需考虑多语言配置方案

---

## 附录：文件完整内容

### A.1 openai.yaml

```yaml
interface:
  display_name: "Skill Installer"
  short_description: "Install curated skills from openai/skills or other repos"
  icon_small: "./assets/skill-installer-small.svg"
  icon_large: "./assets/skill-installer.png"
```

### A.2 相关常量汇总

```rust
// 目录结构常量
SYSTEM_SKILLS_DIR_NAME: &str = ".system";           // 系统技能缓存目录
SKILLS_DIR_NAME: &str = "skills";                   // 技能根目录名
AGENTS_DIR_NAME: &str = ".agents";                  // 仓库级技能目录（如 .agents/skills/）
SKILLS_METADATA_DIR: &str = "agents";                // 技能元数据子目录
SKILLS_METADATA_FILENAME: &str = "openai.yaml";     // 元数据文件名
SKILLS_FILENAME: &str = "SKILL.md";                 // 技能主文档名

// 长度限制
MAX_NAME_LEN: usize = 64;
MAX_DESCRIPTION_LEN: usize = 1024;
MAX_SHORT_DESCRIPTION_LEN: usize = 1024;
MAX_DEFAULT_PROMPT_LEN: usize = 1024;

// 扫描限制
MAX_SCAN_DEPTH: usize = 6;
MAX_SKILLS_DIRS_PER_ROOT: usize = 2000;
```

---

*文档生成时间: 2026-03-22*
*研究对象版本: codex-rs/skills/src/assets/samples/skill-installer/agents/openai.yaml*
