# gpt-5p4-prompting-guide.md 研究文档

## 场景与职责

本文件是 OpenAI Docs Skill 的参考文档之一，专门用于指导用户如何将针对旧版模型（如 GPT-4o、GPT-4.1、GPT-5.2、GPT-5.3-Codex 等）编写的 Prompt 迁移到 GPT-5.4 模型。它属于 `codex-rs/skills` crate 中嵌入的系统 Skill 资源文件，在构建时通过 `include_dir` 嵌入到二进制中，运行时解压到用户目录的 `CODEX_HOME/skills/.system/` 路径下。

主要职责包括：
1. 提供 GPT-5.4 升级时的 Prompt 重写策略和模式
2. 定义一系列可复用的 Prompt 代码块（prompt blocks），用于解决特定场景下的行为回归问题
3. 针对不同源模型家族（GPT-4o、GPT-5.2、GPT-5.3-Codex 等）提供具体的升级配置建议
4. 指导如何在不修改代码的情况下，仅通过调整 Prompt 实现模型升级

## 功能点目的

### 1. 默认升级姿态（Default upgrade posture）

定义了升级时的基本原则：
- **最小化变更**：优先仅替换模型字符串，保持 Prompt 不变
- **渐进式优化**：仅在出现回归时才添加轻量级 Prompt 修改
- **推理力度作为最后手段**：优先通过 Prompt 修复，而非直接提高 reasoning effort
- **区分阻塞场景**：仅当需要修改工具定义、连接或实现细节时才标记为阻塞

### 2. 行为差异指导（Behavioral differences）

总结了 GPT-5.4 的核心优势：
- 更强的个性和语气一致性
- 更好的长程和 Agentic 工作流耐力
- 更强的电子表格、财务和格式化任务处理能力
- 更高效的工具选择，减少不必要的调用
- 更强的结构化生成和分类可靠性

同时指出需要 Prompt 干预的场景：
- 检索密集型工作流需要持久化工具使用和显式完整性检查
- 研究和引用规范
- 不可逆或高影响操作前的验证
- 终端和工具工作流卫生
- 默认行为和隐式后续执行
- 输出简洁性控制

### 3. Prompt 重写模式表

提供了从旧 Prompt 模式到 GPT-5.4 调整的映射表，包含：

| 旧 Prompt 模式 | GPT-5.4 调整 | 原因 | 示例添加 |
|--------------|-------------|------|---------|
| 长重复指令 | 移除重复脚手架 | GPT-5.4 需要更少的重复引导 | 用简洁规则+验证块替代重复提醒 |
| 快速助手 Prompt 无冗长控制 | 先保持原样，必要时添加 verbosity clamp | 许多 GPT-4o/4.1 升级只需模型字符串替换 | 仅在冗长回归后添加 `output_verbosity_spec` |
| 工具密集型 Agent Prompt | 添加持久化和验证规则 | GPT-5.4 默认使用更少工具调用 | 添加 `tool_persistence_rules` 和 `verification_loop` |
| 依赖前置查找的工具工作流 | 添加前置条件和缺失上下文规则 | 上下文稀疏时需要显式依赖感知路由 | 添加 `dependency_checks` 和 `missing_context_gating` |
| 多个独立查找的检索工作流 | 添加选择性并行指导 | GPT-5.4 擅长并行工具使用，但不应并行化依赖步骤 | 添加 `parallel_tool_calling` |
| 经常遗漏项目的批处理工作流 | 添加显式完整性契约 | 项目计数需要直接指令 | 添加 `completeness_contract` |
| 需要引用规范的研究 Prompt | 添加研究、引用和空结果恢复块 | 多轮检索在被告知如何处理弱/空搜索结果时更强 | 添加 `research_mode`、`citation_rules`、`empty_result_handling` |
| 编码或终端 Prompt | 添加终端卫生和验证指令 | 工具使用编码工作流通常需要更好的 Prompt 引导 | 添加 `terminal_tool_hygiene` 和 `verification_loop` |
| 多 Agent 或支持分类工作流 | 添加轻量级控制块 | GPT-5.4 默认更高效，多步流程需要显式完成或验证契约 | 添加 `tool_persistence_rules`、`completeness_contract` 或 `verification_loop` |

### 4. Prompt 代码块（Prompt Blocks）

定义了 18 个可复用的 Prompt 代码块，每个包含：

- **使用场景**：明确何时使用该代码块
- **XML 标签包裹的文本内容**：可直接嵌入到系统 Prompt 中

具体代码块列表：

1. **`output_verbosity_spec`**：控制输出长度，默认 3-6 句话或最多 6 个要点
2. **`default_follow_through_policy`**：定义在可逆低风险步骤上的默认执行策略
3. **`instruction_priority`**：处理用户中途更改任务形状、格式或语气的情况
4. **`tool_persistence_rules`**：确保模型不会为了节省工具调用而过早停止
5. **`dig_deeper_nudge`**：鼓励模型不满足于第一个看似合理的答案
6. **`dependency_checks`**：确保在执行操作前检查前置条件
7. **`parallel_tool_calling`**：指导何时并行化独立检索步骤
8. **`completeness_contract`**：确保批次、列表、枚举或多交付物任务的完整性
9. **`empty_result_handling`**：处理查找返回空或可疑少量结果的情况
10. **`verification_loop`**：在最终确定前检查正确性、依据、格式和安全性
11. **`missing_context_gating`**：在缺少所需上下文时优先查找而非猜测
12. **`action_safety`**：为通过工具主动执行的操作提供飞行前和飞行后框架
13. **`citation_rules`**：确保引用规范，禁止伪造引用
14. **`research_mode`**：定义 3 轮研究流程（计划→检索→综合）
15. **`structured_output_contract`**：确保严格的 JSON、SQL 或其他结构化输出
16. **`bbox_extraction_spec`**：用于 OCR 框、文档区域或坐标提取
17. **`terminal_tool_hygiene`**：终端或编码 Agent 工作流的工具卫生规范
18. **`user_updates_spec`**：长运行工作流中的用户更新规范

### 5. Responses `phase` 指导

针对长运行的 Responses 工作流、序言或工具密集型 Agent：
- 如果主机已经往返传输 `phase`，在升级期间保持其完整
- 如果主机使用 `previous_response_id` 且不手动重放助手项目，注意这可能减少手动 `phase` 处理需求
- 如果可靠的 GPT-5.4 行为需要添加或保留 `phase` 且需要代码编辑，将该情况标记为阻塞

### 6. 示例升级配置（Example upgrade profiles）

针对不同源模型提供具体的升级建议：

| 源模型/场景 | 目标模型 | 推理力度建议 | 推荐添加的 Prompt 代码块 |
|-----------|---------|-------------|------------------------|
| GPT-5.2 | gpt-5.4 | 匹配当前推理力度 | 先保持相同 |
| GPT-5.3-Codex | gpt-5.4 | 匹配当前推理力度 | 如需 Codex 风格速度，先添加验证块再提高推理力度 |
| GPT-4o 或 GPT-4.1 assistant | gpt-5.4 | none | 仅在输出过于冗长时添加 `output_verbosity_spec` |
| 长程 Agent | gpt-5.4 | medium | `tool_persistence_rules`、`completeness_contract`、`verification_loop` |
| 研究工作流 | gpt-5.4 | medium | `research_mode`、`citation_rules`、`empty_result_handling`、`tool_persistence_rules`、`parallel_tool_calling` |
| 支持分类或多 Agent 工作流 | gpt-5.4 | - | `tool_persistence_rules`、`completeness_contract` 或 `verification_loop` 中至少一个 |
| 编码或终端工作流 | gpt-5.4 | 匹配 GPT-5.3-Codex | `terminal_tool_hygiene`、`verification_loop`、`dependency_checks`、`tool_persistence_rules` |

### 7. Prompt 回归检查清单

验证升级后的 Prompt 是否：
- 保留原始任务意图
- 更精简而非更长
- 检查完整性、引用质量、依赖处理、验证行为和冗长性
- 对于长运行 Responses Agent，检查 `phase` 处理是否已就位或需要实现工作
- 确认每个添加的 Prompt 代码块都解决了观察到的回归问题
- 移除没有发挥作用的 Prompt 代码块

## 具体技术实现

### 文档结构

本文档采用 Markdown 格式，包含以下结构：

```markdown
# 标题和简介
## 默认升级姿态
## 行为差异指导
## Prompt 重写模式（表格）
## Prompt 代码块（多个 XML 格式代码块）
## Responses `phase` 指导
## 示例升级配置（多个场景）
## Prompt 回归检查清单
```

### Prompt 代码块格式

每个 Prompt 代码块遵循统一的 XML 标签格式：

```text
<block_name>
- 规则 1
- 规则 2
  - 子规则 A
  - 子规则 B
- 规则 3
</block_name>
```

这种格式：
- 使用 XML 标签作为代码块标识符，便于 LLM 解析和应用
- 采用简洁的要点列表形式，减少 token 消耗
- 支持嵌套结构表示层级关系

### 与 Skill 系统的集成

1. **嵌入方式**：通过 `include_dir` crate 在编译时将整个 `samples` 目录嵌入二进制
2. **运行时解压**：由 `codex-skills` crate 的 `install_system_skills()` 函数在首次运行时解压到用户目录
3. **指纹验证**：使用目录内容的哈希指纹避免不必要的重复解压
4. **加载机制**：由 OpenAI Docs Skill 根据用户查询类型选择性加载

## 关键代码路径与文件引用

### 当前文件

- **路径**: `codex-rs/skills/src/assets/samples/openai-docs/references/gpt-5p4-prompting-guide.md`
- **大小**: 18,036 bytes
- **格式**: Markdown

### 相关文件

| 文件路径 | 关系 | 说明 |
|---------|------|------|
| `codex-rs/skills/src/assets/samples/openai-docs/SKILL.md` | 父 Skill 定义 | 定义何时加载本参考文档 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/upgrading-to-gpt-5p4.md` | 配套文档 | 升级流程和兼容性检查 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/latest-model.md` | 配套文档 | 模型选择参考 |
| `codex-rs/skills/src/lib.rs` | 加载实现 | 系统 Skill 的安装和加载逻辑 |
| `codex-rs/skills/build.rs` | 构建脚本 | 监控资源文件变更 |
| `codex-rs/skills/Cargo.toml` | 包配置 | 定义 `include_dir` 依赖 |

### 加载触发条件

根据 `SKILL.md` 中的定义，本文件在以下情况被加载：

```markdown
4. If the upgrade may require prompt changes, or the workflow is research-heavy, tool-heavy, coding-oriented, multi-agent, or long-running, also load `references/gpt-5p4-prompting-guide.md`.
```

即：当升级可能需要 Prompt 变更，或工作流具有以下特征时：
- 研究密集型（research-heavy）
- 工具密集型（tool-heavy）
- 编码导向（coding-oriented）
- 多 Agent（multi-agent）
- 长运行（long-running）

## 依赖与外部交互

### 内部依赖

1. **OpenAI Docs Skill 框架**
   - 依赖 `SKILL.md` 中定义的工作流来触发加载
   - 与 `upgrading-to-gpt-5p4.md` 和 `latest-model.md` 形成完整的升级指导体系

2. **codex-skills crate**
   - 提供系统 Skill 的安装和管理基础设施
   - 通过 `SYSTEM_SKILLS_DIR` 常量嵌入本文件

### 外部依赖

1. **OpenAI 官方文档**
   - 文档明确声明：所有建议必须在向用户重复之前与当前 OpenAI 文档进行验证
   - 如果文件与当前文档冲突，以文档为准

2. **MCP Server**
   - Skill 优先使用 `openaiDeveloperDocs` MCP 工具获取最新信息
   - 本文件仅作为辅助上下文，不能替代 MCP 工具返回的权威信息

3. **GPT-5.4 模型行为**
   - 文档基于 GPT-5.4 的特定行为特征编写
   - 如果模型行为在后续版本中发生变化，文档可能需要更新

### 交互流程

```
用户询问 GPT-5.4 升级/Prompt 优化
    ↓
OpenAI Docs Skill 加载 SKILL.md
    ↓
根据工作流类型判断加载哪些参考文件
    ↓
加载 gpt-5p4-prompting-guide.md（如需要）
    ↓
使用 MCP 工具验证建议的准确性
    ↓
结合 MCP 结果和参考文件生成回答
    ↓
向用户提供带引用的指导
```

## 风险、边界与改进建议

### 风险

1. **文档漂移风险（Document Drift）**
   - 文件明确警告："This file will drift unless it is periodically re-verified against current OpenAI docs"
   - GPT-5.4 的行为可能在发布候选版和最终版之间发生变化
   - 建议可能随时间变得过时或不准确

2. **过度应用风险**
   - 文档包含 18 个 Prompt 代码块，用户可能倾向于全部应用
   - 文档反复强调："Use these selectively. Do not add all of them by default"
   - 过度应用可能导致 Prompt 过长、成本增加、性能下降

3. **阻塞判断错误风险**
   - 区分 `model string only`、`model string + light prompt rewrite` 和 `blocked` 需要准确判断
   - 错误的分类可能导致不必要的代码修改或遗漏必要的实现变更

4. **Phase 处理复杂性**
   - 对于长运行 Responses Agent，`phase` 的处理是一个复杂的技术细节
   - 文档指出如果需要代码编辑来添加/保留 `phase`，应标记为阻塞
   - 这可能被误解或忽视

### 边界

1. **适用范围边界**
   - 仅适用于 Prompt 级别的升级指导
   - 不涵盖需要 API 表面变更、参数重写、工具重新连接的情况
   - 不处理需要添加或改造 `phase` 处理的实现代码编辑

2. **权威性边界**
   - 文档明确声明 OpenAI 官方文档是真理来源
   - 本文件仅为便利指南，不能替代官方文档

3. **模型版本边界**
   - 针对 GPT-5.4 特定版本编写
   - 可能不适用于未来模型版本

### 改进建议

1. **自动化验证机制**
   - 建议添加自动化测试或 CI 流程，定期验证文档中的建议是否与最新 OpenAI 文档一致
   - 可以添加版本标记，明确文档最后验证日期

2. **Prompt 代码块交互式选择器**
   - 考虑开发交互式工具，根据用户描述的工作流特征推荐应使用的 Prompt 代码块
   - 减少用户过度应用所有代码块的风险

3. **案例库扩展**
   - 当前文档提供了升级配置建议，但缺少具体的 before/after 案例
   - 建议添加更多真实场景的 Prompt 重写示例

4. **与 MCP 工具的深度集成**
   - 考虑让 MCP 工具能够直接引用本文件中的特定代码块
   - 实现文档建议与实际 API 行为的自动对齐验证

5. **版本化策略**
   - 考虑为文档添加版本号，与 GPT-5.4 的模型版本对应
   - 在模型更新时同步更新文档，并保留历史版本供参考

6. **中文本地化**
   - 当前文档为英文，对于中文用户可能需要本地化版本
   - 注意 Prompt 代码块本身应保持英文以确保模型理解
