# quick_validate.py 研究文档

## 场景与职责

`quick_validate.py` 是 Skill Creator 工具链中的验证脚本，用于在 Skill 开发完成后进行基础结构验证。它是 Skill 创建流程（Step 5: Validate the Skill）的自动化实现，帮助开发者在提交或发布前捕获常见的结构和格式问题。

### 使用场景
1. **开发完成验证**：Skill 编辑完成后验证结构正确性
2. **CI/CD 集成**：在持续集成流程中自动验证 Skill
3. **批量验证**：验证多个 Skill 或整个 Skill 仓库
4. **预提交检查**：作为 Git 钩子防止提交无效 Skill

### 核心职责
- 验证 `SKILL.md` 文件存在性
- 验证 YAML frontmatter 格式正确性
- 验证必需字段（`name`, `description`）存在
- 验证字段类型和格式约束
- 验证 Skill 名称符合命名规范
- 验证描述符合长度和内容约束

---

## 功能点目的

### 1. 基础结构验证
检查 Skill 目录的基本结构：
- **SKILL.md 存在性**：确保主文档存在
- **Frontmatter 存在性**：确保文档以 `---` 开头
- **Frontmatter 格式**：确保使用正确的分隔符格式

### 2. YAML 解析验证
安全解析 frontmatter 内容：
- 使用 `yaml.safe_load` 防止代码执行
- 验证解析结果为字典类型
- 捕获并报告 YAML 语法错误

### 3. 字段约束验证
验证 frontmatter 中的字段：
- **允许字段白名单**：`name`, `description`, `license`, `allowed-tools`, `metadata`
- **必需字段检查**：`name` 和 `description` 必须存在
- **类型检查**：确保字段值为字符串类型

### 4. Skill 名称验证
验证 Skill 名称符合规范：
- **字符集限制**：仅允许小写字母、数字和连字符
- **格式限制**：不能以连字符开头或结尾，不能有连续连字符
- **长度限制**：不超过 64 个字符

### 5. 描述验证
验证描述字段符合要求：
- **类型检查**：必须为字符串
- **内容限制**：不能包含尖括号（`<` 或 `>`）
- **长度限制**：不超过 1024 个字符

---

## 具体技术实现

### 关键流程

```
validate_skill(skill_path)
  ├── 解析路径
  ├── 检查 SKILL.md 存在性
  ├── 读取文件内容
  ├── 检查 frontmatter 存在性（以 --- 开头）
  ├── 提取 frontmatter（正则匹配）
  ├── 解析 YAML
  │   └── yaml.safe_load()
  ├── 验证字段
  │   ├── 检查允许字段（白名单）
  │   ├── 检查必需字段（name, description）
  │   └── 检查字段类型
  ├── 验证 name 字段
  │   ├── 类型检查（字符串）
  │   ├── 正则匹配（^[a-z0-9-]+$）
  │   ├── 格式检查（不以 - 开头/结尾，无连续 -）
  │   └── 长度检查（≤64）
  └── 验证 description 字段
      ├── 类型检查（字符串）
      ├── 内容检查（无尖括号）
      └── 长度检查（≤1024）

main()
  ├── 检查命令行参数
  ├── 调用 validate_skill()
  ├── 打印验证结果
  └── 返回退出码（0=成功，1=失败）
```

### 数据结构

#### 验证常量
```python
MAX_SKILL_NAME_LENGTH = 64

# 允许的 frontmatter 字段
allowed_properties = {
    "name", 
    "description", 
    "license", 
    "allowed-tools", 
    "metadata"
}
```

#### 验证结果
函数返回元组 `(bool, str)`：
- `True, "Skill is valid!"` - 验证通过
- `False, "<error message>"` - 验证失败，附带具体错误信息

### 命令行接口

```bash
# 基本用法
python quick_validate.py <skill_directory>

# 示例
python quick_validate.py ./my-skill
python quick_validate.py ~/.codex/skills/my-skill
```

### 验证规则详解

#### Skill 名称规则
| 规则 | 正则/条件 | 错误示例 |
|------|-----------|----------|
| 字符集 | `^[a-z0-9-]+$` | `MySkill` (大写), `my_skill` (下划线) |
| 首尾格式 | 不以 `-` 开头/结尾 | `-my-skill`, `my-skill-` |
| 连续连字符 | 不包含 `--` | `my--skill` |
| 长度 | `len(name) <= 64` | 超长名称 |

#### 描述规则
| 规则 | 条件 | 错误示例 |
|------|------|----------|
| 类型 | `isinstance(desc, str)` | `description: 123` |
| 无尖括号 | `'<' not in desc and '>' not in desc` | `"<help> with tasks"` |
| 长度 | `len(desc) <= 1024` | 超长描述 |

#### Frontmatter 规则
| 规则 | 说明 |
|------|------|
| 格式 | 必须以 `---\n` 开头，包含 `\n---` 分隔符 |
| 类型 | 解析后必须为字典 |
| 字段白名单 | 只允许 `name`, `description`, `license`, `allowed-tools`, `metadata` |
| 必需字段 | 必须包含 `name` 和 `description` |

---

## 关键代码路径与文件引用

### 当前文件
- **路径**: `codex-rs/skills/src/assets/samples/skill-creator/scripts/quick_validate.py`
- **大小**: 101 行

### 依赖文件
| 文件 | 用途 |
|------|------|
| `SKILL.md` | 被验证的主文档 |

### 调用方
| 来源 | 说明 |
|------|------|
| 命令行 | 开发者直接执行 |
| Codex Agent | 根据 SKILL.md 指导自动执行 |
| CI/CD | 自动化验证流程 |

### 相关文档
| 文件 | 内容 |
|------|------|
| `SKILL.md` | Skill Creator 指南，包含验证步骤说明 |
| `references/openai_yaml.md` | agents/openai.yaml 字段说明（间接相关）|

---

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `re` | 正则表达式（frontmatter 提取、名称验证） |
| `sys` | 命令行参数和退出码 |
| `pathlib.Path` | 跨平台路径操作 |

### 第三方库
| 库 | 用途 |
|----|------|
| `yaml` | 解析 frontmatter YAML 内容 |

### 文件系统交互
1. **读取**: `SKILL.md` 文件内容

---

## 风险、边界与改进建议

### 已知风险

1. **验证范围有限**
   - 仅验证基础结构和 frontmatter，不验证 Markdown 内容
   - 不验证 `agents/openai.yaml` 的存在或正确性
   - 不验证资源目录内容
   - 建议：扩展验证范围或提供不同验证级别

2. **正则表达式脆弱性**
   - Frontmatter 提取使用简单正则，可能无法处理复杂情况
   - 建议：使用专门的 YAML frontmatter 解析库

3. **字符编码问题**
   - 未显式指定文件编码
   - 建议：使用 `encoding='utf-8'` 读取文件

4. **错误信息不够详细**
   - 未提供行号或位置信息
   - 建议：添加 frontmatter 行号追踪

### 边界条件

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| SKILL.md 为空文件 | 返回 "No YAML frontmatter found" | 提供更具体的错误 |
| Frontmatter 为空 | YAML 解析可能失败 | 添加空 frontmatter 检查 |
| 名称/描述仅空白字符 | 通过验证（strip 后检查） | 添加非空验证 |
| 多行描述 | 正常处理 | 验证多行描述的特殊处理 |
| 非常大的 SKILL.md | 一次性读取到内存 | 考虑流式读取大文件 |
| 循环符号链接 | 可能无限循环 | 添加符号链接检测 |

### 改进建议

1. **验证范围扩展**
   - 验证 `agents/openai.yaml` 存在性和格式
   - 验证资源目录结构（如果存在）
   - 验证脚本文件可执行性（如果存在）
   - 验证 Markdown 语法（使用 markdown linter）
   - 验证内部链接有效性

2. **验证级别**
   - `--quick`: 当前的基础验证（默认）
   - `--standard`: 包含 agents/openai.yaml 验证
   - `--full`: 包含所有内容和结构验证

3. **输出格式改进**
   - 支持 `--json` 输出（便于 CI 解析）
   - 支持 `--verbose` 显示详细检查项
   - 彩色输出区分成功/警告/错误
   - 显示检查进度和统计

4. **批量验证**
   - 支持验证多个 Skill 目录
   - 支持递归验证目录下的所有 Skill
   - 生成验证报告摘要

5. **自动修复**
   - `--fix` 模式自动修复可修复的问题
   - 自动规范化 Skill 名称
   - 自动截断超长描述

6. **配置支持**
   - 支持 `.skill-validator.yaml` 配置文件
   - 允许自定义验证规则
   - 支持忽略特定检查

### 代码质量建议

1. **类型注解**
   - 添加完整的类型注解
   - 使用 `TypedDict` 定义 frontmatter 结构

2. **测试覆盖**
   - 单元测试：每个验证规则
   - 集成测试：完整验证流程
   - 边界测试：各种边缘情况
   -  fixtures：创建测试 Skill 样本

3. **错误处理**
   - 使用自定义异常类
   - 提供错误代码
   - 添加建议修复方案

### 与相关脚本的协作

```
┌─────────────────────────────────────────────────────────────────┐
│                     Skill 验证流程                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ init_skill.py   │────│   Skill 编辑    │                   │
│  │ (创建)          │     │ (人工/Codex)    │                   │
│  └─────────────────┘     └────────┬────────┘                   │
│                                   ▼                            │
│                          ┌─────────────────┐                   │
│                          │quick_validate.py│                   │
│                          │ ─────────────── │                   │
│                          │ • SKILL.md 存在 │                   │
│                          │ • frontmatter   │                   │
│                          │ • name 格式     │                   │
│                          │ • description   │                   │
│                          │   约束          │                   │
│                          └────────┬────────┘                   │
│                                   │                            │
│                    ┌──────────────┼──────────────┐             │
│                    ▼              ▼              ▼             │
│             ┌──────────┐   ┌──────────┐   ┌──────────┐        │
│             │  通过    │   │  警告    │   │  失败    │        │
│             │ 提交/使用│   │ 建议修复 │   │ 必须修复 │        │
│             └──────────┘   └──────────┘   └──────────┘        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

三个脚本形成完整的 Skill 开发工作流：
1. `init_skill.py` 创建基础结构
2. 开发者编辑 SKILL.md 和添加资源
3. `quick_validate.py` 验证结构正确性
4. 根据需要调用 `generate_openai_yaml.py` 更新 UI 配置

### 快速验证 vs 完整验证

当前 `quick_validate.py` 定位为"快速验证"，仅检查最基础的结构问题。建议未来扩展为分层验证体系：

| 验证级别 | 检查内容 | 执行时机 |
|----------|----------|----------|
| Quick | frontmatter, name, description | 开发过程中频繁执行 |
| Standard | + agents/openai.yaml, 目录结构 | 提交前 |
| Full | + 内容质量, 链接有效性, 脚本语法 | 发布前 |
| Integration | + 实际执行测试 | CI/CD 流程 |
