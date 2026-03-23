# init_skill.py 研究文档

## 场景与职责

`init_skill.py` 是 Skill Creator 工具链的核心入口脚本，用于从零创建一个新的 Skill 目录结构。它是 Skill 创建流程（Step 3: Initializing the Skill）的自动化实现，提供标准化的 Skill 初始化模板和目录结构。

### 使用场景
1. **新 Skill 开发**：开发者创建新的 Skill 时使用此脚本生成基础结构
2. **Skill 模板生成**：为特定领域快速生成可复用的 Skill 模板
3. **自动化流程**：在 CI/CD 或自动化工具链中批量创建 Skill

### 核心职责
- 创建标准化的 Skill 目录结构
- 生成带有 TODO 占位符的 `SKILL.md` 模板文件
- 调用 `generate_openai_yaml.py` 生成 `agents/openai.yaml`
- 可选创建资源目录（scripts/, references/, assets/）
- 可选在资源目录中生成示例文件
- 提供清晰的后续步骤指引

---

## 功能点目的

### 1. Skill 名称规范化 (`normalize_skill_name`)
确保 Skill 名称符合命名规范：
- **转换为小写**：统一使用小写字母
- **特殊字符转连字符**：非字母数字字符转为 `-`
- **去除首尾连字符**：避免以连字符开头或结尾
- **合并连续连字符**：多个连续连字符合并为单个

**示例**：
- `"My New Skill"` → `"my-new-skill"`
- `"Skill--Name!!"` → `"skill-name"`

### 2. Skill 名称标题化 (`title_case_skill_name`)
将 hyphen-case 名称转换为标题格式，用于 SKILL.md 中的标题：
- 每个单词首字母大写
- 用空格替换连字符

**示例**：
- `"my-new-skill"` → `"My New Skill"`

### 3. 资源类型解析 (`parse_resources`)
解析 `--resources` 参数：
- 支持逗号分隔的资源类型列表
- 验证资源类型有效性（只允许 `scripts`, `references`, `assets`）
- 去重处理（保持传入顺序）
- 无效资源类型会导致脚本退出并显示错误

### 4. 资源目录创建 (`create_resource_dirs`)
根据指定的资源类型创建对应目录：
- **scripts/**: 可执行脚本目录
- **references/**: 参考文档目录
- **assets/**: 资源文件目录

当 `--examples` 标志启用时，还会在每个目录中生成示例文件。

### 5. Skill 初始化主流程 (`init_skill`)
协调整个初始化过程：
1. 确定 Skill 目录路径
2. 检查目录是否已存在（避免覆盖）
3. 创建 Skill 目录
4. 生成 SKILL.md（从模板填充）
5. 调用 `write_openai_yaml` 生成 agents/openai.yaml
6. 创建资源目录（如果指定）
7. 打印成功消息和后续步骤指引

---

## 具体技术实现

### 关键流程

```
main()
  ├── 解析命令行参数
  │   ├── skill_name: Skill 名称（原始输入）
  │   ├── --path: 输出目录（必需）
  │   ├── --resources: 可选的资源类型列表
  │   ├── --examples: 是否生成示例文件
  │   └── --interface: 接口字段覆盖
  ├── 规范化 Skill 名称
  │   ├── 转换为 hyphen-case
  │   ├── 验证非空
  │   └── 验证长度（≤64 字符）
  ├── 解析资源类型
  ├── 打印初始化信息
  └── 调用 init_skill()
      ├── 构建完整路径（path/skill_name）
      ├── 检查目录是否存在
      ├── 创建目录
      ├── 生成 SKILL.md
      │   ├── 使用 SKILL_TEMPLATE
      │   ├── 填充 skill_name
      │   └── 填充 skill_title
      ├── 生成 agents/openai.yaml
      │   └── 调用 write_openai_yaml()
      ├── 创建资源目录（如果指定）
      │   └── 调用 create_resource_dirs()
      └── 打印后续步骤
```

### 数据结构

#### 模板常量

**SKILL_TEMPLATE**: SKILL.md 的主模板
- 包含 YAML frontmatter 占位符
- 提供结构指导（4 种常见模式）
- 包含资源类型说明
- 使用 `[TODO: ...]` 标记待完成项

**EXAMPLE_SCRIPT**: 示例脚本模板
- Python 3 shebang
- 文档字符串占位符
- main() 函数框架
- 文件权限设置为 755（可执行）

**EXAMPLE_REFERENCE**: 示例参考文档模板
- Markdown 格式
- 参考文档用途说明
- 结构建议（API 参考、工作流指南）

**EXAMPLE_ASSET**: 示例资源文件模板
- 文本占位符
- 常见资源类型列表

#### 常量定义
```python
MAX_SKILL_NAME_LENGTH = 64
ALLOWED_RESOURCES = {"scripts", "references", "assets"}
```

### 命令行接口

```bash
# 基本用法
python init_skill.py <skill-name> --path <output-directory>

# 创建带资源的 Skill
python init_skill.py my-skill --path skills/public --resources scripts,references

# 创建带示例文件的 Skill
python init_skill.py my-skill --path skills/public --resources scripts --examples

# 指定接口字段
python init_skill.py my-skill --path skills/public --interface display_name="My Skill"
```

### 生成的目录结构

```
skill-name/
├── SKILL.md                    # 主文档（从模板生成）
├── agents/
│   └── openai.yaml            # UI 元数据（通过 generate_openai_yaml.py）
├── scripts/                   # 可选（--resources scripts）
│   └── example.py             # 可选（--examples）
├── references/                # 可选（--resources references）
│   └── api_reference.md       # 可选（--examples）
└── assets/                    # 可选（--resources assets）
    └── example_asset.txt      # 可选（--examples）
```

---

## 关键代码路径与文件引用

### 当前文件
- **路径**: `codex-rs/skills/src/assets/samples/skill-creator/scripts/init_skill.py`
- **大小**: 400 行

### 依赖文件
| 文件 | 用途 |
|------|------|
| `generate_openai_yaml.py` | 导入 `write_openai_yaml` 函数生成 UI 配置 |

### 生成文件
| 文件 | 说明 |
|------|------|
| `SKILL.md` | 主 Skill 文档，包含 frontmatter 和 TODO |
| `agents/openai.yaml` | UI 元数据配置 |
| `scripts/example.py` | 示例脚本（--examples 时）|
| `references/api_reference.md` | 示例参考文档（--examples 时）|
| `assets/example_asset.txt` | 示例资源文件（--examples 时）|

### 调用方
| 来源 | 说明 |
|------|------|
| 命令行 | 开发者直接执行 |
| Codex Agent | 根据 SKILL.md 指导自动执行 |

### 相关文档
| 文件 | 内容 |
|------|------|
| `SKILL.md` | Skill Creator 的完整使用指南，包含 init_skill.py 使用说明 |
| `references/openai_yaml.md` | agents/openai.yaml 字段说明 |

---

## 依赖与外部交互

### Python 标准库
| 模块 | 用途 |
|------|------|
| `argparse` | 命令行参数解析 |
| `re` | 正则表达式（名称规范化） |
| `sys` | 系统退出和错误处理 |
| `pathlib.Path` | 跨平台路径操作 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `generate_openai_yaml` | 导入 `write_openai_yaml` 函数 |

### 文件系统交互
1. **创建目录**: Skill 根目录、agents/、资源目录
2. **写入文件**: SKILL.md、agents/openai.yaml、示例文件
3. **设置权限**: 示例脚本设置为可执行（0o755）

---

## 风险、边界与改进建议

### 已知风险

1. **目录覆盖风险**
   - 当前实现会检查目录是否存在，但存在竞态条件
   - 建议：使用 `exist_ok=False` 并在捕获特定异常后重试

2. **部分失败处理**
   - 如果中间步骤失败（如生成 openai.yaml），已创建的文件和目录不会自动清理
   - 建议：实现事务性创建，失败时回滚或提供清理命令

3. **权限问题**
   - 未处理文件系统权限不足的情况
   - 建议：添加权限检查和友好的错误提示

4. **路径遍历风险**
   - 使用 `Path.resolve()` 但未验证最终路径是否在预期范围内
   - 建议：验证解析后的路径不包含 `..` 或指向系统敏感目录

### 边界条件

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| Skill 名称为空（仅特殊字符） | 报错退出 | 提供更具体的错误信息 |
| Skill 名称超长（>64） | 报错退出 | 提供截断选项或建议 |
| 输出目录不存在 | 通过 `parents=True` 自动创建 | 添加确认提示 |
| --examples 但未指定 --resources | 报错退出 | 自动推断或提供更清晰的错误 |
| 磁盘空间不足 | 抛出异常 | 提前检查可用空间 |
| 文件名大小写敏感问题 | 依赖系统行为 | 统一使用小写 |

### 改进建议

1. **功能增强**
   - 添加 `--dry-run` 模式，预览将要创建的文件结构
   - 支持从现有 Skill 复制/继承（`--template` 参数）
   - 添加交互式模式（`--interactive`），引导用户输入关键信息
   - 支持批量创建多个相关 Skill
   - 添加 `--git-init` 选项，自动初始化 Git 仓库

2. **模板系统改进**
   - 支持自定义模板（`--template-dir`）
   - 提供多种预设模板（workflow-based, task-based, reference-based）
   - 模板变量扩展（支持更多占位符）
   - 条件模板内容（根据资源类型调整 SKILL.md 内容）

3. **验证和检查**
   - 创建后自动运行 `quick_validate.py`
   - 检查 Skill 名称全局唯一性
   - 验证输出目录可写
   - 检查依赖工具（Python 版本、yaml 库）

4. **用户体验**
   - 添加 `--verbose` 和 `--quiet` 输出控制
   - 彩色输出支持（成功/错误状态）
   - 生成初始化报告（创建的文件列表）
   - 提供 `cd <skill-dir>` 命令复制提示

5. **集成改进**
   - 支持配置文件（`.skillrc` 或 `pyproject.toml`）
   - 环境变量支持（`SKILL_DEFAULT_PATH` 等）
   - 与 IDE 插件集成
   - 生成 IDE 配置文件（.vscode/settings.json 等）

### 代码质量建议

1. **类型注解**
   - 为所有函数添加类型注解
   - 使用 `Optional`, `List`, `Dict` 等明确类型

2. **错误处理**
   - 使用自定义异常类
   - 提供更详细的错误上下文
   - 添加错误代码便于文档引用

3. **测试覆盖**
   - 单元测试：名称规范化、资源解析
   - 集成测试：完整初始化流程
   - 边界测试：各种错误条件

### 与相关脚本的协作

```
┌─────────────────────────────────────────────────────────────────┐
│                      Skill 创建流程                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐                                            │
│  │ 理解 Skill 需求  │                                            │
│  │ (人工/Codex)    │                                            │
│  └────────┬────────┘                                            │
│           ▼                                                     │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ 规划资源内容    │────▶│ init_skill.py   │                   │
│  │ (scripts/refs)  │     │ - 创建目录结构  │                   │
│  └─────────────────┘     │ - 生成 SKILL.md │                   │
│                          │ - 生成 openai.  │                   │
│                          │   yaml          │                   │
│                          └────────┬────────┘                   │
│                                   ▼                            │
│                          ┌─────────────────┐                   │
│                          │ 编辑 SKILL.md   │                   │
│                          │ 添加资源文件    │                   │
│                          │ (人工/Codex)    │                   │
│                          └────────┬────────┘                   │
│                                   ▼                            │
│                          ┌─────────────────┐                   │
│                          │quick_validate.py│                   │
│                          │ - 验证结构      │                   │
│                          │ - 检查 frontmat │                   │
│                          │   ter           │                   │
│                          └────────┬────────┘                   │
│                                   ▼                            │
│                          ┌─────────────────┐                   │
│                          │ 迭代优化        │                   │
│                          │ 前向测试        │                   │
│                          └─────────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

三个脚本形成完整的 Skill 开发工作流：
1. `init_skill.py` 创建基础结构和模板
2. 开发者编辑 SKILL.md 和添加资源
3. `quick_validate.py` 验证结构正确性
4. 根据需要调用 `generate_openai_yaml.py` 更新 UI 配置
