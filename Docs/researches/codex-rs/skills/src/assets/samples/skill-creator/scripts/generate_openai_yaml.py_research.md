# generate_openai_yaml.py 研究文档

## 场景与职责

`generate_openai_yaml.py` 是 Skill Creator 工具链中的核心脚本之一，负责为 Skill 目录生成 `agents/openai.yaml` 配置文件。该文件是 OpenAI 产品特定的 UI 元数据配置，用于在 Skill 列表和芯片中展示人类可读的名称、描述、图标等信息。

### 使用场景
1. **Skill 初始化时**：通过 `init_skill.py` 自动调用，为新创建的 Skill 生成初始 UI 配置
2. **Skill 更新时**：独立运行以更新或重新生成 `agents/openai.yaml`，例如在 Skill 元数据变更后
3. **CI/CD 集成**：在自动化流程中批量生成或验证 Skill 的 UI 配置

### 核心职责
- 解析 Skill 目录中的 `SKILL.md` 文件，提取 frontmatter 中的 `name` 字段
- 根据 Skill 名称自动生成格式化的 `display_name`（标题格式）
- 自动生成符合长度约束（25-64 字符）的 `short_description`
- 支持通过命令行参数覆盖默认生成的字段值
- 将配置写入 `agents/openai.yaml` 文件

---

## 功能点目的

### 1. 名称格式化 (`format_display_name`)
将 hyphen-case 的 Skill 名称转换为人类可读的标题格式：
- **首字母大写**：普通单词首字母大写
- **缩写保护**：保留预定义缩写的大写形式（如 GH, MCP, API, CI, CLI, LLM, PDF, PR, UI, URL, SQL）
- **品牌名保护**：使用预定义的品牌名格式（如 OpenAI, GitHub, PagerDuty, DataDog, SQLite, FastAPI）
- **小词处理**：连接词（and, or, to, up, with）在非首位置保持小写

### 2. 描述生成 (`generate_short_description`)
自动生成符合 UI 约束的短描述：
- **最小长度保证**：确保描述至少 25 个字符，通过添加 "tasks and workflows" 或 "with guidance" 扩展
- **最大长度限制**：确保描述不超过 64 个字符，通过逐步截断策略实现：
  1. 尝试 "Help with {display_name}"
  2. 尝试 "{display_name} helper"
  3. 尝试 "{display_name} tools"
  4. 截断 display_name 后加 " helper"
  5. 直接截断到 64 字符

### 3. YAML 安全转义 (`yaml_quote`)
确保生成的 YAML 字符串值安全：
- 转义反斜杠：`\` → `\\`
- 转义双引号：`"` → `\"`
- 转义换行符：`\n` → `\\n`
- 使用双引号包裹整个值

### 4. Frontmatter 解析 (`read_frontmatter_name`)
从 `SKILL.md` 文件中提取 Skill 名称：
- 使用正则表达式匹配 YAML frontmatter（`---\n...\n---`）
- 使用 `yaml.safe_load` 安全解析 frontmatter
- 验证 `name` 字段存在且为有效字符串

### 5. 接口覆盖解析 (`parse_interface_overrides`)
支持通过命令行参数覆盖生成的字段：
- 允许的覆盖键：`display_name`, `short_description`, `icon_small`, `icon_large`, `brand_color`, `default_prompt`
- 格式要求：`key=value` 格式
- 记录可选字段的顺序以保持输出一致性

---

## 具体技术实现

### 关键流程

```
main()
  ├── 解析命令行参数
  │   ├── skill_dir: Skill 目录路径
  │   ├── --name: 可选的 Skill 名称覆盖
  │   └── --interface: 可重复的 key=value 覆盖参数
  ├── 验证 Skill 目录存在且为目录
  ├── 获取 Skill 名称
  │   ├── 优先使用 --name 参数
  │   └── 否则从 SKILL.md frontmatter 提取
  └── 写入 openai.yaml
      ├── 解析接口覆盖参数
      ├── 生成或获取 display_name
      ├── 生成或获取 short_description
      ├── 验证 short_description 长度约束
      ├── 构建 YAML 内容
      └── 写入 agents/openai.yaml
```

### 数据结构

#### 预定义常量集合
```python
ACRONYMS = {"GH", "MCP", "API", "CI", "CLI", "LLM", "PDF", "PR", "UI", "URL", "SQL"}
BRANDS = {"openai": "OpenAI", "github": "GitHub", "pagerduty": "PagerDuty", ...}
SMALL_WORDS = {"and", "or", "to", "up", "with"}
ALLOWED_INTERFACE_KEYS = {"display_name", "short_description", "icon_small", "icon_large", "brand_color", "default_prompt"}
```

#### YAML 输出结构
```yaml
interface:
  display_name: "..."
  short_description: "..."
  # 可选字段（按传入顺序）
  icon_small: "..."
  icon_large: "..."
  brand_color: "..."
  default_prompt: "..."
```

### 命令行接口

```bash
# 基本用法
python generate_openai_yaml.py <skill_dir>

# 指定 Skill 名称
python generate_openai_yaml.py <skill_dir> --name my-skill

# 覆盖接口字段
python generate_openai_yaml.py <skill_dir> --interface display_name="My Skill"
python generate_openai_yaml.py <skill_dir> --interface short_description="Custom description"
python generate_openai_yaml.py <skill_dir> --interface icon_small="./assets/icon.svg"
```

---

## 关键代码路径与文件引用

### 当前文件
- **路径**: `codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py`
- **大小**: 226 行

### 依赖文件
| 文件 | 用途 |
|------|------|
| `SKILL.md` | 读取 frontmatter 获取 Skill 名称 |
| `agents/openai.yaml` | 生成的输出文件 |

### 调用方
| 文件 | 调用方式 |
|------|----------|
| `init_skill.py` | `from generate_openai_yaml import write_openai_yaml` |
| 命令行/CI | 直接执行脚本 |

### 相关引用文档
| 文件 | 内容 |
|------|------|
| `references/openai_yaml.md` | `agents/openai.yaml` 字段完整说明和约束 |

---

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `argparse` | 命令行参数解析 |
| `re` | 正则表达式（frontmatter 匹配） |
| `sys` | 系统退出和错误处理 |
| `pathlib.Path` | 跨平台路径操作 |

### 第三方库
| 库 | 用途 |
|----|------|
| `yaml` | 解析 SKILL.md frontmatter（在 `read_frontmatter_name` 中动态导入） |

### 文件系统交互
1. **读取**: `SKILL.md`（提取 frontmatter）
2. **创建目录**: `agents/`（如果不存在）
3. **写入**: `agents/openai.yaml`

---

## 风险、边界与改进建议

### 已知风险

1. **YAML 注入风险**
   - 当前 `yaml_quote` 仅处理基本转义，可能存在边界情况
   - 建议：考虑使用专门的 YAML 库生成输出，而非字符串拼接

2. **Frontmatter 解析脆弱性**
   - 使用简单正则匹配 frontmatter，可能无法处理复杂情况
   - 边界情况：frontmatter 中包含 `---` 分隔线
   - 建议：考虑使用专门的 YAML frontmatter 解析库

3. **字符编码问题**
   - 未显式处理文件编码，依赖系统默认编码
   - 建议：明确指定 `encoding='utf-8'` 进行文件读写

4. **并发写入风险**
   - 无文件锁机制，并发执行可能导致数据损坏
   - 建议：添加文件锁或使用临时文件 + 原子重命名

### 边界条件

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| Skill 名称超长（>64 字符） | 截断处理 | 添加警告提示 |
| 描述无法同时满足最小和最大长度 | 优先满足最大长度 | 记录警告 |
| 无效的 interface 覆盖键 | 报错退出 | 提供建议的替代键 |
| SKILL.md 不存在 | 报错 | 提供创建模板选项 |
| agents/openai.yaml 已存在 | 直接覆盖 | 添加备份或确认机制 |

### 改进建议

1. **功能增强**
   - 添加 `--dry-run` 模式，预览生成的 YAML 而不写入文件
   - 支持从 `pyproject.toml` 或其他配置文件读取默认值
   - 添加 `--validate` 模式，验证现有 `openai.yaml` 是否符合约束
   - 支持批量处理多个 Skill 目录

2. **错误处理**
   - 更详细的错误上下文（如 frontmatter 行号）
   - 区分可恢复错误和致命错误
   - 添加日志级别控制（--verbose, --quiet）

3. **测试覆盖**
   - 添加单元测试覆盖各种边界条件
   - 添加集成测试验证生成的 YAML 可被正确解析
   - 测试不同字符编码的处理

4. **文档改进**
   - 在脚本中添加更多使用示例
   - 记录字段约束的详细规则
   - 提供与其他工具（如 CI）集成的最佳实践

### 与相关脚本的协作

```
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────────┐
│  init_skill.py  │────▶│ generate_openai_    │────▶│ agents/openai.  │
│  (Skill 初始化)  │     │ yaml.py             │     │ yaml            │
└─────────────────┘     └─────────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │ quick_validate  │
                        │ .py (验证)      │
                        └─────────────────┘
```

三个脚本形成完整的 Skill 创建和验证工作流：
1. `init_skill.py` 创建基础结构和模板
2. `generate_openai_yaml.py` 生成 UI 元数据配置
3. `quick_validate.py` 验证 Skill 结构正确性
