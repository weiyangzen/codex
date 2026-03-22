# skill-creator 系统技能研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与目标

`skill-creator` 是 Codex CLI 内置的**系统级技能（System Skill）**，作为技能生态的"自举工具"存在。它的核心职责是：**指导用户（包括 AI Agent 自身）创建、更新和验证新的技能（Skill）**。

这形成了一个有趣的递归关系：
- Codex 使用 `skill-creator` 技能来创建新技能
- 新技能又可以扩展 Codex 的能力
- 形成自我增强的生态系统

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| **用户请求创建技能** | 用户说"帮我创建一个处理 PDF 的技能"，Codex 加载 `skill-creator` 并引导流程 |
| **自定义提示词迁移** | 检测到 `~/.codex/prompts` 中的旧版自定义提示时，建议用 `$skill-creator` 转换为技能 |
| **技能更新** | 修改现有技能的元数据、添加资源文件或更新文档 |
| **技能验证** | 在技能开发完成后运行验证脚本检查结构和格式 |

### 1.3 在系统中的位置

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex CLI 应用层                         │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ openai-docs  │  │ skill-creator│  │skill-installer│      │
│  │   (系统技能)  │  │   (系统技能)  │  │   (系统技能)  │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         ↑                  ↑                  ↑             │
│         └──────────────────┴──────────────────┘             │
│                    codex-skills crate                        │
│              (嵌入式系统技能管理)                              │
├─────────────────────────────────────────────────────────────┤
│                    codex-core crate                          │
│         (SkillsManager, loader, injection)                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 核心功能模块

| 功能模块 | 目的 | 对应脚本 |
|---------|------|---------|
| **技能初始化** | 创建新技能目录结构，生成模板文件 | `init_skill.py` |
| **元数据生成** | 自动生成/更新 `agents/openai.yaml` | `generate_openai_yaml.py` |
| **结构验证** | 验证技能格式、字段、命名规范 | `quick_validate.py` |
| **文档指导** | 提供完整的技能创建最佳实践指南 | `SKILL.md` |

### 2.2 技能创建六步流程

根据 `SKILL.md` 的指导，技能创建遵循以下流程：

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: 理解技能（Concrete Examples）                           │
│  └── 通过对话明确技能用途、触发条件和预期行为                      │
├─────────────────────────────────────────────────────────────────┤
│  Step 2: 规划资源（Planning）                                    │
│  └── 识别需要的 scripts/、references/、assets/                   │
├─────────────────────────────────────────────────────────────────┤
│  Step 3: 初始化（Initialize）←── 调用 init_skill.py              │
│  └── 生成目录结构、SKILL.md 模板、agents/openai.yaml              │
├─────────────────────────────────────────────────────────────────┤
│  Step 4: 编辑实现（Edit）                                        │
│  └── 填充 SKILL.md 内容，实现脚本和资源                            │
├─────────────────────────────────────────────────────────────────┤
│  Step 5: 验证（Validate）←── 调用 quick_validate.py              │
│  └── 检查 frontmatter、命名规范、必需字段                          │
├─────────────────────────────────────────────────────────────────┤
│  Step 6: 迭代优化（Iterate）                                     │
│  └── 前向测试（Forward-testing），使用子代理验证技能效果            │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 渐进式披露设计

`skill-creator` 本身也遵循技能的"渐进式披露"原则：

| 层级 | 内容 | 大小控制 |
|------|------|---------|
| **Metadata** | `name` + `description`（触发条件） | ~100 words |
| **SKILL.md body** | 完整创建指南 | <5k words |
| **Bundled resources** | 脚本和参考文档 | 按需加载 |

---

## 具体技术实现

### 3.1 文件结构

```
codex-rs/skills/src/assets/samples/skill-creator/
├── SKILL.md                              # 技能主文档（416行）
├── agents/
│   └── openai.yaml                       # UI 元数据配置
├── assets/
│   ├── skill-creator-small.svg          # 小图标（UI 展示）
│   └── skill-creator.png                # 大图标（UI 展示）
├── license.txt                           # Apache 2.0 许可证
├── references/
│   └── openai_yaml.md                   # openai.yaml 格式规范
└── scripts/
    ├── generate_openai_yaml.py          # 元数据生成脚本（226行）
    ├── init_skill.py                    # 技能初始化脚本（400行）
    └── quick_validate.py                # 验证脚本（101行）
```

### 3.2 关键数据结构

#### 3.2.1 SKILL.md Frontmatter 结构

```yaml
---
name: skill-creator
description: Guide for creating effective skills. This skill should be used when users want to create a new skill...
metadata:
  short-description: Create or update a skill
---
```

**字段约束**（由 `quick_validate.py` 和 `loader.rs` 共同执行）：

| 字段 | 类型 | 约束 | 验证位置 |
|------|------|------|---------|
| `name` | string | 小写字母、数字、连字符；最大64字符；不能以连字符开头/结尾；不能包含连续连字符 | `quick_validate.py:61-70`, `loader.rs:561` |
| `description` | string | 最大1024字符；不能包含尖括号 `<>` | `quick_validate.py:78-89`, `loader.rs:562` |
| `metadata.short-description` | string | 最大1024字符 | `loader.rs:563-569` |

#### 3.2.2 agents/openai.yaml 结构

```yaml
interface:
  display_name: "Skill Creator"                    # UI 显示名称
  short_description: "Create or update a skill"    # 25-64字符的简短描述
  icon_small: "./assets/skill-creator-small.svg"   # 小图标路径
  icon_large: "./assets/skill-creator.png"         # 大图标路径
```

**扩展字段**（由 `references/openai_yaml.md` 定义）：

| 字段 | 类型 | 描述 |
|------|------|------|
| `brand_color` | string | 品牌色，格式 `#RRGGBB` |
| `default_prompt` | string | 默认提示词模板，必须包含 `$skill-name` |
| `dependencies.tools` | array | 工具依赖（如 MCP 服务器） |
| `policy.allow_implicit_invocation` | bool | 是否允许隐式调用 |

### 3.3 脚本实现细节

#### 3.3.1 init_skill.py

**功能**：创建新技能目录结构

**关键流程**：

```python
def init_skill(skill_name, path, resources, include_examples, interface_overrides):
    # 1. 规范化技能名称（转小写、连字符连接）
    skill_name = normalize_skill_name(skill_name)
    
    # 2. 创建技能目录
    skill_dir = Path(path).resolve() / skill_name
    skill_dir.mkdir(parents=True, exist_ok=False)
    
    # 3. 生成 SKILL.md（从模板填充）
    skill_content = SKILL_TEMPLATE.format(skill_name=skill_name, skill_title=skill_title)
    (skill_dir / "SKILL.md").write_text(skill_content)
    
    # 4. 创建 agents/openai.yaml
    write_openai_yaml(skill_dir, skill_name, interface_overrides)
    
    # 5. 创建资源目录（可选）
    create_resource_dirs(skill_dir, resources, include_examples)
```

**模板类型**（SKILL_TEMPLATE 提供4种结构模式）：
1. **Workflow-Based**：顺序流程（如 DOCX 处理）
2. **Task-Based**：工具集合（如 PDF 处理）
3. **Reference/Guidelines**：标准规范（如品牌指南）
4. **Capabilities-Based**：集成系统（如产品管理）

#### 3.3.2 generate_openai_yaml.py

**功能**：生成/更新 `agents/openai.yaml`

**核心算法**：

```python
def format_display_name(skill_name):
    """将连字符名称转换为显示名称"""
    words = skill_name.split("-")
    formatted = []
    for index, word in enumerate(words):
        if word.upper() in ACRONYMS:           # GH, API, CLI 等 → 大写
            formatted.append(word.upper())
        elif word.lower() in BRANDS:           # github, openai 等 → 品牌规范
            formatted.append(BRANDS[word.lower()])
        elif index > 0 and word.lower() in SMALL_WORDS:  # and, or, to → 小写
            formatted.append(word.lower())
        else:
            formatted.append(word.capitalize())
    return " ".join(formatted)

def generate_short_description(display_name):
    """生成符合长度要求的短描述"""
    # 目标长度：25-64 字符
    description = f"Help with {display_name} tasks"
    # 多重回退策略确保长度合规...
```

**特殊处理规则**：

| 类别 | 示例值 | 处理方式 |
|------|--------|---------|
| 缩写词 | GH, API, CLI, LLM, PDF | 全大写 |
| 品牌名 | github→GitHub, openai→OpenAI | 品牌规范大小写 |
| 小词 | and, or, to, up, with | 非首词时小写 |

#### 3.3.3 quick_validate.py

**功能**：验证技能结构合规性

**验证项**：

```python
def validate_skill(skill_path):
    # 1. SKILL.md 存在性检查
    # 2. YAML frontmatter 格式检查（--- 包围）
    # 3. YAML 语法有效性检查
    # 4. 必需字段检查（name, description）
    # 5. 字段类型检查（必须为字符串）
    # 6. 名称格式检查（连字符规范）
    # 7. 描述长度和内容检查（无尖括号）
```

### 3.4 系统技能安装机制

`skill-creator` 作为系统技能，通过 `codex-skills` crate 管理：

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");

pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // 1. 计算嵌入式目录指纹
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    // 2. 检查 marker 文件，避免重复安装
    if read_marker(&marker_path).is_ok_and(|marker| marker == expected_fingerprint) {
        return Ok(());  // 已是最新版本
    }
    
    // 3. 清理旧版本
    if dest_system.as_path().exists() {
        fs::remove_dir_all(dest_system.as_path())?;
    }
    
    // 4. 写入嵌入式目录内容
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
    
    // 5. 写入 marker 文件
    fs::write(marker_path.as_path(), format!("{expected_fingerprint}\n"))?;
}
```

**安装路径**：`$CODEX_HOME/skills/.system/skill-creator/`

---

## 关键代码路径与文件引用

### 4.1 本目录文件清单

| 文件路径 | 行数 | 类型 | 职责 |
|---------|------|------|------|
| `SKILL.md` | 416 | Markdown | 技能主文档，包含完整创建指南 |
| `agents/openai.yaml` | 5 | YAML | UI 元数据配置 |
| `assets/skill-creator-small.svg` | - | SVG | 小图标（400px） |
| `assets/skill-creator.png` | - | PNG | 大图标 |
| `license.txt` | 202 | Text | Apache 2.0 许可证 |
| `references/openai_yaml.md` | 49 | Markdown | openai.yaml 格式规范文档 |
| `scripts/init_skill.py` | 400 | Python | 技能初始化脚本 |
| `scripts/generate_openai_yaml.py` | 226 | Python | 元数据生成脚本 |
| `scripts/quick_validate.py` | 101 | Python | 技能验证脚本 |

### 4.2 调用方代码路径

#### 4.2.1 系统技能加载

```
codex-rs/core/src/skills/manager.rs:53
    └── install_system_skills(&manager.codex_home)  // 安装系统技能
        └── codex-rs/skills/src/lib.rs:47
            └── write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)
                └── 将 skill-creator 写入 ~/.codex/skills/.system/
```

#### 4.2.2 技能触发

```
codex-rs/core/src/skills/injection.rs:100
    └── collect_explicit_skill_mentions(...)
        └── 解析用户输入中的 $skill-creator 提及
            └── 触发技能注入，加载 SKILL.md 内容到上下文
```

#### 4.2.3 TUI 层提示

```
codex-rs/tui/src/app.rs:303
    └── "Use the `$skill-creator` skill to convert each custom prompt into a skill."
        └── 当检测到 ~/.codex/prompts 存在时提示用户迁移
```

### 4.3 被调用方代码路径

#### 4.3.1 技能加载器

```
codex-rs/core/src/skills/loader.rs:527
    └── parse_skill_file(path, scope)
        └── 解析 SKILL.md frontmatter
            └── 提取 name, description, metadata
```

#### 4.3.2 元数据解析

```
codex-rs/core/src/skills/loader.rs:602
    └── load_skill_metadata(skill_path)
        └── 读取 agents/openai.yaml
            └── 解析 interface, dependencies, policy, permissions
```

---

## 依赖与外部交互

### 5.1 Python 脚本依赖

| 脚本 | 依赖库 | 用途 |
|------|--------|------|
| `init_skill.py` | `generate_openai_yaml` (本地导入) | 生成 UI 元数据 |
| `generate_openai_yaml.py` | `pyyaml` | YAML 解析（读取 SKILL.md frontmatter） |
| `quick_validate.py` | `pyyaml` | YAML 验证 |

### 5.2 Rust 层依赖

| Crate | 用途 |
|-------|------|
| `codex-skills` | 系统技能嵌入和安装 |
| `codex-core` | 技能加载、管理、注入 |
| `include_dir` | 编译时嵌入技能文件 |
| `serde_yaml` | YAML 解析（frontmatter） |

### 5.3 外部工具交互

| 工具 | 交互方式 | 用途 |
|------|---------|------|
| Python 解释器 | 子进程执行 | 运行初始化/验证脚本 |
| 文件系统 | 读写操作 | 创建技能目录结构 |

### 5.4 与其他系统技能的关系

```
┌─────────────────────────────────────────────────────────────┐
│                     系统技能生态                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌──────────────┐         ┌──────────────┐                │
│   │ skill-creator│◄───────►│skill-installer│               │
│   │   (创建技能)  │         │   (安装技能)  │                │
│   └──────┬───────┘         └──────────────┘                │
│          │                                                  │
│          ▼                                                  │
│   ┌──────────────┐                                         │
│   │  openai-docs │  ← 被 skill-creator 引用（参考文档）       │
│   │  (API 文档)   │                                         │
│   └──────────────┘                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 脚本依赖风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| Python 未安装 | 脚本依赖 Python 3 环境 | 脚本使用 `#!/usr/bin/env python3` shebang，依赖系统环境 |
| PyYAML 未安装 | `generate_openai_yaml.py` 和 `quick_validate.py` 依赖 PyYAML | 需要用户手动安装 `pip install pyyaml` |
| 路径解析失败 | 符号链接或特殊字符路径可能导致问题 | `init_skill.py` 使用 `Path.resolve()` 处理路径 |

#### 6.1.2 命名冲突风险

```python
# init_skill.py:275-277
if skill_dir.exists():
    print(f"[ERROR] Skill directory already exists: {skill_dir}")
    return None
```
- **风险**：同名技能会阻止创建，但不会提示用户其他位置的同名技能
- **边界**：系统技能（如 skill-creator 自身）与用户技能可能同名

#### 6.1.3 验证局限性

```python
# quick_validate.py:40
allowed_properties = {"name", "description", "license", "allowed-tools", "metadata"}
```
- **风险**：验证器只检查 frontmatter 字段，不验证 Markdown 内容质量
- **边界**：无法检测 SKILL.md 中的逻辑错误或过时信息

### 6.2 边界条件

#### 6.2.1 名称长度边界

```python
MAX_SKILL_NAME_LENGTH = 64  # init_skill.py:23, quick_validate.py:12
```

#### 6.2.2 描述长度边界

```python
MAX_DESCRIPTION_LEN = 1024  # loader.rs:139
MAX_SHORT_DESCRIPTION_LEN = 64  # 实际 UI 约束，generate_openai_yaml.py 强制 25-64
```

#### 6.2.3 扫描深度边界

```rust
// loader.rs:149
const MAX_SCAN_DEPTH: usize = 6;
const MAX_SKILLS_DIRS_PER_ROOT: usize = 2000;
```

### 6.3 改进建议

#### 6.3.1 短期改进

| 建议 | 优先级 | 实现复杂度 |
|------|--------|-----------|
| 添加 Python 依赖检查 | 高 | 低 |
| 在 `init_skill.py` 中添加 `--dry-run` 模式 | 中 | 低 |
| 验证脚本添加 `--fix` 自动修复选项 | 中 | 中 |
| 生成脚本支持交互式输入（无参数模式） | 低 | 低 |

#### 6.3.2 中期改进

| 建议 | 描述 |
|------|------|
| **技能模板市场** | 提供常见技能模板（如 MCP 工具包装、API 客户端等） |
| **版本兼容性检查** | 验证技能声明的 `allowed-tools` 与当前 Codex 版本兼容 |
| **自动化测试生成** | 根据 SKILL.md 示例自动生成基础测试用例 |
| **技能依赖解析** | 支持技能声明依赖其他技能，自动加载依赖链 |

#### 6.3.3 长期改进

| 建议 | 描述 |
|------|------|
| **可视化技能编辑器** | 提供 TUI/GUI 界面编辑技能元数据和结构 |
| **技能性能分析** | 跟踪技能使用频率、token 消耗，优化热门技能 |
| **技能市场集成** | 支持从远程仓库安装社区技能 |
| **A/B 测试框架** | 支持技能的多个版本并行测试，自动选择效果更好的版本 |

### 6.4 测试覆盖建议

当前 `codex-rs/skills/src/lib.rs` 包含基础测试：

```rust
#[test]
fn fingerprint_traverses_nested_entries() {
    // 验证 skill-creator/SKILL.md 和 skill-creator/scripts/init_skill.py 存在
}
```

建议增加：

1. **集成测试**：验证脚本在真实 Python 环境下的执行
2. **模板测试**：验证生成的 SKILL.md 模板可以被正确解析
3. **边界测试**：测试名称长度、特殊字符等边界条件
4. **端到端测试**：完整流程测试（创建→验证→加载→触发）

---

## 附录

### A. 相关文档链接

| 文档 | 路径 |
|------|------|
| 系统技能管理 | `codex-rs/skills/src/lib.rs` |
| 技能加载器 | `codex-rs/core/src/skills/loader.rs` |
| 技能注入 | `codex-rs/core/src/skills/injection.rs` |
| 技能管理器 | `codex-rs/core/src/skills/manager.rs` |
| 技能模型 | `codex-rs/core/src/skills/model.rs` |
| App Server 协议 | `codex-rs/app-server-protocol/src/protocol/v2.rs` |

### B. 触发关键词

根据 `SKILL.md` frontmatter 的 `description` 字段，以下用户输入会触发 `skill-creator`：

- "create a new skill"
- "update a skill"
- "skill creation"
- "create or update a skill"
- 任何提及创建/更新 Codex 技能扩展能力的请求
