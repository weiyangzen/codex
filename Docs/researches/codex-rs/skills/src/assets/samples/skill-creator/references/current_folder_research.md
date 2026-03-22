# 研究报告：codex-rs/skills/src/assets/samples/skill-creator/references

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

`codex-rs/skills/src/assets/samples/skill-creator/references/` 是 Codex CLI 内置系统技能（System Skill）`skill-creator` 的参考文档目录。该目录属于 `codex-skills` crate 的嵌入式资源，通过 `include_dir` 宏在编译时嵌入到二进制中。

### 1.2 核心职责

该目录存放 `skill-creator` 技能的参考文档，用于：

1. **指导 Skill 元数据配置**：`openai_yaml.md` 详细定义了 `agents/openai.yaml` 配置文件的字段规范、约束条件和最佳实践
2. **支持渐进式披露设计**：作为 `references/` 资源的一部分，仅在需要时加载到上下文，避免占用宝贵的上下文窗口
3. **确保 Skill 创建一致性**：为 Codex 代理提供标准化的元数据生成指南

### 1.3 在 Skill 体系中的角色

```
Skill 加载层级（由高到低优先级）：
┌─────────────────────────────────────────────────────────────┐
│  Repo Scope    →  项目级 .agents/skills/                    │
│  User Scope    →  ~/.agents/skills/ 或 $CODEX_HOME/skills/  │
│  System Scope  →  $CODEX_HOME/skills/.system/  (本目录)     │
│  Admin Scope   →  /etc/codex/skills/                        │
└─────────────────────────────────────────────────────────────┘
```

`skill-creator` 作为 System Scope Skill，通过 `codex_skills::install_system_skills()` 在启动时解压到用户本地缓存目录。

---

## 功能点目的

### 2.1 openai_yaml.md 的设计目标

该文档服务于 `agents/openai.yaml` 配置规范，定义以下核心功能：

| 功能模块 | 目的 |
|---------|------|
| `interface` 字段组 | 定义 Skill 的 UI 展示元数据（显示名称、描述、图标、品牌色、默认提示词） |
| `dependencies` 字段组 | 声明 Skill 依赖的外部工具（如 MCP 服务器） |
| `policy` 字段组 | 控制 Skill 的调用策略（是否允许隐式调用） |

### 2.2 关键约束规则

文档中明确定义的约束包括：

1. **字符串引号要求**：所有字符串值必须使用双引号
2. **键名格式**：保持 unquoted，使用 camelCase
3. **长度限制**：
   - `short_description`: 25-64 字符
   - `display_name`: 建议简洁可读
4. **路径规范**：图标路径必须相对于 Skill 目录，默认使用 `./assets/`
5. **颜色格式**：`brand_color` 必须为 `#RRGGBB` 十六进制格式

### 2.3 与生成脚本的协作

`openai_yaml.md` 被以下脚本引用：

- `scripts/generate_openai_yaml.py`: 读取 Skill 元数据生成规范 YAML
- `scripts/init_skill.py`: 初始化 Skill 时调用生成脚本

生成脚本会验证 `short_description` 长度必须在 25-64 字符之间，否则报错。

---

## 具体技术实现

### 3.1 文档结构解析

`openai_yaml.md` 采用标准 Markdown 格式，包含：

```markdown
# 标题与概述
- 说明文档用途：agents/openai.yaml 的完整字段参考

## Full example
- 提供完整 YAML 示例（含所有可选字段）

## Field descriptions and constraints  
- 字段级详细说明
- 约束条件（Top-level constraints）
- 每个字段的类型、用途、限制
```

### 3.2 配置 Schema 定义

#### Interface 字段结构
```yaml
interface:
  display_name: "string"        # UI 显示名称
  short_description: "string"   # 25-64 字符简短描述
  icon_small: "./assets/..."    # 小图标路径（相对）
  icon_large: "./assets/..."    # 大图标路径（相对）
  brand_color: "#RRGGBB"        # 品牌色
  default_prompt: "string"      # 默认提示词模板
```

#### Dependencies 字段结构
```yaml
dependencies:
  tools:
    - type: "mcp"               # 工具类型（目前仅支持 mcp）
      value: "identifier"       # 工具标识符
      description: "string"     # 人类可读描述
      transport: "streamable_http"  # 传输协议
      url: "https://..."        # MCP 服务器 URL
```

#### Policy 字段结构
```yaml
policy:
  allow_implicit_invocation: true  # 是否允许隐式调用，默认 true
```

### 3.3 生成脚本的实现逻辑

`generate_openai_yaml.py` 中的相关实现：

```python
# 允许的 interface 字段白名单
ALLOWED_INTERFACE_KEYS = {
    "display_name",
    "short_description", 
    "icon_small",
    "icon_large",
    "brand_color",
    "default_prompt",
}

# display_name 格式化逻辑
def format_display_name(skill_name):
    words = [word for word in skill_name.split("-") if word]
    formatted = []
    for index, word in enumerate(words):
        lower = word.lower()
        upper = word.upper()
        if upper in ACRONYMS:           # 处理缩写词（API, CLI 等）
            formatted.append(upper)
        elif lower in BRANDS:           # 处理品牌名（GitHub, OpenAI 等）
            formatted.append(BRANDS[lower])
        elif index > 0 and lower in SMALL_WORDS:  # 小词小写（and, or, to）
            formatted.append(lower)
        else:
            formatted.append(word.capitalize())
    return " ".join(formatted)

# short_description 长度强制约束
def generate_short_description(display_name):
    description = f"Help with {display_name} tasks"
    # 多级回退确保长度在 25-64 字符
    if len(description) < 25:
        description = f"Help with {display_name} tasks and workflows"
    if len(description) > 64:
        description = f"Help with {display_name}"
    # ... 更多回退逻辑
    return description
```

### 3.4 运行时验证

`quick_validate.py` 对 Skill 进行基础验证：

```python
def validate_skill(skill_path):
    # 1. 检查 SKILL.md 存在性
    # 2. 解析 YAML frontmatter
    # 3. 验证 name 字段：仅允许小写字母、数字、连字符
    # 4. 验证 description 字段：无尖括号，最大 1024 字符
    # 5. 验证 name 长度：最大 64 字符
```

---

## 关键代码路径与文件引用

### 4.1 本目录文件清单

| 文件 | 类型 | 说明 |
|-----|------|------|
| `openai_yaml.md` | Markdown | agents/openai.yaml 配置规范文档 |

### 4.2 上游依赖（调用本目录）

```
codex-rs/skills/src/assets/samples/skill-creator/
├── SKILL.md                          # 引用 references/openai_yaml.md
├── agents/openai.yaml                # 由脚本生成的元数据文件
├── scripts/
│   ├── init_skill.py                 # 导入并调用 generate_openai_yaml.py
│   ├── generate_openai_yaml.py       # 实现 openai.yaml 生成逻辑
│   └── quick_validate.py             # Skill 验证脚本
└── references/
    └── openai_yaml.md                # 【本文件】配置规范参考
```

### 4.3 下游依赖（被本目录引用/影响）

```
codex-rs/core/src/skills/
├── loader.rs                         # 解析 agents/openai.yaml
├── model.rs                          # SkillInterface/SkillMetadata 定义
└── manager.rs                        # Skill 生命周期管理

codex-rs/skills/
├── src/lib.rs                        # 系统技能安装逻辑
└── build.rs                          # 资源变更检测
```

### 4.4 核心代码引用链

#### 4.4.1 文档被引用位置

**SKILL.md 中的引用**：
```markdown
- Read references/openai_yaml.md before generating values and follow its descriptions and constraints
- See references/openai_yaml.md for field definitions and examples
- For full field descriptions and examples, see references/openai_yaml.md
```

#### 4.4.2 配置解析代码

**loader.rs 中的 Interface 解析**（行 98-106）：
```rust
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

**loader.rs 中的依赖解析**（行 108-131）：
```rust
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

#### 4.4.3 系统技能安装

**lib.rs 中的嵌入逻辑**（行 12）：
```rust
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

**指纹计算**（行 87-118）：
```rust
fn embedded_system_skills_fingerprint() -> String {
    // 计算所有嵌入式资源的哈希指纹
    // 用于判断是否需要重新解压系统技能
}
```

### 4.5 常量定义对照

| 常量 | 定义位置 | 值 | 用途 |
|-----|---------|-----|------|
| `MAX_NAME_LEN` | loader.rs | 64 | Skill 名称最大长度 |
| `MAX_DESCRIPTION_LEN` | loader.rs | 1024 | 描述最大长度 |
| `MAX_SHORT_DESCRIPTION_LEN` | loader.rs | 1024 | 短描述最大长度 |
| `MAX_SKILL_NAME_LENGTH` | init_skill.py | 64 | Python 端名称长度限制 |
| `ALLOWED_INTERFACE_KEYS` | generate_openai_yaml.py | 6 个字段 | 允许的 interface 字段 |

---

## 依赖与外部交互

### 5.1 编译时依赖

| 依赖 | 用途 |
|-----|------|
| `include_dir` crate | 将资源文件嵌入二进制 |
| `build.rs` | 监听资源目录变更，触发重新编译 |

### 5.2 运行时依赖

| 依赖 | 用途 |
|-----|------|
| `codex_core::skills::loader` | 解析 agents/openai.yaml |
| `serde_yaml` | YAML 反序列化 |
| `codex_skills::install_system_skills` | 解压嵌入式资源到缓存目录 |

### 5.3 外部工具依赖

| 工具 | 用途 |
|-----|------|
| Python 3 | 执行 init_skill.py, generate_openai_yaml.py, quick_validate.py |
| PyYAML | Python YAML 解析库 |

### 5.4 数据流图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           编译时                                            │
│  openai_yaml.md ──► include_dir!() ──► 嵌入二进制 ──► SYSTEM_SKILLS_DIR   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           运行时启动                                        │
│  install_system_skills() ──► 解压到 $CODEX_HOME/skills/.system/            │
│                              指纹比对避免重复解压                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Skill 使用                                        │
│  SKILL.md 引用 ──► 加载 references/openai_yaml.md ──► 指导配置生成        │
│                                                                      │
│  generate_openai_yaml.py ◄── 读取规范 ◄── openai_yaml.md              │
│         │                                                            │
│         ▼                                                            │
│  agents/openai.yaml ──► loader.rs 解析 ──► SkillMetadata.interface   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 文档与代码不同步风险

**问题**：`openai_yaml.md` 中定义的字段约束与 Rust 代码中的实际解析逻辑可能存在不一致。

**具体表现**：
- 文档规定 `short_description` 应为 25-64 字符
- Python 生成脚本强制执行此约束
- 但 Rust loader.rs 中 `MAX_SHORT_DESCRIPTION_LEN = 1024`，约束较宽松

**风险等级**：中等

#### 6.1.2 路径遍历风险

**缓解措施**：`loader.rs` 中的 `resolve_asset_path()` 函数已实施防护：
```rust
// 拒绝绝对路径
if path.is_absolute() { return None; }

// 拒绝包含 .. 的路径
Component::ParentDir => { return None; }

// 强制要求路径以 assets/ 开头
match components.next() {
    Some(Component::Normal(component)) if component == "assets" => {}
    _ => { return None; }
}
```

#### 6.1.3 依赖注入风险

`dependencies.tools` 允许声明 MCP 服务器依赖，但：
- URL 格式验证有限
- 命令行工具依赖（`command` 字段）的安全边界需依赖外部沙箱

### 6.2 边界条件

| 边界 | 当前处理 |
|-----|---------|
| 空 Skill 目录 | `install_system_skills()` 会清理旧目录后重新写入 |
| 指纹不匹配 | 触发完整重新解压，非增量更新 |
| 并发访问 | 无显式锁，依赖文件系统原子操作 |
| 符号链接 | System Scope 不跟随符号链接（安全考虑） |
| 深度限制 | `MAX_SCAN_DEPTH = 6` 层目录深度限制 |
| 目录数量限制 | `MAX_SKILLS_DIRS_PER_ROOT = 2000` |

### 6.3 改进建议

#### 6.3.1 统一约束校验

建议将长度约束统一到一个共享配置文件中：

```rust
// 建议：创建 codex-rs/skills/src/constants.rs
pub const SKILL_NAME_MAX_LEN: usize = 64;
pub const SKILL_DESCRIPTION_MAX_LEN: usize = 1024;
pub const SKILL_SHORT_DESCRIPTION_MIN_LEN: usize = 25;
pub const SKILL_SHORT_DESCRIPTION_MAX_LEN: usize = 64;
```

Python 脚本通过生成代码或解析 Rust 常量来保持同步。

#### 6.3.2 增强文档结构化

当前 `openai_yaml.md` 是自由格式 Markdown，建议：

```yaml
# 考虑增加机器可读的 schema 定义（如 JSON Schema）
# 或采用类似 OpenAPI 的结构化格式
```

这样 `generate_openai_yaml.py` 可以基于 schema 进行更严格的验证。

#### 6.3.3 增量更新优化

当前 `install_system_skills()` 在指纹不匹配时会删除整个目录：

```rust
if dest_system.as_path().exists() {
    fs::remove_dir_all(dest_system.as_path())?;  // 全量删除
}
write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;  // 全量写入
```

建议：
- 实现基于文件级指纹的增量更新
- 减少不必要的 I/O 操作

#### 6.3.4 国际化准备

当前 `openai_yaml.md` 完全使用英文，未来如需支持多语言：

```
references/
├── openai_yaml.md          # 默认（英文）
├── openai_yaml.zh-CN.md    # 简体中文
└── openai_yaml.ja-JP.md    # 日文
```

### 6.4 测试覆盖建议

当前测试覆盖（`lib.rs` 中的单元测试）：

```rust
#[test]
fn fingerprint_traverses_nested_entries() {
    // 仅验证指纹计算能遍历嵌套条目
}
```

建议增加：
1. `openai_yaml.md` 格式有效性测试
2. 生成脚本输出与 Rust 解析器兼容性测试
3. 约束边界值测试（25/64 字符边界）

---

## 附录：关键代码索引

| 功能 | 文件路径 | 行号 |
|-----|---------|------|
| 系统技能安装 | `codex-rs/skills/src/lib.rs` | 47-78 |
| 指纹计算 | `codex-rs/skills/src/lib.rs` | 87-118 |
| 资源嵌入 | `codex-rs/skills/src/lib.rs` | 12 |
| YAML 生成 | `codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py` | 156-187 |
| Interface 解析 | `codex-rs/core/src/skills/loader.rs` | 693-722 |
| 依赖解析 | `codex-rs/core/src/skills/loader.rs` | 724-781 |
| 路径解析 | `codex-rs/core/src/skills/loader.rs` | 783-829 |
| Skill 模型定义 | `codex-rs/core/src/skills/model.rs` | 23-78 |

---

*报告生成时间：2026-03-22*
*研究范围：codex-rs/skills/src/assets/samples/skill-creator/references/*
