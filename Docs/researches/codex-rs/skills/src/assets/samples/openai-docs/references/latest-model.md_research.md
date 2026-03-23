# latest-model.md 研究文档

## 场景与职责

本文件是 OpenAI Docs Skill 的参考文档之一，专门用于回答用户关于"最佳/最新/当前模型"选择的问题。它属于 `codex-rs/skills` crate 中嵌入的系统 Skill 资源文件，在构建时通过 `include_dir` 嵌入到二进制中，运行时解压到用户目录的 `CODEX_HOME/skills/.system/` 路径下。

主要职责包括：
1. 提供当前 OpenAI 模型 ID 到使用场景的映射表
2. 作为模型选择决策的快速参考指南
3. 帮助用户根据具体需求选择最合适的模型

## 功能点目的

### 1. 当前模型映射表（Current model map）

提供一个简洁的表格，将模型 ID 映射到推荐使用场景：

| 模型 ID | 使用场景 |
|---------|---------|
| `gpt-5.4` | 大多数新应用的默认文本+推理 |
| `gpt-5.4-pro` | 仅在用户明确要求最大推理或质量时；明显更慢更贵 |
| `gpt-5-mini` | 更便宜更快的推理，质量良好 |
| `gpt-5-nano` | 高吞吐量简单任务和分类 |
| `gpt-5.4` | 通过 `reasoning.effort: none` 的显式无推理文本路径 |
| `gpt-4.1-mini` | 更便宜的无推理文本 |
| `gpt-4.1-nano` | 最快最便宜的无推理文本 |
| `gpt-5.3-codex` | Agentic 编码、代码编辑和工具密集型编码工作流 |
| `gpt-5.1-codex-mini` | 更便宜的编码工作流 |
| `gpt-image-1.5` | 最佳图像生成和编辑质量 |
| `gpt-image-1-mini` | 成本优化的图像生成 |
| `gpt-4o-mini-tts` | 文本转语音 |
| `gpt-4o-mini-transcribe` | 语音转文本，快速且成本高效 |
| `gpt-realtime-1.5` | 实时语音和多模态会话 |
| `gpt-realtime-mini` | 更便宜的实时会话 |
| `gpt-audio` | Chat Completions 音频输入和输出 |
| `gpt-audio-mini` | 更便宜的 Chat Completions 音频工作流 |
| `sora-2` | 更快的迭代和草稿视频生成 |
| `sora-2-pro` | 更高质量的生产视频 |
| `omni-moderation-latest` | 文本和图像审核 |
| `text-embedding-3-large` | 更高质量的检索嵌入；默认选择（因为没有最佳特定行） |
| `text-embedding-3-small` | 更低成本的嵌入 |

### 2. 维护说明（Maintenance notes）

明确文档的局限性：
- 文件会随时间漂移，除非定期与当前 OpenAI 文档重新验证
- 如果文件与当前文档冲突，以文档为准

## 具体技术实现

### 文档结构

本文档采用 Markdown 格式，包含以下结构：

```markdown
# 标题和免责声明
## 当前模型映射（表格）
## 维护说明
```

### 表格格式

使用标准 Markdown 表格：
- 第一列：模型 ID（带反引号的代码格式）
- 第二列：使用场景描述
- 表头：Model ID | Use for

### 模型分类逻辑

文档按照功能领域对模型进行隐式分类：

1. **文本+推理模型**（GPT-5.4 系列）
   - gpt-5.4（默认）
   - gpt-5.4-pro（最大质量）
   - gpt-5-mini（成本优化）
   - gpt-5-nano（高吞吐量）

2. **无推理文本模型**（GPT-4.1 系列）
   - gpt-4.1-mini
   - gpt-4.1-nano

3. **编码专用模型**（Codex 系列）
   - gpt-5.3-codex
   - gpt-5.1-codex-mini

4. **图像生成模型**
   - gpt-image-1.5
   - gpt-image-1-mini

5. **音频模型**
   - gpt-4o-mini-tts
   - gpt-4o-mini-transcribe
   - gpt-realtime-1.5
   - gpt-realtime-mini
   - gpt-audio
   - gpt-audio-mini

6. **视频模型**
   - sora-2
   - sora-2-pro

7. **审核和嵌入模型**
   - omni-moderation-latest
   - text-embedding-3-large
   - text-embedding-3-small

## 关键代码路径与文件引用

### 当前文件

- **路径**: `codex-rs/skills/src/assets/samples/openai-docs/references/latest-model.md`
- **大小**: 1,844 bytes
- **格式**: Markdown

### 相关文件

| 文件路径 | 关系 | 说明 |
|---------|------|------|
| `codex-rs/skills/src/assets/samples/openai-docs/SKILL.md` | 父 Skill 定义 | 定义何时加载本参考文档 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/upgrading-to-gpt-5p4.md` | 配套文档 | 升级流程指导 |
| `codex-rs/skills/src/assets/samples/openai-docs/references/gpt-5p4-prompting-guide.md` | 配套文档 | Prompt 升级指导 |
| `codex-rs/skills/src/lib.rs` | 加载实现 | 系统 Skill 的安装和加载逻辑 |
| `codex-rs/skills/build.rs` | 构建脚本 | 监控资源文件变更 |

### 加载触发条件

根据 `SKILL.md` 中的定义，本文件在以下情况被加载：

```markdown
2. If it is a model-selection request, load `references/latest-model.md`.
```

即：当用户请求涉及模型选择或询问"最佳/最新/当前模型"问题时。

## 依赖与外部交互

### 内部依赖

1. **OpenAI Docs Skill 框架**
   - 依赖 `SKILL.md` 中定义的工作流来触发加载
   - 与 `upgrading-to-gpt-5p4.md` 和 `gpt-5p4-prompting-guide.md` 形成完整的模型指导体系

2. **codex-skills crate**
   - 提供系统 Skill 的安装和管理基础设施
   - 通过 `SYSTEM_SKILLS_DIR` 常量嵌入本文件

### 外部依赖

1. **OpenAI 官方文档**
   - 文档明确声明："Every recommendation here must be verified against current OpenAI docs before it is repeated to a user"
   - 所有建议必须在向用户重复之前与当前 OpenAI 文档进行验证

2. **MCP Server**
   - Skill 优先使用 `openaiDeveloperDocs` MCP 工具获取最新信息
   - 本文件仅作为辅助上下文，不能替代 MCP 工具返回的权威信息

### 交互流程

```
用户询问模型选择/最佳模型/最新模型
    ↓
OpenAI Docs Skill 加载 SKILL.md
    ↓
识别为模型选择请求
    ↓
加载 references/latest-model.md
    ↓
使用 MCP 工具验证建议的准确性
    ↓
结合 MCP 结果和参考文件生成回答
    ↓
向用户提供带引用的模型推荐
```

## 风险、边界与改进建议

### 风险

1. **文档快速过时风险**
   - OpenAI 模型发布频率较高，模型 ID 和推荐可能快速变化
   - 文件明确警告会"drift"（漂移）
   - 如果用户基于过时信息做出决策，可能导致次优选择

2. **过度简化风险**
   - 表格形式简洁但可能过度简化复杂的选择场景
   - 某些边缘用例可能无法被简单分类覆盖
   - 用户可能忽略 MCP 验证步骤直接应用建议

3. **重复条目问题**
   - `gpt-5.4` 在表格中出现两次（第 1 行和第 5 行）
   - 第 5 行描述为"通过 `reasoning.effort: none` 的显式无推理文本路径"
   - 这可能造成混淆，用户不清楚应该使用哪个条目

### 边界

1. **权威性边界**
   - 文档明确声明 OpenAI 官方文档是真理来源
   - 本文件仅为便利指南，不能替代官方文档
   - 必须在向用户重复之前验证每条建议

2. **信息深度边界**
   - 仅提供模型 ID 和使用场景的一行描述
   - 不包含定价、性能基准、上下文长度等技术细节
   - 不包含具体的 API 调用示例

3. **时效性边界**
   - 文档反映的是特定时间点的模型状态
   - 新模型发布后文档可能滞后更新

### 改进建议

1. **添加时间戳**
   - 在文档中添加最后更新日期或版本号
   - 帮助用户判断信息的时效性

2. **去重和澄清**
   - 修复 `gpt-5.4` 重复出现的问题
   - 可以合并为一个条目，说明支持 reasoning effort 配置
   - 或者明确区分两个使用场景

3. **添加更多上下文**
   - 考虑添加模型选择决策树或流程图
   - 帮助用户根据具体需求导航到合适的模型

4. **与 MCP 的深度集成**
   - 考虑添加 MCP 工具调用示例，展示如何验证建议
   - 可以添加指向特定 OpenAI 文档页面的链接

5. **分类标题**
   - 为表格添加分类标题或分隔，提高可读性
   - 例如："推理模型"、"无推理模型"、"多模态模型"等

6. **扩展信息**
   - 考虑添加关键参数列（如上下文长度、知识截止日期）
   - 帮助用户做出更全面的决策

7. **自动化同步**
   - 建议建立自动化流程，定期从 OpenAI 文档同步模型信息
   - 减少手动维护负担和过时风险
