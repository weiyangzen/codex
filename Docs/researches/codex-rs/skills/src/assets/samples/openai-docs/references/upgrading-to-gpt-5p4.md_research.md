# upgrading-to-gpt-5p4.md 研究文档

## 场景与职责

本文件是 OpenAI Docs Skill 的核心参考文档之一，专门用于指导用户将现有集成升级到 GPT-5.4。它属于 `codex-rs/skills` crate 中嵌入的系统 Skill 资源文件，在构建时通过 `include_dir` 嵌入到二进制中，运行时解压到用户目录的 `CODEX_HOME/skills/.system/` 路径下。

主要职责包括：
1. 提供系统化的 GPT-5.4 升级工作流程
2. 定义升级分类体系（model string only / model string + light prompt rewrite / blocked）
3. 提供无代码兼容性检查清单
4. 定义升级输出的结构化格式
5. 明确升级指导的范围边界

## 功能点目的

### 1. 升级姿态（Upgrade posture）

定义升级的基本原则：
- **最小化变更集**：使用最窄的安全变更集进行升级
- 优先仅替换模型字符串
- 仅更新直接与该模型使用相关的 Prompt
- 尽可能优先仅通过 Prompt 升级
- 如果升级需要 API 表面变更、参数重写、工具重新连接或更广泛的代码编辑，则标记为阻塞而非扩大范围

### 2. 升级工作流程（Upgrade workflow）

定义 7 步升级流程：

1. **清点当前模型使用**
   - 搜索模型字符串、客户端调用和包含 Prompt 的文件
   - 包括内联 Prompt、Prompt 模板、YAML/JSON 配置、Markdown 文档和保存的 Prompt

2. **将每个模型使用与其 Prompt 表面对配对**
   - 优先选择最接近的 Prompt 表面：内联系统或开发者文本，然后是相邻 Prompt 文件，最后是共享模板
   - 如果无法自信地将 Prompt 与模型使用关联，应说明而非猜测

3. **分类源模型家族**
   - 常见分类：GPT-4o/GPT-4.1、o1/o3/o4-mini、早期 GPT-5、后期 GPT-5.x 或混合/不清楚

4. **决定升级类别**
   - `model string only`
   - `model string + light prompt rewrite`
   - `blocked without code changes`

5. **运行无代码兼容性门控**
   - 检查当前集成是否可以在没有 API 表面变更或实现变更的情况下接受 `gpt-5.4`
   - 对于长运行 Responses 或工具密集型 Agent，检查当主机重放助手项目或使用序言时 `phase` 是否已经保留或往返传输
   - 如果兼容性依赖于代码变更，返回 `blocked`
   - 如果兼容性不清楚，返回 `unknown` 而非即兴发挥

6. **推荐升级**
   - 默认替换字符串：`gpt-5.4`
   - 保持干预小而行为保持

7. **交付结构化推荐**
   - 当前模型使用
   - 推荐的模型字符串更新
   - 起始推理建议
   - Prompt 更新
   - 相关时的 `phase` 评估
   - 无代码兼容性检查
   - 验证计划
   - 发布日刷新项目

**输出规则**：
- 始终为每个使用站点发出起始 `reasoning_effort_recommendation`
- 如果仓库暴露当前推理设置，首先保留它，除非源指南另有说明
- 如果仓库不暴露当前设置，使用源家族起始映射而非返回 `null`

### 3. 升级结果分类

#### `model string only`（仅模型字符串）

**选择时机**：
- 现有 Prompt 已经简短、明确且任务有界
- 工作流不是强烈研究密集型、工具密集型、多 Agent、批次或完整性敏感的，也不是长程的
- 没有明显的兼容性阻塞点

**默认操作**：
- 将模型字符串替换为 `gpt-5.4`
- 保持 Prompt 不变
- 使用现有评估或抽查验证行为

#### `model string + light prompt rewrite`（模型字符串 + 轻量 Prompt 重写）

**选择时机**：
- 旧 Prompt 补偿了较弱的指令遵循能力
- 工作流需要比默认工具使用行为可能提供的更多持久性
- 任务需要更强的完整性、引用规范或验证
- 升级后的模型变得过于冗长或不够完整，除非另有指示
- 工作流是研究密集型的，需要更强的稀疏或空检索结果处理
- 工作流是编码导向的、工具密集型的或多 Agent 的，但现有 API 表面和工具定义可以保持不变

**默认操作**：
- 将模型字符串替换为 `gpt-5.4`
- 添加一两个有针对性的 Prompt 代码块
- 阅读 `references/gpt-5p4-prompting-guide.md` 选择恢复旧行为的最小 Prompt 变更
- 避免与升级无关的广泛 Prompt 清理
- 研究工作流默认使用 `research_mode` + `citation_rules` + `empty_result_handling`；主机已使用检索工具时添加 `tool_persistence_rules`
- 依赖感知或工具密集型工作流默认使用 `tool_persistence_rules` + `dependency_checks` + `verification_loop`；检索步骤真正独立时才添加 `parallel_tool_calling`
- 编码或终端工作流默认使用 `terminal_tool_hygiene` + `verification_loop`
- 多 Agent 支持或分类工作流默认至少使用 `tool_persistence_rules`、`completeness_contract` 或 `verification_loop` 中的一个
- 对于带有序言或多个助手消息的长运行 Responses Agent，明确检查 `phase` 是否已处理；如果添加或保留 `phase` 需要代码编辑，将该路径标记为 `blocked`
- 不要因为可见片段最小就将编码或使用工具的 Responses 工作流分类为 `blocked`；除非仓库明确显示安全的 GPT-5.4 路径需要主机端代码变更，否则优先选择 `model string + light prompt rewrite`

#### `blocked`（阻塞）

**选择时机**：
- 升级似乎需要 API 表面变更
- 升级似乎需要参数重写或推理设置变更，而这些变更在实现代码外部未暴露
- 升级需要更改工具定义、工具处理程序连接或模式契约
- 无法自信地识别与模型使用关联的 Prompt 表面

**默认操作**：
- 不要即兴发挥更广泛的升级
- 报告阻塞点并解释修复超出了本指南的范围

### 4. 无代码兼容性检查清单

推荐无代码升级前检查 6 项：

1. 当前主机是否可以在不更改客户端代码或 API 表面的情况下接受 `gpt-5.4` 模型字符串？
2. 相关 Prompt 是否可识别和可编辑？
3. 主机是否依赖可能需要 API 表面变更、参数重写或工具重新连接的行为？
4. 可能的修复是仅通过 Prompt 还是需要实现变更？
5. Prompt 表面是否足够接近模型使用，可以进行有针对性的变更而非广泛清理？
6. 对于长运行 Responses 或工具密集型 Agent，如果主机依赖序言、重放的助手项目或多个助手消息，`phase` 是否已经保留？

**决策规则**：
- 如果第 1 项为否，第 3-4 项指向实现工作，或第 6 项为否且修复需要代码变更，返回 `blocked`
- 如果第 2 项为否，返回 `unknown`，除非用户可以指出 Prompt 位置

**重要说明**：
- 现有工具、Agent 或多个使用站点的使用本身不是阻塞点
- 如果当前主机可以保持相同的 API 表面和相同的工具定义，优先选择 `model string + light prompt rewrite` 而非 `blocked`
- 仅将 `blocked` 保留给真正需要实现变更的案例，而非仅需要更强 Prompt 引导的案例

### 5. 范围边界（Scope boundaries）

**本指南可以**：
- 更新或推荐更新的模型字符串
- 更新或推荐更新的 Prompt
- 检查代码和 Prompt 文件以了解这些变更属于何处
- 检查现有 Responses 流程是否已保留 `phase`
- 标记兼容性阻塞点

**本指南不可以**：
- 将 Chat Completions 代码移至 Responses
- 将 Responses 代码移至另一个 API 表面
- 重写参数形状
- 更改工具定义或工具调用处理
- 更改结构化输出连接
- 在实现代码中添加或改造 `phase` 处理
- 编辑业务逻辑、编排逻辑或超出字面模型字符串替换的 SDK 使用

如果安全的 GPT-5.4 升级需要上述任何变更，将该路径标记为阻塞和超出范围。

### 6. 验证计划（Validation plan）

- 使用现有评估或真实抽查验证每个升级的使用站点
- 检查升级后的模型是否仍符合预期的延迟、输出形状和质量
- 如果添加了 Prompt 编辑，确认每个代码块都在做实际工作而非添加噪音
- 如果工作流有下游影响，在最终确定前添加轻量级验证通过

### 7. 发布日刷新项目（Launch-day refresh items）

当最终 GPT-5.4 指导变更时：

1. 在适当的地方用最终 GPT-5.4 指导替换发布候选假设
2. 重新检查默认目标字符串是否应对所有源家族保持 `gpt-5.4`
3. 重新检查任何语义可能已变更的 Prompt 代码块推荐
4. 根据最终模型行为重新检查研究、引用和兼容性指导
5. 重新运行相同的升级场景并确认阻塞与可行边界仍然成立

## 具体技术实现

### 文档结构

本文档采用 Markdown 格式，包含以下结构：

```markdown
# 标题和简介
## 升级姿态
## 升级工作流程（7 步）
## 升级结果（3 种分类）
## 无代码兼容性检查清单
## 范围边界
## 验证计划
## 发布日刷新项目
```

### 决策流程图

文档隐含了以下决策流程：

```
开始升级评估
    ↓
清点当前模型使用
    ↓
配对 Prompt 表面
    ↓
分类源模型家族
    ↓
运行无代码兼容性检查
    ↓
是否存在阻塞点？
    ↓ 是
返回 blocked
    ↓ 否
Prompt 是否需要变更？
    ↓ 否
返回 model string only
    ↓ 是
返回 model string + light prompt rewrite
    ↓
生成结构化推荐
```

### 结构化输出格式

文档定义了推荐的输出格式，包含 8 个字段：

1. `Current model usage`：当前模型使用情况
2. `Recommended model-string updates`：推荐的模型字符串更新
3. `Starting reasoning recommendation`：起始推理建议
4. `Prompt updates`：Prompt 更新
5. `Phase assessment`：Phase 评估（长运行、重放或工具密集型时）
6. `No-code compatibility check`：无代码兼容性检查
7. `Validation plan`：验证计划
8. `Launch-day refresh items`：发布日刷新项目

## 关键代码路径与文件引用

### 当前文件

- **路径**: `codex-rs/skills/src/assets/samples/openai-docs/references/upgrading-to-gpt-5p4.md`
- **大小**: 8,611 bytes
- **格式**: Markdown

### 相关文件

| 文件路径 | 关系 | 说明 |
|---------|------|------|
| `codex-rs/skills/src/assets/samples/openai-docs/SKILL.md` | 父 Skill 定义 | 定义何时加载本参考文档 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/gpt-5p4-prompting-guide.md` | 配套文档 | Prompt 升级代码块定义 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/latest-model.md` | 配套文档 | 模型选择参考 |
| `codex-rs/skills/src/lib.rs` | 加载实现 | 系统 Skill 的安装和加载逻辑 |
| `codex-rs/skills/build.rs` | 构建脚本 | 监控资源文件变更 |

### 加载触发条件

根据 `SKILL.md` 中的定义，本文件在以下情况被加载：

```markdown
3. If it is an explicit GPT-5.4 upgrade request, load `references/upgrading-to-gpt-5p4.md`.
```

即：当用户明确提出 GPT-5.4 升级或升级规划请求时。

## 依赖与外部交互

### 内部依赖

1. **OpenAI Docs Skill 框架**
   - 依赖 `SKILL.md` 中定义的工作流来触发加载
   - 与 `gpt-5p4-prompting-guide.md` 形成升级指导的完整体系（流程 + 代码块）

2. **codex-skills crate**
   - 提供系统 Skill 的安装和管理基础设施
   - 通过 `SYSTEM_SKILLS_DIR` 常量嵌入本文件

### 外部依赖

1. **OpenAI 官方文档**
   - 文档明确声明需要与当前 OpenAI 文档查找配对使用
   - 检查清单和兼容性指导必须与当前 OpenAI 文档进行验证

2. **MCP Server**
   - Skill 优先使用 `openaiDeveloperDocs` MCP 工具获取最新信息
   - 本文件仅作为辅助上下文，不能替代 MCP 工具返回的权威信息

3. **GPT-5.4 模型特性**
   - 文档基于 GPT-5.4 的特定行为特征（如 `phase` 处理、reasoning effort 等）
   - 如果模型行为在后续版本中发生变化，文档可能需要更新

### 交互流程

```
用户提出 GPT-5.4 升级请求
    ↓
OpenAI Docs Skill 加载 SKILL.md
    ↓
识别为升级请求
    ↓
加载 references/upgrading-to-gpt-5p4.md
    ↓
如有需要，加载 references/gpt-5p4-prompting-guide.md
    ↓
使用 MCP 工具验证兼容性信息
    ↓
执行 7 步升级工作流程
    ↓
生成结构化推荐
    ↓
向用户提供升级指导
```

## 风险、边界与改进建议

### 风险

1. **Phase 处理复杂性**
   - `phase` 是 Responses API 的一个重要概念，用于管理长运行会话状态
   - 文档多次提到需要检查 `phase` 是否已保留，但这是一个技术细节
   - 用户可能不理解 `phase` 的概念或如何检查其状态

2. **分类主观性**
   - 区分 `model string only`、`model string + light prompt rewrite` 和 `blocked` 需要专业判断
   - 不同用户可能对同一情况做出不同分类
   - 错误的分类可能导致不必要的代码修改或遗漏必要的实现变更

3. **文档漂移风险**
   - 发布日刷新项目列表表明文档内容基于发布候选假设
   - 最终 GPT-5.4 指导可能与文档中的假设不同
   - 需要持续维护以保持文档的准确性

4. **unknown 状态的处理**
   - 文档建议在不清楚时返回 `unknown` 而非即兴发挥
   - 但用户可能不知道如何处理 `unknown` 状态
   - 可能需要更多指导来帮助用户从 `unknown` 推进到明确状态

### 边界

1. **范围限制严格**
   - 文档明确列出了 7 项不允许的操作
   - 这些限制确保升级指导保持聚焦，但也可能限制了解决某些场景的能力
   - 用户可能需要额外的指导来处理超出范围的情况

2. **依赖用户输入**
   - 升级流程需要用户能够识别和提供 Prompt 表面位置
   - 如果用户无法做到这一点，流程可能停滞在 `unknown` 状态

3. **模型特定性**
   - 文档专门针对 GPT-5.4 升级编写
   - 可能不完全适用于其他模型升级场景

### 改进建议

1. **添加 Phase 解释附录**
   - 考虑添加关于 `phase` 概念的简要解释
   - 帮助用户理解何时以及为什么需要检查 `phase` 状态
   - 可以包含示例代码展示如何检查 `phase` 是否已保留

2. **分类决策树可视化**
   - 将隐含的决策流程图显式化为可视化图表
   - 帮助用户更直观地理解分类逻辑
   - 可以作为快速参考工具

3. **添加案例研究**
   - 文档提供了理论框架，但缺少具体的 before/after 案例
   - 建议添加 2-3 个真实的升级案例，展示完整的 7 步流程应用

4. **unknown 状态处理指南**
   - 扩展关于如何处理 `unknown` 状态的指导
   - 提供用户可以采取的步骤来收集更多信息
   - 定义何时应该寻求外部帮助

5. **与 gpt-5p4-prompting-guide.md 的交叉引用**
   - 文档提到了 Prompt 代码块，但没有直接链接到具体定义
   - 建议添加更具体的交叉引用，方便用户查找代码块详情

6. **自动化检查工具**
   - 考虑开发辅助工具来自动化部分检查清单项目
   - 例如，自动扫描代码库中的模型字符串和 Prompt 表面

7. **版本控制**
   - 添加文档版本号，与 GPT-5.4 的发布版本对应
   - 在发布日刷新项目完成后更新版本号

8. **扩展验证计划**
   - 当前验证计划较为简略
   - 建议添加具体的评估指标和通过/失败标准
   - 可以包含推荐的测试用例模板
