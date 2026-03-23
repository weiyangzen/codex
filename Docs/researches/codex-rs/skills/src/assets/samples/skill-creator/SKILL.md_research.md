# SKILL.md 研究文档

## 场景与职责

`SKILL.md` 是 `skill-creator` 系统技能的核心文档，作为 Codex CLI 的**元技能（Meta-Skill）**。它的职责是指导用户（或其他 AI 实例）如何创建、更新和验证新的技能（Skill）。

### 核心场景

1. **技能创建指导**：当用户需要创建新技能时，通过 `$skill-creator` 触发该技能，获取完整的创建流程指导
2. **技能更新指导**：当现有技能需要迭代改进时，提供修改和验证的指导
3. **最佳实践传播**：将技能设计的核心原则、结构规范、工作流程标准化并传播

### 在项目中的定位

- 该文件位于 `codex-rs/skills/src/assets/samples/skill-creator/`，是**嵌入式系统技能**的一部分
- 通过 `include_dir` 在编译时嵌入到 `codex-skills` crate 中
- 在运行时通过 `install_system_skills()` 函数解压到用户的 `CODEX_HOME/skills/.system/` 目录
- 被 `codex-rs/core/tests/suite/skills.rs` 测试用例验证，确保系统技能正确安装和加载

---

## 功能点目的

### 1. 技能概念教育

向用户解释什么是技能（Skill）：
- 模块化的、自包含的文件夹
- 扩展 Codex 能力的专用知识、工作流和工具
- 将通用 AI 代理转变为特定领域的专业代理

### 2. 核心设计原则传授

**三大核心原则**：

| 原则 | 目的 | 实践指导 |
|------|------|----------|
| **Concise is Key** | 上下文窗口是公共资源 | 只添加 Codex 不知道的信息，优先简洁示例而非冗长解释 |
| **Set Appropriate Degrees of Freedom** | 根据任务脆弱性匹配具体程度 | 脆弱操作给低自由度（具体脚本），开放任务给高自由度（文本指导） |
| **Protect Validation Integrity** | 使用子代理验证技能效果 | 传递原始工件而非结论，避免上下文泄漏 |

### 3. 技能结构规范

定义标准技能目录结构：

```
skill-name/
├── SKILL.md (必需) - YAML frontmatter + Markdown 指令
├── agents/openai.yaml (推荐) - UI 元数据
├── scripts/ (可选) - 可执行代码
├── references/ (可选) - 参考文档
└── assets/ (可选) - 输出资源文件
```

### 4. 渐进式披露设计

三级加载系统管理上下文效率：

1. **Metadata** (`name` + `description`) - 始终在上下文中 (~100 词)
2. **SKILL.md body** - 技能触发时加载 (<5k 词)
3. **Bundled resources** - 按需加载（无限制，脚本可直接执行）

### 5. 技能创建流程

六步标准化流程：

1. **理解技能** - 通过具体示例明确技能用途
2. **规划可复用内容** - 识别需要的 scripts/references/assets
3. **初始化技能** - 运行 `init_skill.py` 创建模板
4. **编辑技能** - 实现资源和编写 SKILL.md
5. **验证技能** - 运行 `quick_validate.py` 检查结构
6. **迭代优化** - 基于实际使用和前向测试改进

---

## 具体技术实现

### 文档结构与格式

**YAML Frontmatter**（必需）：
```yaml
---
name: skill-creator
description: Guide for creating effective skills...
metadata:
  short-description: Create or update a skill
---
```

**关键约束**：
- `name` 和 `description` 是 Codex 决定何时使用技能的唯一字段
- `description` 必须包含技能功能和使用场景（触发条件）
- 名称使用小写字母、数字和连字符（hyphen-case）

### 渐进式披露模式

**模式 1：高级指南 + 引用**
```markdown
## Quick start
[核心代码示例]

## Advanced features
- **Form filling**: See [FORMS.md](FORMS.md) for complete guide
- **API reference**: See [REFERENCE.md](REFERENCE.md)
```

**模式 2：领域特定组织**
```
bigquery-skill/
├── SKILL.md (概述和导航)
└── reference/
    ├── finance.md
    ├── sales.md
    └── product.md
```

**模式 3：条件详情**
```markdown
## Creating documents
Use docx-js for new documents.

**For tracked changes**: See [REDLINING.md](REDLINING.md)
```

### 配套脚本集成

SKILL.md 指导用户使用三个 Python 脚本：

| 脚本 | 功能 | 使用场景 |
|------|------|----------|
| `init_skill.py` | 创建技能目录模板 | 步骤 3 - 初始化 |
| `generate_openai_yaml.py` | 生成 UI 元数据 | 创建/更新 agents/openai.yaml |
| `quick_validate.py` | 验证技能结构 | 步骤 5 - 验证 |

### 命名规范

```python
# 技能名称规范（来自 init_skill.py）
- 仅小写字母、数字、连字符
- 最大 64 字符
- 规范化：去除首尾连字符，合并连续连字符
- 示例："Plan Mode" -> "plan-mode"
```

### 前向测试协议

```
正确的前向测试提示：
  "Use $skill-x at /path/to/skill-x to solve problem y"

错误的前向测试提示（泄漏上下文）：
  "Review the skill at /path/to/skill-x; pretend a user asks you to..."
```

---

## 关键代码路径与文件引用

### 当前文件

- **路径**: `codex-rs/skills/src/assets/samples/skill-creator/SKILL.md`
- **大小**: 22,047 bytes
- **行数**: 416 行

### 直接依赖文件

| 文件 | 路径 | 关系 |
|------|------|------|
| `openai.yaml` | `agents/openai.yaml` | UI 元数据，被引用 |
| `openai_yaml.md` | `references/openai_yaml.md` | 字段定义和示例，被引用 |
| `init_skill.py` | `scripts/init_skill.py` | 初始化脚本，被指导使用 |
| `generate_openai_yaml.py` | `scripts/generate_openai_yaml.py` | YAML 生成脚本，被指导使用 |
| `quick_validate.py` | `scripts/quick_validate.py` | 验证脚本，被指导使用 |

### 调用方代码

| 代码 | 路径 | 用途 |
|------|------|------|
| `lib.rs` | `codex-rs/skills/src/lib.rs` | 嵌入和安装系统技能 |
| `skills.rs` | `codex-rs/core/tests/suite/skills.rs` | 测试系统技能加载 |
| `v2.rs` | `codex-rs/app-server-protocol/src/protocol/v2.rs` | 协议示例引用 |
| `README.md` | `codex-rs/app-server/README.md` | API 文档示例 |

### 编译时嵌入

```rust
// codex-rs/skills/src/lib.rs
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

### 运行时安装

```rust
// install_system_skills() 函数流程
1. 检查 marker 文件指纹
2. 如果指纹匹配，跳过安装
3. 否则，清除旧目录
4. 写入嵌入式目录内容
5. 更新 marker 文件
```

---

## 依赖与外部交互

### 内部依赖

| 组件 | 关系 |
|------|------|
| `codex-skills` crate | 宿主 crate，负责嵌入和安装 |
| `include_dir` | 编译时目录嵌入 |
| `codex-utils-absolute-path` | 路径处理 |

### 外部工具依赖

| 工具 | 用途 | 调用方式 |
|------|------|----------|
| Python 3 | 执行配套脚本 | 命令行 |
| PyYAML | YAML 解析 | Python 库 |

### 运行时环境

- **CODEX_HOME**: 技能安装目标根目录
- **默认路径**: `~/.codex/skills/.system/skill-creator/`
- **Marker 文件**: `.codex-system-skills.marker`（用于指纹缓存）

### 与其他技能的交互

- **skill-installer**: 并行的系统技能，负责技能安装管理
- **openai-docs**: 并行的系统技能，提供 OpenAI API 文档

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 上下文窗口膨胀 | SKILL.md 本身较大（22KB），可能占用过多上下文 | 已通过渐进式披露设计缓解，但仍有优化空间 |
| 脚本依赖 Python | 用户环境可能缺少 Python 或 PyYAML | 脚本有错误处理，但无自动安装机制 |
| 技能名称冲突 | 用户创建的技能可能与系统技能同名 | 系统技能安装在 `.system/` 子目录，与用户技能隔离 |
| 指纹缓存失效 | 标记文件可能因手动修改而失效 | 使用内容哈希指纹，修改后自动重新安装 |

### 边界情况

1. **超长描述**: `description` 字段最大 1024 字符，超出会被验证脚本拒绝
2. **非法字符**: 技能名称只能包含 `[a-z0-9-]`，其他字符会被规范化或报错
3. **嵌套引用**: 文档建议避免深层嵌套引用，所有引用文件应直接从 SKILL.md 链接
4. **Windows 兼容性**: 测试文件明确排除 Windows (`#![cfg(not(target_os = "windows"))]`)

### 改进建议

#### 高优先级

1. **添加版本控制**
   - 当前 SKILL.md 无版本号，难以追踪更新
   - 建议添加 `version` 字段到 frontmatter

2. **优化上下文占用**
   - 考虑将部分内容移到 references/，进一步减少核心文档体积
   - 特别是 "Structuring This Skill" 部分可以外置

3. **增强验证脚本**
   - `quick_validate.py` 目前只验证 frontmatter
   - 建议添加对 agents/openai.yaml 的验证
   - 建议添加对引用文件存在性的检查

#### 中优先级

4. **多语言支持**
   - 当前仅英文，考虑 i18n 框架
   - 或提供翻译指南

5. **脚本独立化**
   - 考虑将 Python 脚本重写为 Rust，减少外部依赖
   - 或提供独立的二进制分发

6. **模板丰富化**
   - `init_skill.py` 的模板可以按技能类型提供多种选择
   - 如：工具类、工作流类、参考类

#### 低优先级

7. **自动化测试集成**
   - 提供技能模板的自动化测试框架
   - 帮助用户验证技能行为是否符合预期

8. **文档交叉链接**
   - 添加与其他系统技能（如 skill-installer）的交叉引用
   - 形成完整的技能生态系统文档

### 技术债务

- `SKILL.md` 第 344 行提到 "Always use imperative/infinitive form"，但文档本身不完全遵循此规则
- 部分示例代码使用 TODO 占位符，可能影响初次阅读体验
- `init_skill.py` 模板中的 "Structuring This Skill" 指导章节过长，建议精简
