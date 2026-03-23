# read_path.md 深度研究文档

## 文件基本信息

| 属性 | 值 |
|------|-----|
| 文件路径 | `codex-rs/core/templates/memories/read_path.md` |
| 文件大小 | 129 行 |
| 文件类型 | Askama 模板 (Markdown) |
| 所属模块 | `codex-core` memories 子系统 |

---

## 一、场景与职责

### 1.1 核心定位

`read_path.md` 是 **Memory Tool 的开发者指令模板**，用于指导主 Agent 如何读取和使用记忆系统。与 `consolidation.md`（指导写入）不同，此模板专注于**读取路径**。

### 1.2 运行时机

- 在主 Agent 启动时注入到 developer instructions
- 当 `memory_summary.md` 存在且非空时启用
- 由 `prompts.rs` 中的 `build_memory_tool_developer_instructions()` 异步构建

### 1.3 设计目标

1. **渐进式记忆访问**：指导 Agent 从一般到具体地访问记忆
2. **防止过度依赖**：明确定义何时应该/不应该使用记忆
3. **轻量级查找**：限制记忆查找的预算（<= 4-6 搜索步骤）
4. **引用规范**：强制要求记忆引用格式，便于追踪和验证

---

## 二、功能点目的

### 2.1 记忆使用决策边界

模板明确定义了使用记忆的决策边界：

**应该跳过记忆的情况：**
- 当前时间/日期查询
- 简单翻译
- 简单句子改写
- 单行 shell 命令
- 简单格式化任务

**应该使用记忆的情况：**
- 查询提及 workspace/repo/module/path/files
- 用户要求先前上下文/一致性/先前决策
- 任务模糊且可能依赖早期项目选择
- 非平凡任务且与 MEMORY_SUMMARY 相关

### 2.2 快速记忆通过 (Quick Memory Pass)

定义了标准化的记忆查找流程：

```
1. 浏览 MEMORY_SUMMARY 提取相关关键词
2. 使用关键词搜索 MEMORY.md
3. 仅在 MEMORY.md 指向时打开 rollout summaries/skills
4. 如需精确命令/错误文本，搜索 rollout_path
5. 如无相关命中，停止记忆查找
```

### 2.3 记忆验证策略

模板提供了验证记忆内容的决策框架：

| 事实类型 | 验证成本 | 建议策略 |
|---------|---------|---------|
| 高漂移风险 + 低成本验证 | 低 | 回答前验证 |
| 高漂移风险 + 高成本验证 | 高 | 可基于记忆回答，但需声明可能过时 |
| 低漂移风险 + 低成本验证 | 低 | 根据重要性判断 |
| 低漂移风险 + 高成本验证 | 高 | 通常可直接基于记忆回答 |

### 2.4 记忆引用规范

强制要求在最终回复末尾添加 `<oai-mem-citation>` 块：

```xml
<oai-mem-citation>
<citation_entries>
MEMORY.md:234-236|note=[responsesapi citation extraction code pointer]
rollout_summaries/2026-02-17T21-23-02-LN3m-weekly_memory_report_pivot_from_git_history.md:10-12|note=[weekly report format]
</citation_entries>
<rollout_ids>
019c6e27-e55b-73d1-87d8-4e01f1f75043
019c7714-3b77-74d1-9866-e1f484aae2ab
</rollout_ids>
</oai-mem-citation>
```

---

## 三、具体技术实现

### 3.1 模板变量

```rust
#[derive(Template)]
#[template(path = "memories/read_path.md", escape = "none")]
struct MemoryToolDeveloperInstructionsTemplate<'a> {
    base_path: &'a str,        // 记忆根目录路径
    memory_summary: &'a str,   // memory_summary.md 内容（已截断）
}
```

### 3.2 构建流程

```rust
pub(crate) async fn build_memory_tool_developer_instructions(
    codex_home: &Path
) -> Option<String> {
    let base_path = memory_root(codex_home);
    let memory_summary_path = base_path.join("memory_summary.md");
    
    // 读取 memory_summary.md
    let memory_summary = fs::read_to_string(&memory_summary_path).await.ok()?;
    
    // 截断至 5,000 tokens
    let memory_summary = truncate_text(
        &memory_summary,
        TruncationPolicy::Tokens(phase_one::MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT),
    );
    
    if memory_summary.is_empty() {
        return None;
    }
    
    // 渲染模板
    let template = MemoryToolDeveloperInstructionsTemplate {
        base_path: &base_path.display().to_string(),
        memory_summary: &memory_summary,
    };
    template.render().ok()
}
```

### 3.3 截断策略

- **截断限制**：`MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT = 5_000` tokens
- **截断位置**：`memory_summary.md` 文件末尾
- **空内容处理**：如果截断后为空，返回 `None`（不注入记忆指令）

### 3.4 记忆布局层级

模板定义了从一般到具体的记忆访问层级：

```
{{ base_path }}/memory_summary.md  (已提供，不再打开)
    ↓
{{ base_path }}/MEMORY.md  (主要查询文件)
    ↓
{{ base_path }}/skills/<skill-name>/  (技能目录)
    ├── SKILL.md  (入口点)
    ├── scripts/  (可选辅助脚本)
    ├── examples/  (可选示例输出)
    └── templates/  (可选模板)
    ↓
{{ base_path }}/rollout_summaries/  (每个 rollout 的摘要)
```

### 3.5 rollout_summaries 文件格式

模板说明了 rollout 摘要文件的格式：

```jsonl
{
  "session_meta": {"payload": {"id": "<rollout_id>"}},
  "turn_context": {...},  // 标记轮次边界
  "event_msg": {...},      // 轻量级状态流
  "response_item": {...}   // 实际消息、tool 调用和输出
}
```

---

## 四、关键代码路径与文件引用

### 4.1 调用链

```
Session 启动
    ↓
build_memory_tool_developer_instructions() [prompts.rs:158]
    ↓
MemoryToolDeveloperInstructionsTemplate.render() [prompts.rs:31]
    ↓ (renders)
read_path.md (this file)
    ↓
注入到 BaseInstructions.text (作为 developer instructions 的一部分)
```

### 4.2 关键文件引用

| 文件 | 角色 |
|------|------|
| `codex-rs/core/src/memories/prompts.rs` | 模板定义和渲染函数 |
| `codex-rs/core/src/memories/mod.rs` | 定义 `MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT` |
| `codex-rs/core/src/truncate.rs` | 文本截断逻辑 |

### 4.3 配置常量

```rust
// phase_one 常量 [memories/mod.rs:47]
const MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT: usize = 5_000;
```

---

## 五、依赖与外部交互

### 5.1 输入依赖

| 输入 | 来源 | 用途 |
|------|------|------|
| `memory_summary.md` | Phase 2 输出 | 注入到模板中作为上下文 |
| `memory_root` 路径 | 配置 | 构建文件路径引用 |

### 5.2 输出消费

| 输出 | 消费者 | 用途 |
|------|--------|------|
| 渲染后的开发者指令 | 主 Agent | 指导记忆读取行为 |

### 5.3 与 Memory Tool 的关系

`read_path.md` 与 Memory Tool 紧密配合：

1. Memory Tool 提供文件系统访问能力
2. `read_path.md` 提供使用这些文件的策略和指导
3. 两者共同实现"记忆增强"功能

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **截断信息丢失** | 5,000 token 限制可能截断重要信息 | 保持 `memory_summary.md` 简洁；优先保留 `User preferences` 和 `General Tips` |
| **过时记忆** | 基于旧记忆的回答可能不准确 | 模板要求声明记忆来源和可能过时性 |
| **过度依赖** | Agent 可能过度依赖记忆而忽略新信息 | 明确的决策边界指导何时跳过记忆 |
| **引用格式错误** | 错误的引用格式导致解析失败 | 严格的 `<oai-mem-citation>` 格式规范 |

### 6.2 边界条件

1. **空记忆文件**：如果 `memory_summary.md` 为空或不存在，不注入任何记忆指令
2. **纯截断内容**：如果截断后内容为空，返回 `None`
3. **并发访问**：多个 Agent 实例可能同时读取记忆文件，但写入由 Phase 2 串行控制

### 6.3 改进建议

1. **分层截断策略**：
   - 优先保留 `## User preferences` 和 `## General Tips`
   - 其次保留 `## User Profile`
   - 最后保留 `## What's in Memory`

2. **动态预算调整**：
   - 根据模型上下文窗口动态调整 5,000 token 限制
   - 对于大上下文模型，可增加预算

3. **记忆新鲜度指示**：
   - 在模板中添加记忆年龄信息
   - 帮助 Agent 判断记忆的可靠性

4. **引用验证**：
   - 添加引用格式验证逻辑
   - 确保引用的行号范围有效

5. **记忆使用统计**：
   - 跟踪哪些记忆被频繁引用
   - 用于优化记忆保留策略

---

## 七、模板内容结构速览

```
read_path.md (129 lines)
├── Header: Memory
├── 使用决策边界
│   ├── Skip memory 的情况
│   └── Use memory 的情况
├── 记忆布局层级
│   ├── memory_summary.md
│   ├── MEMORY.md
│   ├── skills/
│   └── rollout_summaries/
├── 快速记忆通过流程
│   ├── 5 步查找流程
│   └── 预算限制 (<= 4-6 steps)
├── 记忆验证策略
│   ├── 风险 vs 成本矩阵
│   └── 回答时的声明要求
└── 记忆引用规范
    ├── <oai-mem-citation> 格式
    ├── citation_entries 格式
    └── rollout_ids 格式
```

---

## 八、与相关模板的关系

```
┌─────────────────────────────────────────────────────────────┐
│                     Memories Pipeline                        │
├─────────────────────────────────────────────────────────────┤
│  Phase 1 (Extraction)          Phase 2 (Consolidation)      │
│  ┌─────────────────────┐       ┌─────────────────────┐      │
│  │ stage_one_system.md │──────→│ consolidation.md    │      │
│  │ stage_one_input.md  │       │ (写入指导)           │      │
│  └─────────────────────┘       └─────────────────────┘      │
│                                          │                   │
│                                          ↓                   │
│                               ┌─────────────────────┐       │
│                               │ memory_summary.md   │       │
│                               │ MEMORY.md           │       │
│                               └─────────────────────┘       │
│                                          │                   │
│                                          ↓                   │
│                               ┌─────────────────────┐       │
│                               │ read_path.md        │       │
│                               │ (读取指导)           │       │
│                               └─────────────────────┘       │
│                                          │                   │
│                                          ↓                   │
│                               ┌─────────────────────┐       │
│                               │ 主 Agent (运行时)    │       │
│                               └─────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## 九、测试相关

### 9.1 相关测试文件

| 测试文件 | 覆盖内容 |
|---------|---------|
| `codex-rs/core/tests/suite/memories.rs` | 端到端记忆流程测试 |
| `codex-rs/core/src/memories/prompts_tests.rs` | 模板渲染测试 |

### 9.2 测试要点

1. **截断逻辑测试**：验证大 `memory_summary.md` 正确截断
2. **空文件处理**：验证空文件返回 `None`
3. **模板渲染**：验证变量正确替换
