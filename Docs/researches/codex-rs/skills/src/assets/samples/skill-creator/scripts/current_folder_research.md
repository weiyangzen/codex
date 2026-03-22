# Research: codex-rs/skills/src/assets/samples/skill-creator/scripts

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/skills/src/assets/samples/skill-creator/scripts` 是 Codex 系统技能（System Skill）"skill-creator" 的核心脚本目录。该目录包含三个 Python 脚本，共同构成 Skill 创建、初始化和验证的完整工具链。

### 1.2 核心职责

该目录承载以下关键职责：

| 职责 | 说明 |
|------|------|
| **Skill 初始化** | `init_skill.py` - 从模板创建新 Skill 目录结构 |
| **UI 元数据生成** | `generate_openai_yaml.py` - 生成 `agents/openai.yaml` 配置文件 |
| **结构验证** | `quick_validate.py` - 验证 Skill 目录结构合规性 |

### 1.3 使用场景

1. **新 Skill 创建**: 当用户需要创建自定义 Skill 时，通过 `init_skill.py` 快速生成标准目录结构
2. **Skill 更新**: 修改 Skill 后使用 `quick_validate.py` 验证结构完整性
3. **UI 集成**: 生成/更新 `openai.yaml` 以支持 Codex UI 中的 Skill 展示

### 1.4 在系统中的位置

```
Codex 系统启动
    ↓
SkillsManager::new() → install_system_skills()
    ↓
将嵌入式 Skill 解压到 $CODEX_HOME/skills/.system/
    ↓
skill-creator/ 目录可用
    ├── SKILL.md (使用指南)
    ├── scripts/ (本目录 - 工具脚本)
    ├── references/ (参考文档)
    ├── assets/ (图标资源)
    └── agents/openai.yaml (UI 配置)
```

---

## 2. 功能点目的

### 2.1 init_skill.py - Skill 初始化器

**目的**: 自动化创建符合 Codex 规范的 Skill 目录结构

**核心功能**:
- 规范化 Skill 名称（转换为小写连字符格式）
- 生成 SKILL.md 模板（包含结构化 TODO 指导）
- 创建可选资源目录（scripts/、references/、assets/）
- 调用 `generate_openai_yaml.py` 生成 UI 元数据
- 支持示例文件生成（`--examples` 标志）

**命令行接口**:
```bash
init_skill.py <skill-name> --path <path> \
    [--resources scripts,references,assets] \
    [--examples] \
    [--interface key=value]
```

### 2.2 generate_openai_yaml.py - OpenAI YAML 生成器

**目的**: 为 Skill 生成标准化的 UI 元数据配置文件

**核心功能**:
- 从 SKILL.md frontmatter 读取 Skill 名称
- 智能格式化显示名称（处理首字母大写、缩写、品牌名）
- 自动生成短描述（25-64 字符约束）
- 支持通过命令行覆盖接口字段

**命名格式化规则**:
- 缩写词大写（API、CLI、LLM 等）
- 品牌名特殊处理（openai→OpenAI、github→GitHub）
- 小词小写（and、or、to、up、with）

**生成的 YAML 结构**:
```yaml
interface:
  display_name: "Skill Creator"
  short_description: "Create or update a skill"
  icon_small: "./assets/skill-creator-small.svg"
  icon_large: "./assets/skill-creator.png"
```

### 2.3 quick_validate.py - 快速验证器

**目的**: 在 Skill 开发完成后进行基础合规性检查

**验证项**:
- SKILL.md 文件存在性
- YAML frontmatter 格式正确性
- 必需字段检查（name、description）
- 名称格式合规（小写字母、数字、连字符）
- 描述长度限制（≤1024 字符，无尖括号）
- 意外字段检测

**允许的 Frontmatter 字段**:
```python
{"name", "description", "license", "allowed-tools", "metadata"}
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 Skill 模板常量 (init_skill.py)

```python
SKILL_TEMPLATE = """---
name: {skill_name}
description: [TODO: ...]
---

# {skill_title}

## Overview
...
"""
```

模板包含四种结构设计模式指导：
1. **Workflow-Based**: 顺序流程（如 DOCX 处理）
2. **Task-Based**: 工具集合（如 PDF 操作）
3. **Reference/Guidelines**: 标准规范（如品牌指南）
4. **Capabilities-Based**: 集成系统（如产品管理）

#### 3.1.2 资源类型定义

```python
ALLOWED_RESOURCES = {"scripts", "references", "assets"}
MAX_SKILL_NAME_LENGTH = 64
```

#### 3.1.3 接口字段约束 (generate_openai_yaml.py)

```python
ALLOWED_INTERFACE_KEYS = {
    "display_name",
    "short_description", 
    "icon_small",
    "icon_large",
    "brand_color",
    "default_prompt",
}
```

### 3.2 关键流程

#### 3.2.1 Skill 初始化流程

```
┌─────────────────┐
│  解析命令行参数  │
└────────┬────────┘
         ↓
┌─────────────────┐
│ 规范化 Skill 名 │ ← normalize_skill_name()
│ (小写+连字符)   │
└────────┬────────┘
         ↓
┌─────────────────┐
│  创建 Skill 目录 │
└────────┬────────┘
         ↓
┌─────────────────┐
│ 生成 SKILL.md   │ ← SKILL_TEMPLATE.format()
└────────┬────────┘
         ↓
┌─────────────────┐
│ 创建 agents/    │ ← write_openai_yaml()
│ openai.yaml     │
└────────┬────────┘
         ↓
┌─────────────────┐
│ 创建资源目录    │ ← create_resource_dirs()
│ (可选+示例)     │
└─────────────────┘
```

#### 3.2.2 名称规范化流程

```python
def normalize_skill_name(skill_name):
    normalized = skill_name.strip().lower()
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized)  # 非字母数字→连字符
    normalized = normalized.strip("-")                    # 去除首尾连字符
    normalized = re.sub(r"-{2,}", "-", normalized)       # 合并连续连字符
    return normalized
```

#### 3.2.3 显示名称智能格式化

```python
def format_display_name(skill_name):
    words = [word for word in skill_name.split("-") if word]
    formatted = []
    for index, word in enumerate(words):
        lower = word.lower()
        upper = word.upper()
        if upper in ACRONYMS:           # API, CLI, LLM...
            formatted.append(upper)
        elif lower in BRANDS:           # openai→OpenAI
            formatted.append(BRANDS[lower])
        elif index > 0 and lower in SMALL_WORDS:  # and, or, to...
            formatted.append(lower)
        else:
            formatted.append(word.capitalize())
    return " ".join(formatted)
```

#### 3.2.4 短描述生成算法

```python
def generate_short_description(display_name):
    # 基础模板
    description = f"Help with {display_name} tasks"
    
    # 长度约束处理（25-64 字符）
    if len(description) < 25:
        description = f"Help with {display_name} tasks and workflows"
    if len(description) > 64:
        description = f"Help with {display_name}"
    if len(description) > 64:
        description = f"{display_name} helper"
    # ... 更多降级策略
    
    return description
```

### 3.3 验证逻辑

#### 3.3.1 Frontmatter 提取

```python
def extract_frontmatter(contents):
    lines = contents.lines()
    if not matches(lines.next(), "---"):
        return None
    
    frontmatter_lines = []
    for line in lines:
        if line.trim() == "---":
            return "\n".join(frontmatter_lines)
        frontmatter_lines.append(line)
    return None  # 未找到闭合标记
```

#### 3.3.2 名称格式验证

```python
# 允许的字符：小写字母、数字、连字符
if not re.match(r"^[a-z0-9-]+$", name):
    return False, "Name should be hyphen-case"

# 禁止首尾连字符和连续连字符
if name.startswith("-") or name.endswith("-") or "--" in name:
    return False, "Invalid hyphen usage"
```

### 3.4 文件系统操作

#### 3.4.1 资源目录创建

```python
def create_resource_dirs(skill_dir, skill_name, skill_title, resources, include_examples):
    for resource in resources:
        resource_dir = skill_dir / resource
        resource_dir.mkdir(exist_ok=True)
        
        if resource == "scripts" and include_examples:
            example_script = resource_dir / "example.py"
            example_script.write_text(EXAMPLE_SCRIPT.format(skill_name=skill_name))
            example_script.chmod(0o755)  # 可执行权限
```

#### 3.4.2 YAML 安全转义

```python
def yaml_quote(value):
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'
```

---

## 4. 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 核心功能 |
|------|------|----------|
| `init_skill.py` | 400 | Skill 初始化主入口 |
| `generate_openai_yaml.py` | 226 | UI 元数据生成 |
| `quick_validate.py` | 101 | 结构验证 |

### 4.2 同 Skill 相关文件

```
skill-creator/
├── SKILL.md                          # 使用指南 (416 行)
├── scripts/
│   ├── init_skill.py                 # 本研究对象
│   ├── generate_openai_yaml.py       # 本研究对象
│   └── quick_validate.py             # 本研究对象
├── references/
│   └── openai_yaml.md                # openai.yaml 字段说明
├── agents/
│   └── openai.yaml                   # UI 配置示例
├── assets/
│   ├── skill-creator-small.svg       # 小图标
│   └── skill-creator.png             # 大图标
└── license.txt                       # Apache 2.0 许可证
```

### 4.3 Rust 集成层

| 文件 | 职责 |
|------|------|
| `codex-rs/skills/src/lib.rs` | 系统 Skill 安装/缓存管理 |
| `codex-rs/skills/build.rs` | 构建时监控 samples 目录变化 |
| `codex-rs/core/src/skills/system.rs` | 系统 Skill 安装/卸载接口 |
| `codex-rs/core/src/skills/loader.rs` | Skill 加载/解析/验证 |
| `codex-rs/core/src/skills/manager.rs` | Skill 管理器（缓存、根目录解析） |
| `codex-rs/core/tests/suite/skills.rs` | Skill 集成测试 |

### 4.4 调用链

```
Rust 层调用链:
----------------
SkillsManager::new()
  └── install_system_skills(codex_home)
        └── write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest)
              └── SYSTEM_SKILLS_DIR = include_dir!("src/assets/samples")
                    └── skill-creator/ 目录解压到 ~/.codex/skills/.system/

Python 脚本调用链:
------------------
init_skill.py
  ├── 导入: generate_openai_yaml.write_openai_yaml()
  └── 生成: agents/openai.yaml

用户工作流:
-----------
1. 用户执行: init_skill.py my-skill --path ~/.codex/skills
2. 生成目录结构
3. 用户编辑 SKILL.md
4. 用户执行: quick_validate.py ~/.codex/skills/my-skill
5. 验证通过后 Skill 可用
```

---

## 5. 依赖与外部交互

### 5.1 Python 依赖

| 依赖 | 用途 | 来源 |
|------|------|------|
| `argparse` | 命令行参数解析 | 标准库 |
| `re` | 正则表达式（名称规范化） | 标准库 |
| `sys` | 系统退出、错误处理 | 标准库 |
| `pathlib.Path` | 跨平台路径操作 | 标准库 |
| `yaml` (PyYAML) | YAML 解析/生成 | 第三方（由 generate_openai_yaml.py 导入） |

### 5.2 内部模块依赖

```python
# init_skill.py 导入
try:
    from generate_openai_yaml import write_openai_yaml  # 同目录模块
except ImportError:
    # 回退处理
```

### 5.3 Rust 层依赖

| Crate | 用途 |
|-------|------|
| `include_dir` | 编译时嵌入目录到二进制 |
| `codex_utils_absolute_path` | 绝对路径安全操作 |
| `thiserror` | 错误处理 |

### 5.4 外部系统交互

| 交互对象 | 方式 | 说明 |
|----------|------|------|
| 文件系统 | 读写 | 创建目录、写入模板文件 |
| 环境变量 | 读取 | `$CODEX_HOME` 决定安装位置 |
| 用户输入 | 命令行 | 参数解析和交互式提示 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 等级 | 说明 |
|------|------|------|
| 路径遍历 | 低 | `init_skill.py` 使用 `Path(path).resolve()`，但无额外校验 |
| 权限提升 | 低 | 脚本设置 0o755 权限，但仅作用于示例文件 |
| YAML 注入 | 低 | `yaml_quote()` 转义了 `"`、`
` 和 `\`，但可能遗漏其他特殊字符 |

#### 6.1.2 功能风险

| 风险 | 影响 | 场景 |
|------|------|------|
| 名称冲突 | 中 | 同名 Skill 目录已存在时直接报错退出 |
| 部分失败 | 中 | 创建过程中断可能导致目录处于不一致状态 |
| 验证遗漏 | 低 | `quick_validate.py` 不验证 Markdown 内容质量 |

### 6.2 边界条件

#### 6.2.1 名称长度约束

```python
MAX_SKILL_NAME_LENGTH = 64
```

- 超过 64 字符的名称将被拒绝
- 规范化后的名称若为空也拒绝

#### 6.2.2 描述长度约束

```python
MAX_DESCRIPTION_LEN = 1024        # SKILL.md frontmatter
MAX_SHORT_DESCRIPTION_LEN = 64    # openai.yaml interface
MIN_SHORT_DESCRIPTION_LEN = 25    # UI 显示要求
```

#### 6.2.3 资源类型限制

```python
ALLOWED_RESOURCES = {"scripts", "references", "assets"}
```

其他资源类型将被拒绝并显示错误信息。

#### 6.2.4 扫描深度限制（Rust 层）

```rust
const MAX_SCAN_DEPTH: usize = 6;
const MAX_SKILLS_DIRS_PER_ROOT: usize = 2000;
```

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增强 YAML 转义**
   ```python
   # 当前仅处理 \", \\, \n
   # 建议增加对其他特殊字符的处理
   def yaml_quote(value):
       escaped = value.replace("\\", "\\\\").replace('"', '\\"')
       escaped = escaped.replace("\n", "\\n").replace("\r", "\\r")
       escaped = escaped.replace("\t", "\\t")
       return f'"{escaped}"'
   ```

2. **添加原子性操作**
   ```python
   # 当前：逐步创建，失败时可能残留部分目录
   # 建议：先创建临时目录，成功后原子移动
   import tempfile
   import shutil
   
   with tempfile.TemporaryDirectory() as tmpdir:
       # 在 tmpdir 中创建完整结构
       # 成功后 shutil.move(tmpdir, skill_dir)
   ```

3. **增强验证覆盖**
   - 验证 `agents/openai.yaml` 存在性和格式
   - 验证资源目录中的可执行脚本语法
   - 检查图标文件存在性

#### 6.3.2 中期改进

1. **配置化模板**
   - 支持用户自定义 SKILL.md 模板
   - 支持多语言模板

2. **交互式向导**
   - 提供 `init_skill.py --interactive` 模式
   - 逐步引导用户输入关键信息

3. **版本兼容性检查**
   - 验证 Skill 结构与当前 Codex 版本兼容
   - 提供迁移工具处理旧格式

#### 6.3.3 长期改进

1. **Schema 验证**
   - 为 openai.yaml 提供 JSON Schema
   - 使用 `jsonschema` 库进行严格验证

2. **测试生成**
   - 自动生成基础测试用例
   - 集成 forward-testing 工作流

3. **依赖管理**
   - 追踪 Skill 间依赖关系
   - 自动安装依赖 Skill

### 6.4 测试覆盖

当前测试情况：
- **Rust 层**: `codex-rs/core/tests/suite/skills.rs` 包含系统 Skill 集成测试
- **Python 层**: 无单元测试，依赖手动验证

建议增加：
```python
# test_init_skill.py
import tempfile
from pathlib import Path

def test_normalize_skill_name():
    assert normalize_skill_name("My Skill") == "my-skill"
    assert normalize_skill_name("API-Helper") == "api-helper"
    assert normalize_skill_name("--test--") == "test"

def test_init_skill_creates_structure():
    with tempfile.TemporaryDirectory() as tmpdir:
        result = init_skill("test-skill", tmpdir, ["scripts"], False, [])
        assert result is not None
        assert (Path(tmpdir) / "test-skill" / "SKILL.md").exists()
```

---

## 7. 附录

### 7.1 相关文档

- `skill-creator/SKILL.md`: Skill 创建完整指南
- `skill-creator/references/openai_yaml.md`: UI 元数据字段说明
- `AGENTS.md`: 项目级代理开发规范

### 7.2 关键常量汇总

| 常量 | 值 | 定义位置 |
|------|-----|----------|
| `MAX_SKILL_NAME_LENGTH` | 64 | `init_skill.py`, `quick_validate.py` |
| `MAX_DESCRIPTION_LEN` | 1024 | `loader.rs` |
| `MAX_SCAN_DEPTH` | 6 | `loader.rs` |
| `MAX_SKILLS_DIRS_PER_ROOT` | 2000 | `loader.rs` |
| `ALLOWED_RESOURCES` | {"scripts", "references", "assets"} | `init_skill.py` |

### 7.3 文件权限

```python
# 示例脚本权限
0o755  # rwxr-xr-x (所有者可读写执行，其他可读执行)

# 其他文件权限
默认 0o644 (rw-r--r--)
```
