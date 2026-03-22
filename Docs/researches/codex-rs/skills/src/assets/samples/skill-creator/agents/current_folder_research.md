# 研究文档：codex-rs/skills/src/assets/samples/skill-creator/agents

## 目录

- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位

`codex-rs/skills/src/assets/samples/skill-creator/agents/` 是 **Skill Creator** 系统技能的元数据配置目录，包含该技能的 UI 展示配置和接口定义。该目录是 Codex CLI/IDE 中技能发现、展示和调用的关键组成部分。

### 核心职责

1. **UI 元数据配置**：定义技能在 Codex 产品界面中的展示方式（名称、描述、图标等）
2. **人机交互接口**：提供用户可读的技能描述和默认提示词
3. **依赖声明**：声明技能运行所需的外部工具依赖（如 MCP 服务器）
4. **策略配置**：定义技能的调用策略（如是否允许隐式调用）

### 在 Skill 体系中的位置

```
skill-creator/                    # 技能根目录
├── SKILL.md                      # 技能核心文档（必需）
├── agents/                       # UI/机器可读元数据（推荐）
│   └── openai.yaml              # OpenAI 产品专用配置
├── scripts/                      # 可执行脚本
│   ├── init_skill.py            # 技能初始化脚本
│   ├── generate_openai_yaml.py  # 生成 openai.yaml
│   └── quick_validate.py        # 快速验证脚本
├── references/                   # 参考文档
│   └── openai_yaml.md           # openai.yaml 格式规范
├── assets/                       # 静态资源
│   ├── skill-creator-small.svg
│   └── skill-creator.png
└── license.txt                   # Apache 2.0 许可证
```

### 与调用方的关系

| 调用方 | 用途 |
|--------|------|
| `codex-core` 的 Skill Loader | 读取 `openai.yaml` 解析 Skill 元数据 |
| `codex-tui` / IDE 插件 | 展示技能列表、芯片、图标 |
| `init_skill.py` | 生成新的 `openai.yaml` 文件 |
| `generate_openai_yaml.py` | 更新/重新生成配置 |

---

## 功能点目的

### 1. 界面展示配置 (`interface` 段)

**目的**：让 Skill 在 Codex UI 中以专业、一致的方式呈现

| 字段 | 当前值 | 用途 |
|------|--------|------|
| `display_name` | "Skill Creator" | 技能列表中显示的人类可读名称 |
| `short_description` | "Create or update a skill" | 技能芯片/列表中的简短描述（25-64字符） |
| `icon_small` | `./assets/skill-creator-small.svg` | 小图标（用于芯片、列表） |
| `icon_large` | `./assets/skill-creator.png` | 大图标（用于详情页） |

**约束**：
- `short_description` 必须在 25-64 字符之间
- 图标路径必须是相对于技能目录的 `./assets/` 子路径
- 图标路径不能包含 `..` 或绝对路径

### 2. 依赖声明 (`dependencies` 段)

**目的**：声明 Skill 运行所需的外部工具（当前 skill-creator 未使用，但其他技能如 openai-docs 使用）

```yaml
dependencies:
  tools:
    - type: "mcp"
      value: "openaiDeveloperDocs"
      description: "OpenAI Developer Docs MCP server"
      transport: "streamable_http"
      url: "https://developers.openai.com/mcp"
```

### 3. 调用策略 (`policy` 段)

**目的**：控制技能的自动触发行为

```yaml
policy:
  allow_implicit_invocation: true  # 默认为 true，设为 false 时需显式通过 $skill 调用
```

---

## 具体技术实现

### 1. 文件格式规范

**格式**：YAML，遵循 `references/openai_yaml.md` 定义的规范

**完整 Schema**：
```yaml
interface:
  display_name: "string"           # 人类可读名称
  short_description: "string"      # 简短描述（25-64字符）
  icon_small: "./assets/..."       # 小图标路径
  icon_large: "./assets/..."       # 大图标路径
  brand_color: "#RRGGBB"           # 品牌色（可选）
  default_prompt: "string"         # 默认提示词（可选）

dependencies:
  tools:
    - type: "mcp"                  # 依赖类型
      value: "identifier"          # 依赖标识
      description: "string"        # 人类可读描述
      transport: "streamable_http" # 传输方式
      url: "https://..."           # 服务 URL
      command: "string"            # 本地命令（可选）

policy:
  allow_implicit_invocation: true  # 是否允许隐式调用

permissions:                       # 权限配置（可选）
  file_system:
    read:
      - "./data"
    write:
      - "./output"
  network:
    enabled: true
    allowed_domains:
      - "api.example.com"
```

### 2. 生成流程

**入口脚本**：`scripts/init_skill.py`

```python
# 关键调用链
init_skill.py 
  └── write_openai_yaml(skill_dir, skill_name, interface_overrides)
      └── 生成 agents/openai.yaml
```

**自动生成逻辑**（`scripts/generate_openai_yaml.py`）：

1. **display_name 生成**：
   ```python
   def format_display_name(skill_name):
       # 将 hyphen-case 转换为 Title Case
       # 处理首字母大写、小词（and, or, to, up, with）、品牌名、缩写
       "my-cool-skill" → "My Cool Skill"
       "github-helper" → "GitHub Helper"
       "api-tester"    → "API Tester"
   ```

2. **short_description 生成**：
   ```python
   def generate_short_description(display_name):
       # 尝试多个模板，确保长度在 25-64 字符
       "Help with {display_name} tasks"
       "Help with {display_name} tasks and workflows"
       "{display_name} helper"
       "{display_name} tools"
   ```

3. **YAML 转义**：
   ```python
   def yaml_quote(value):
       # 转义反斜杠、双引号、换行符
       escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
       return f'"{escaped}"'
   ```

### 3. 解析流程

**入口**：`codex-rs/core/src/skills/loader.rs`

```rust
// 关键函数调用链
load_skills_from_roots(roots)
  └── discover_skills_under_root(root, scope, outcome)
      └── parse_skill_file(path, scope)
          └── load_skill_metadata(skill_path)
              └── 读取 agents/openai.yaml
```

**核心数据结构**（`loader.rs`）：

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
```

**路径解析逻辑**（`resolve_asset_path`）：

```rust
fn resolve_asset_path(skill_dir: &Path, field: &'static str, path: Option<PathBuf>) -> Option<PathBuf> {
    // 1. 检查路径非空
    // 2. 拒绝绝对路径
    // 3. 检查路径必须以 ./assets/ 开头
    // 4. 拒绝包含 .. 的路径
    // 5. 返回 skill_dir.join(normalized)
}
```

### 4. 权限配置处理

**权限合并流程**（`loader.rs`）：

```rust
fn normalize_permissions(permissions: Option<SkillPermissionProfile>) 
    -> (Option<PermissionProfile>, Option<SkillManagedNetworkOverride>) {
    // 1. 解析 network 配置
    // 2. 解析 file_system 配置
    // 3. 解析 macos seatbelt 扩展
    // 4. 过滤空配置
}
```

**测试用例**（`skill_approval.rs`）：

```rust
// 测试 skill 权限是否被正确应用
write_skill_metadata(home, "test-skill", r#"
permissions:
  file_system:
    write:
      - "./output"
"#);
```

---

## 关键代码路径与文件引用

### 配置文件本身

| 文件 | 路径 | 说明 |
|------|------|------|
| `openai.yaml` | `codex-rs/skills/src/assets/samples/skill-creator/agents/openai.yaml` | 本研究对象 |

### 生成工具

| 文件 | 路径 | 功能 |
|------|------|------|
| `init_skill.py` | `codex-rs/skills/src/assets/samples/skill-creator/scripts/init_skill.py` | 初始化新技能，生成 openai.yaml |
| `generate_openai_yaml.py` | `codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py` | 独立生成/更新 openai.yaml |
| `quick_validate.py` | `codex-rs/skills/src/assets/samples/skill-creator/scripts/quick_validate.py` | 验证技能结构（不验证 openai.yaml） |

### 消费代码（Rust）

| 文件 | 路径 | 功能 |
|------|------|------|
| `loader.rs` | `codex-rs/core/src/skills/loader.rs` | 解析 openai.yaml，加载 Skill 元数据 |
| `model.rs` | `codex-rs/core/src/skills/model.rs` | Skill 元数据模型定义 |
| `permissions.rs` | `codex-rs/protocol/src/permissions.rs` | 权限配置解析与验证 |
| `skill_approval.rs` | `codex-rs/core/tests/suite/skill_approval.rs` | Skill 权限集成测试 |

### 文档规范

| 文件 | 路径 | 说明 |
|------|------|------|
| `openai_yaml.md` | `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md` | openai.yaml 完整规范文档 |
| `SKILL.md` | `codex-rs/skills/src/assets/samples/skill-creator/SKILL.md` | Skill Creator 使用指南 |

### 嵌入与分发

| 文件 | 路径 | 功能 |
|------|------|------|
| `lib.rs` | `codex-rs/skills/src/lib.rs` | 使用 `include_dir!` 嵌入系统技能 |
| `build.rs` | `codex-rs/skills/build.rs` | 监控样本目录变更，触发重新构建 |

---

## 依赖与外部交互

### 1. 构建时依赖

```
build.rs
  └── 监控 src/assets/samples/ 目录变更
      └── 触发 cargo 重新构建
```

### 2. 运行时依赖

```
codex-core
  └── install_system_skills()
      └── 将嵌入的技能写入 ~/.codex/skills/.system/
          └── 包含 skill-creator/agents/openai.yaml
```

### 3. 工具链依赖

| 工具 | 用途 |
|------|------|
| `serde_yaml` | YAML 解析（Rust）|
| `PyYAML` | YAML 解析（Python）|
| `include_dir` | 编译时嵌入目录 |

### 4. 与其他技能的对比

| 技能 | openai.yaml 内容 | 特殊配置 |
|------|------------------|----------|
| `skill-creator` | interface 基础字段 | 无 |
| `skill-installer` | interface 基础字段 | 无 |
| `openai-docs` | interface + dependencies | MCP 服务器依赖 |

---

## 风险、边界与改进建议

### 1. 已知风险

#### 风险 1：路径遍历攻击

**描述**：`icon_small`/`icon_large` 如果允许 `..` 可能导致读取技能目录外文件

**缓解**：`resolve_asset_path` 函数已实施以下检查：
- 拒绝绝对路径
- 拒绝包含 `..` 的路径
- 强制路径以 `./assets/` 开头

**代码位置**：`loader.rs:783-829`

#### 风险 2：YAML 解析失败导致 Skill 加载失败

**描述**：`openai.yaml` 格式错误可能导致整个 Skill 无法加载

**缓解**：`load_skill_metadata` 使用 "fail open" 策略：
```rust
// 可选元数据不应阻止加载 SKILL.md
let Some(skill_dir) = skill_path.parent() else {
    return LoadedSkillMetadata::default();  // 返回默认值而非错误
};
```

#### 风险 3：图标文件缺失

**描述**：配置的图标路径指向不存在的文件

**现状**：当前实现仅在 UI 层处理，无运行时验证

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| `openai.yaml` 不存在 | Skill 仍可加载，使用 SKILL.md 中的基础元数据 |
| `short_description` 过长 | Python 生成器自动截断；Rust 解析器发出警告并忽略 |
| `brand_color` 格式错误 | 解析器验证 `#RRGGBB` 格式，错误时忽略该字段 |
| 权限配置与沙箱冲突 | 权限在 `skill_approval.rs` 中被测试，确保正确应用 |

### 3. 改进建议

#### 建议 1：添加图标文件存在性验证

**优先级**：中

**实现**：在 `resolve_asset_path` 中添加文件存在检查：

```rust
let full_path = skill_dir.join(normalized);
if !full_path.exists() {
    tracing::warn!("icon file does not exist: {}", full_path.display());
    return None;
}
```

#### 建议 2：统一验证工具

**优先级**：中

**现状**：`quick_validate.py` 不验证 `openai.yaml`

**改进**：扩展验证器检查：
- YAML 格式有效性
- 必需字段存在性
- 图标路径有效性
- 颜色格式正确性

#### 建议 3：版本控制

**优先级**：低

**建议**：在 `openai.yaml` 中添加 `version` 字段，便于未来格式演进：

```yaml
version: "1.0"
interface:
  ...
```

#### 建议 4：文档同步

**优先级**：中

**现状**：`references/openai_yaml.md` 与实际代码实现可能存在偏差

**建议**：
1. 将规范文档转换为 JSON Schema
2. 使用 schema 验证测试确保文档与实现同步
3. 在 CI 中添加 schema 验证步骤

#### 建议 5：国际化支持

**优先级**：低

**现状**：`display_name` 和 `short_description` 仅支持单一语言

**建议**：未来支持多语言：

```yaml
interface:
  display_name:
    en: "Skill Creator"
    zh: "技能创建器"
```

### 4. 测试覆盖

**当前测试**（`skill_approval.rs`）：
- ✅ 权限配置解析与应用
- ✅ Skill 元数据加载
- ✅ 沙箱权限继承

**缺失测试**：
- ❌ 图标路径解析边界
- ❌ YAML 格式错误处理
- ❌ 多字段组合验证

---

## 附录：关键常量定义

```rust
// loader.rs
const SKILLS_METADATA_DIR: &str = "agents";
const SKILLS_METADATA_FILENAME: &str = "openai.yaml";
const MAX_NAME_LEN: usize = 64;
const MAX_DESCRIPTION_LEN: usize = 1024;
const MAX_SHORT_DESCRIPTION_LEN: usize = MAX_DESCRIPTION_LEN;
const MAX_DEFAULT_PROMPT_LEN: usize = MAX_DESCRIPTION_LEN;
```

```python
# generate_openai_yaml.py
ALLOWED_INTERFACE_KEYS = {
    "display_name",
    "short_description",
    "icon_small",
    "icon_large",
    "brand_color",
    "default_prompt",
}
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/skills/src/assets/samples/skill-creator/agents/*
