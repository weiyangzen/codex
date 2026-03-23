# openai_yaml.md 研究文档

## 文件位置

- **目标文件**: `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md`
- **研究文档**: `Docs/researches/codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md_research.md`

---

## 1. 场景与职责

### 1.1 文件定位

`openai_yaml.md` 是 **Skill Creator** 技能的参考文档，用于指导 Codex 在创建或更新技能时正确生成 `agents/openai.yaml` 文件。该文件属于 Skill Creator 技能的 `references/` 目录，遵循 Skill Creator 的渐进式披露设计原则——仅在需要生成 UI 元数据时才被加载。

### 1.2 核心职责

该文档定义了 `agents/openai.yaml` 的完整规范，包括：

1. **UI 展示元数据**: 定义技能在 UI 列表和芯片中显示的名称、描述、图标、品牌色等
2. **依赖声明**: 定义技能所需的 MCP 工具依赖
3. **策略配置**: 定义技能的隐式调用策略

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| 创建新技能 | 通过 `init_skill.py` 自动生成 `agents/openai.yaml` |
| 更新技能元数据 | 通过 `generate_openai_yaml.py` 重新生成 |
| 手动编辑 | 开发者根据文档规范手动修改 YAML 文件 |

### 1.4 目标读者

- **Codex Agent**: 在协助用户创建技能时，需要引用此文档生成正确的 YAML 结构
- **Skill 开发者**: 需要理解 UI 元数据字段的约束和最佳实践

---

## 2. 功能点目的

### 2.1 功能点总览

```yaml
# agents/openai.yaml 结构
interface:          # UI 展示层配置
  display_name: "..."
  short_description: "..."
  icon_small: "..."
  icon_large: "..."
  brand_color: "..."
  default_prompt: "..."

dependencies:       # 工具依赖配置
  tools:
    - type: "mcp"
      value: "..."
      description: "..."
      transport: "..."
      url: "..."

policy:             # 调用策略配置
  allow_implicit_invocation: true/false
```

### 2.2 各功能点详细说明

#### 2.2.1 `interface` - UI 展示层

| 字段 | 类型 | 长度限制 | 目的 |
|------|------|----------|------|
| `display_name` | string | ≤64 chars | 人类可读的标题，显示在 UI 技能列表和芯片中 |
| `short_description` | string | 25-64 chars | 简短描述，用于快速扫描 |
| `icon_small` | path | 相对路径 | 小图标路径（建议 400px），相对于技能目录 |
| `icon_large` | path | 相对路径 | 大图标/Logo 路径，相对于技能目录 |
| `brand_color` | hex | #RRGGBB | UI 强调色（如徽章颜色） |
| `default_prompt` | string | ≤1024 chars | 调用技能时插入的默认提示片段 |

**关键约束**:
- 所有字符串值必须加引号
- 键名不加引号
- `default_prompt` 必须显式提及技能名称（格式: `$skill-name`）
- 图标路径必须是相对于技能目录的路径，且位于 `assets/` 目录下

#### 2.2.2 `dependencies.tools` - MCP 工具依赖

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | 是 | 依赖类别，目前仅支持 `mcp` |
| `value` | string | 是 | 工具或依赖的标识符 |
| `description` | string | 否 | 人类可读的依赖说明 |
| `transport` | string | MCP 时需要 | 连接类型，如 `streamable_http` |
| `url` | string | MCP 时需要 | MCP 服务器 URL |

**目的**: 声明技能运行所需的外部 MCP 工具，使系统能够在技能被调用前准备好相应的工具环境。

#### 2.2.3 `policy.allow_implicit_invocation` - 调用策略

| 值 | 行为 |
|----|------|
| `true` (默认) | 技能默认注入到模型上下文中，可被隐式触发 |
| `false` | 技能不自动注入，只能通过显式 `$skill` 语法调用 |

**目的**: 控制技能的自动触发行为。对于敏感操作或需要显式控制的技能，应设置为 `false`。

---

## 3. 具体技术实现

### 3.1 数据流与处理流程

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  SKILL.md       │────▶│  init_skill.py       │────▶│ agents/openai.yaml│
│  (name/desc)    │     │  generate_openai_yaml.py│   │ (UI metadata)   │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
         │                         │                         │
         ▼                         ▼                         ▼
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Core Skill     │     │  quick_validate.py   │     │  TUI Display    │
│  Loader         │     │  (validation)        │     │  (skills list)  │
└─────────────────┘     └──────────────────────┘     └─────────────────┘
```

### 3.2 核心数据结构

#### 3.2.1 Rust 协议层定义 (`codex-rs/protocol/src/protocol.rs`)

```rust
// 技能元数据（Wire 协议）
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS)]
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub short_description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interface: Option<SkillInterface>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dependencies: Option<SkillDependencies>,
    pub path: PathBuf,
    pub scope: SkillScope,
    pub enabled: bool,
}

// UI 接口定义
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS, PartialEq, Eq)]
pub struct SkillInterface {
    pub display_name: Option<String>,
    pub short_description: Option<String>,
    pub icon_small: Option<PathBuf>,
    pub icon_large: Option<PathBuf>,
    pub brand_color: Option<String>,
    pub default_prompt: Option<String>,
}

// 依赖定义
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS, PartialEq, Eq)]
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS, PartialEq, Eq)]
pub struct SkillToolDependency {
    #[serde(rename = "type")]
    pub r#type: String,
    pub value: String,
    pub description: Option<String>,
    pub transport: Option<String>,
    pub command: Option<String>,
    pub url: Option<String>,
}
```

#### 3.2.2 Core 层内部模型 (`codex-rs/core/src/skills/model.rs`)

```rust
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

pub struct SkillPolicy {
    pub allow_implicit_invocation: Option<bool>,
    pub products: Vec<Product>,
}
```

### 3.3 YAML 生成脚本实现

#### 3.3.1 `generate_openai_yaml.py`

关键函数:

```python
def write_openai_yaml(skill_dir, skill_name, raw_overrides):
    """生成 agents/openai.yaml 文件"""
    # 1. 解析 interface 覆盖参数
    overrides, optional_order = parse_interface_overrides(raw_overrides)
    
    # 2. 生成 display_name（自动格式化）
    display_name = overrides.get("display_name") or format_display_name(skill_name)
    
    # 3. 生成 short_description（自动调整长度到 25-64 字符）
    short_description = overrides.get("short_description") or generate_short_description(display_name)
    
    # 4. 构建 YAML 内容
    interface_lines = [
        "interface:",
        f'  display_name: {yaml_quote(display_name)}',
        f'  short_description: {yaml_quote(short_description)}',
    ]
    
    # 5. 添加可选字段（按传入顺序）
    for key in optional_order:
        value = overrides.get(key)
        if value is not None:
            interface_lines.append(f'  {key}: {yaml_quote(value)}')
    
    # 6. 写入文件
    output_path.write_text("\n".join(interface_lines) + "\n")
```

**自动格式化规则**:
- **首字母大写**: 每个单词首字母大写
- **缩写词处理**: API, CLI, LLM, PDF 等保持大写
- **品牌名处理**: openai → OpenAI, github → GitHub
- **小词处理**: and, or, to, up, with 在非首位置小写

#### 3.3.2 `init_skill.py`

初始化流程:

```python
def init_skill(skill_name, path, resources, include_examples, interface_overrides):
    # 1. 创建技能目录
    skill_dir.mkdir(parents=True, exist_ok=False)
    
    # 2. 生成 SKILL.md 模板
    skill_content = SKILL_TEMPLATE.format(skill_name=skill_name, skill_title=skill_title)
    skill_md_path.write_text(skill_content)
    
    # 3. 创建 agents/openai.yaml
    write_openai_yaml(skill_dir, skill_name, interface_overrides)
    
    # 4. 创建资源目录（可选）
    create_resource_dirs(skill_dir, skill_name, skill_title, resources, include_examples)
```

### 3.4 技能加载器实现 (`codex-rs/core/src/skills/loader.rs`)

#### 3.4.1 元数据加载流程

```rust
fn load_skill_metadata(skill_path: &Path) -> LoadedSkillMetadata {
    // 1. 确定技能目录
    let Some(skill_dir) = skill_path.parent() else { return default };
    
    // 2. 构建元数据文件路径: agents/openai.yaml
    let metadata_path = skill_dir.join(SKILLS_METADATA_DIR).join(SKILLS_METADATA_FILENAME);
    if !metadata_path.exists() { return default }
    
    // 3. 解析 YAML
    let parsed: SkillMetadataFile = serde_yaml::from_str(&contents)?;
    
    // 4. 解析各字段
    LoadedSkillMetadata {
        interface: resolve_interface(interface, skill_dir),
        dependencies: resolve_dependencies(dependencies),
        policy: resolve_policy(policy),
        permission_profile,
        managed_network_override,
    }
}
```

#### 3.4.2 图标路径解析 (`resolve_asset_path`)

```rust
fn resolve_asset_path(skill_dir: &Path, field: &'static str, path: Option<PathBuf>) -> Option<PathBuf> {
    let path = path?;
    
    // 约束 1: 必须是相对路径
    if path.is_absolute() { return None }
    
    // 约束 2: 不能包含 .. 组件
    for component in path.components() {
        if matches!(component, Component::ParentDir) { return None }
    }
    
    // 约束 3: 必须位于 assets/ 目录下
    let mut components = normalized.components();
    match components.next() {
        Some(Component::Normal(component)) if component == "assets" => {}
        _ => return None,
    }
    
    Some(skill_dir.join(normalized))
}
```

#### 3.4.3 品牌颜色验证 (`resolve_color_str`)

```rust
fn resolve_color_str(value: Option<String>, field: &'static str) -> Option<String> {
    let value = value?;
    let value = value.trim();
    
    // 必须是 #RRGGBB 格式
    let mut chars = value.chars();
    if value.len() == 7 
        && chars.next() == Some('#') 
        && chars.all(|c| c.is_ascii_hexdigit()) {
        Some(value.to_string())
    } else {
        tracing::warn!("ignoring {field}: expected #RRGGBB, got {value}");
        None
    }
}
```

### 3.5 验证脚本 (`quick_validate.py`)

验证规则:

```python
def validate_skill(skill_path):
    # 1. 检查 SKILL.md 存在
    if not skill_md.exists(): return False, "SKILL.md not found"
    
    # 2. 检查 YAML frontmatter 格式
    if not content.startswith("---"): return False, "No YAML frontmatter found"
    
    # 3. 解析 frontmatter
    frontmatter = yaml.safe_load(frontmatter_text)
    
    # 4. 检查必需字段
    if "name" not in frontmatter: return False, "Missing 'name' in frontmatter"
    if "description" not in frontmatter: return False, "Missing 'description' in frontmatter"
    
    # 5. 检查 name 格式（hyphen-case）
    if not re.match(r"^[a-z0-9-]+$", name): return False, "Name should be hyphen-case"
    
    # 6. 检查 description 长度
    if len(description) > 1024: return False, "Description too long"
```

---

## 4. 关键代码路径与文件引用

### 4.1 文档本身

| 文件 | 作用 |
|------|------|
| `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md` | 本研究文档的目标文件，定义 openai.yaml 规范 |

### 4.2 调用方（消费者）

| 文件 | 作用 |
|------|------|
| `codex-rs/skills/src/assets/samples/skill-creator/SKILL.md` | Skill Creator 的主文档，引用 openai_yaml.md 作为参考 |
| `codex-rs/skills/src/assets/samples/skill-creator/scripts/init_skill.py` | 初始化技能时生成 openai.yaml |
| `codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py` | 生成/更新 openai.yaml 的专用脚本 |

### 4.3 被调用方（实现层）

| 文件 | 作用 |
|------|------|
| `codex-rs/core/src/skills/loader.rs` | 技能加载器，解析 agents/openai.yaml |
| `codex-rs/core/src/skills/model.rs` | 技能内部数据模型定义 |
| `codex-rs/protocol/src/protocol.rs` | Wire 协议定义（SkillMetadata, SkillInterface 等） |

### 4.4 配置与测试

| 文件 | 作用 |
|------|------|
| `codex-rs/skills/src/assets/samples/skill-creator/scripts/quick_validate.py` | 技能验证脚本 |
| `codex-rs/core/src/skills/loader_tests.rs` | 加载器单元测试 |
| `codex-rs/core/tests/suite/skills.rs` | 技能集成测试 |

### 4.5 UI 展示层

| 文件 | 作用 |
|------|------|
| `codex-rs/tui/src/skills_helpers.rs` | TUI 技能显示辅助函数 |
| `codex-rs/tui/src/chatwidget/skills.rs` | TUI 技能列表和选择逻辑 |
| `codex-rs/tui/src/bottom_pane/skills_toggle_view.rs` | 技能启用/禁用切换视图 |

### 4.6 示例文件

| 文件 | 作用 |
|------|------|
| `codex-rs/skills/src/assets/samples/skill-creator/agents/openai.yaml` | Skill Creator 自身的 UI 元数据 |
| `codex-rs/skills/src/assets/samples/skill-installer/agents/openai.yaml` | Skill Installer 的 UI 元数据 |
| `codex-rs/skills/src/assets/samples/openai-docs/agents/openai.yaml` | OpenAI Docs 技能的 UI 元数据（含 dependencies 示例） |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
openai_yaml.md (规范文档)
    │
    ├──▶ SKILL.md (引用规范)
    │
    ├──▶ init_skill.py (生成实现)
    │       └──▶ generate_openai_yaml.py
    │
    ├──▶ loader.rs (解析实现)
    │       ├──▶ model.rs (数据模型)
    │       └──▶ protocol.rs (Wire 协议)
    │
    └──▶ TUI/ChatWidget (展示消费)
```

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `serde_yaml` | YAML 解析（Rust 层） |
| `PyYAML` | YAML 解析（Python 脚本层） |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 5.3 协议交互

`agents/openai.yaml` 中的数据通过以下流程进入协议层：

1. **加载阶段**: `loader.rs` 读取并解析 YAML 文件
2. **转换阶段**: 内部 `SkillMetadata` 转换为协议层 `SkillMetadata`
3. **传输阶段**: 通过 App-Server Protocol v2 的 `SkillsList` RPC 传输到客户端
4. **展示阶段**: TUI 使用 `skill_display_name()` 和 `skill_description()` 辅助函数展示

### 5.4 与 SKILL.md 的关系

| 文件 | 内容 | 加载时机 |
|------|------|----------|
| `SKILL.md` | 技能名称、描述、使用指南 | 技能触发后加载 |
| `agents/openai.yaml` | UI 元数据、依赖、策略 | 系统启动时扫描加载 |

**关键区别**: `SKILL.md` 的 `name` 和 `description` 用于技能触发决策；`openai.yaml` 的 `display_name` 和 `short_description` 仅用于 UI 展示。

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 字段长度约束风险

| 字段 | 最大长度 | 风险 |
|------|----------|------|
| `name` | 64 chars | 超长名称被截断或拒绝 |
| `description` | 1024 chars | 超长描述被截断 |
| `short_description` | 64 chars | 自动生成时可能不符合 25-64 字符范围 |

**缓解措施**: `generate_openai_yaml.py` 中的 `generate_short_description()` 函数会自动调整描述长度到合规范围。

#### 6.1.2 路径安全风险

图标路径必须满足：
- 相对路径（非绝对路径）
- 位于 `assets/` 目录下
- 不包含 `..` 组件

**风险**: 恶意构造的 YAML 可能尝试引用技能目录外的文件。

**缓解措施**: `resolve_asset_path()` 函数严格验证路径组件，违规路径会被忽略并记录警告。

#### 6.1.3 隐式调用策略风险

`allow_implicit_invocation: false` 的技能仍可通过显式 `$skill` 语法调用，但：
- 用户可能不了解此语法
- 技能文档需要明确说明调用方式

### 6.2 边界情况

#### 6.2.1 缺失 openai.yaml

技能可以没有 `agents/openai.yaml` 文件，此时：
- UI 展示使用 `SKILL.md` 中的 `name` 和 `description`
- 没有图标、品牌色等视觉元素
- 没有额外依赖声明
- 隐式调用默认为 `true`

#### 6.2.2 部分字段缺失

```yaml
interface:
  display_name: "Only Name"  # short_description 缺失
```

- `short_description` 缺失时，UI 回退到 `description`
- `display_name` 缺失时，UI 回退到 `name`

#### 6.2.3 无效字段值

- 无效的品牌色（非 #RRGGBB 格式）→ 字段被忽略
- 无效的图标路径 → 字段被忽略
- 超长的字符串值 → 被截断或忽略

### 6.3 改进建议

#### 6.3.1 增强验证

当前 `quick_validate.py` 仅验证 `SKILL.md`，建议：

```python
# 新增对 agents/openai.yaml 的验证
def validate_openai_yaml(skill_path):
    openai_yaml = skill_path / "agents" / "openai.yaml"
    if not openai_yaml.exists():
        return True, "No openai.yaml (optional)"
    
    # 验证 YAML 结构
    # 验证字段类型和长度
    # 验证图标路径存在性
    # 验证品牌色格式
```

#### 6.3.2 统一配置格式

当前存在两种配置：
- `SKILL.md` frontmatter: `metadata.short-description`
- `agents/openai.yaml`: `interface.short_description`

建议逐步迁移到单一来源，或明确优先级：
```
展示优先级: interface.short_description > metadata.short-description > description
```

#### 6.3.3 扩展 dependencies 支持

当前仅支持 MCP 工具依赖，未来可扩展：

```yaml
dependencies:
  tools:
    - type: "mcp"
      ...
  env:                    # 新增：环境变量依赖
    - name: "GITHUB_TOKEN"
      description: "GitHub API token"
  python_packages:        # 新增：Python 包依赖
    - name: "pandas"
      version: ">=2.0"
```

#### 6.3.4 国际化支持

当前 `display_name` 和 `short_description` 仅支持单一语言，未来可考虑：

```yaml
interface:
  display_name:
    en: "Skill Creator"
    zh: "技能创建器"
  short_description:
    en: "Create or update a skill"
    zh: "创建或更新技能"
```

#### 6.3.5 文档增强

建议在 `openai_yaml.md` 中增加：
1. 完整的 JSON Schema 定义
2. 更多实际示例（含 dependencies 和 policy 的复杂案例）
3. 与其他技能元数据字段的关联说明
4. 版本历史（如果规范有变更）

---

## 7. 附录

### 7.1 示例 openai.yaml 文件

**基础示例**（skill-creator）:
```yaml
interface:
  display_name: "Skill Creator"
  short_description: "Create or update a skill"
  icon_small: "./assets/skill-creator-small.svg"
  icon_large: "./assets/skill-creator.png"
```

**完整示例**（openai-docs）:
```yaml
interface:
  display_name: "OpenAI Docs"
  short_description: "Reference official OpenAI docs, including upgrade guidance"
  icon_small: "./assets/openai-small.svg"
  icon_large: "./assets/openai.png"
  default_prompt: "Look up official OpenAI docs, load relevant GPT-5.4 upgrade references when applicable, and answer with concise, cited guidance."

dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

### 7.2 相关命令

```bash
# 初始化新技能（自动生成 openai.yaml）
python scripts/init_skill.py my-skill --path ~/.codex/skills --interface display_name="My Skill"

# 重新生成 openai.yaml
python scripts/generate_openai_yaml.py /path/to/skill --interface short_description="New description"

# 验证技能
python scripts/quick_validate.py /path/to/skill
```

### 7.3 参考链接

- Skill Creator SKILL.md: `codex-rs/skills/src/assets/samples/skill-creator/SKILL.md`
- Core Skills 模块: `codex-rs/core/src/skills/`
- Protocol 定义: `codex-rs/protocol/src/protocol.rs`
