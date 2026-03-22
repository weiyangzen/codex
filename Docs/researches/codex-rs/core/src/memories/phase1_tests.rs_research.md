# phase1_tests.rs - 研究文档

## 场景与职责

`phase1_tests.rs` 是 `phase1.rs` 模块的单元测试文件，负责验证 Phase 1 记忆提取功能的正确性。

### 测试覆盖范围

1. **内容过滤**: 验证 rollout 内容的正确过滤和序列化
2. **统计聚合**: 验证作业结果的统计计算
3. **Token 使用**: 验证跨作业的 token 使用聚合

## 功能点目的

### 测试用例设计

| 测试函数 | 目的 |
|----------|------|
| `serializes_memory_rollout_with_agents_removed_but_environment_kept` | 验证内容过滤逻辑 |
| `count_outcomes_sums_token_usage_across_all_jobs` | 验证 token 使用聚合 |
| `count_outcomes_keeps_usage_empty_when_no_job_reports_it` | 验证空 token 使用处理 |

## 具体技术实现

### 测试 1: 内容过滤

```rust
#[test]
fn serializes_memory_rollout_with_agents_removed_but_environment_kept() {
    // 构建混合上下文消息（包含 AGENTS.md 指令和环境上下文）
    let mixed_contextual_message = ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![
            ContentItem::InputText {
                text: "# AGENTS.md instructions for /tmp\n\n<INSTRUCTIONS>\nbody\n</INSTRUCTIONS>"
                    .to_string(),
            },
            ContentItem::InputText {
                text: "<environment_context>\n<cwd>/tmp</cwd>\n</environment_context>".to_string(),
            },
        ],
        end_turn: None,
        phase: None,
    };
    
    // 技能消息
    let skill_message = ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::InputText {
            text: "<skill>\n<name>demo</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>"
                .to_string(),
        }],
        end_turn: None,
        phase: None,
    };
    
    // 子代理通知消息
    let subagent_message = ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::InputText {
            text: "<subagent_notification>{\"agent_id\":\"a\",\"status\":\"completed\"}</subagent_notification>"
                .to_string(),
        }],
        end_turn: None,
        phase: None,
    };

    // 执行序列化
    let serialized = serialize_filtered_rollout_response_items(&[
        RolloutItem::ResponseItem(mixed_contextual_message),
        RolloutItem::ResponseItem(skill_message),
        RolloutItem::ResponseItem(subagent_message.clone()),
    ]).expect("serialize");
    
    let parsed: Vec<ResponseItem> = serde_json::from_str(&serialized).expect("parse");

    // 验证：AGENTS.md 指令被移除，环境上下文被保留
    // 技能消息被移除，子代理通知被保留
    assert_eq!(
        parsed,
        vec![
            ResponseItem::Message {
                id: None,
                role: "user".to_string(),
                content: vec![ContentItem::InputText {
                    text: "<environment_context>\n<cwd>/tmp</cwd>\n</environment_context>"
                        .to_string(),
                }],
                end_turn: None,
                phase: None,
            },
            subagent_message,
        ]
    );
}
```

**验证点**:
- AGENTS.md 指令被正确过滤
- 环境上下文被保留
- 技能消息被过滤
- 子代理通知被保留

### 测试 2: Token 使用聚合

```rust
#[test]
fn count_outcomes_sums_token_usage_across_all_jobs() {
    let counts = aggregate_stats(vec![
        JobResult {
            outcome: JobOutcome::SucceededWithOutput,
            token_usage: Some(TokenUsage {
                input_tokens: 10,
                cached_input_tokens: 2,
                output_tokens: 3,
                reasoning_output_tokens: 1,
                total_tokens: 13,
            }),
        },
        JobResult {
            outcome: JobOutcome::SucceededNoOutput,
            token_usage: Some(TokenUsage {
                input_tokens: 7,
                cached_input_tokens: 1,
                output_tokens: 2,
                reasoning_output_tokens: 0,
                total_tokens: 9,
            }),
        },
        JobResult {
            outcome: JobOutcome::Failed,
            token_usage: None,
        },
    ]);

    assert_eq!(counts.claimed, 3);
    assert_eq!(counts.succeeded_with_output, 1);
    assert_eq!(counts.succeeded_no_output, 1);
    assert_eq!(counts.failed, 1);
    assert_eq!(
        counts.total_token_usage,
        Some(TokenUsage {
            input_tokens: 17,           // 10 + 7
            cached_input_tokens: 3,     // 2 + 1
            output_tokens: 5,           // 3 + 2
            reasoning_output_tokens: 1, // 1 + 0
            total_tokens: 22,           // 13 + 9
        })
    );
}
```

**验证点**:
- 作业计数正确
- Token 使用正确累加
- 失败作业（无 token 使用）被正确处理

### 测试 3: 空 Token 使用处理

```rust
#[test]
fn count_outcomes_keeps_usage_empty_when_no_job_reports_it() {
    let counts = aggregate_stats(vec![
        JobResult {
            outcome: JobOutcome::SucceededWithOutput,
            token_usage: None,
        },
        JobResult {
            outcome: JobOutcome::Failed,
            token_usage: None,
        },
    ]);

    assert_eq!(counts.claimed, 2);
    assert_eq!(counts.total_token_usage, None);  // 保持为 None
}
```

**验证点**:
- 当没有作业报告 token 使用时，结果为 None
- 作业计数仍然正确

## 关键代码路径与文件引用

### 测试结构

```
phase1_tests.rs
├── 导入被测函数和类型
├── 测试 1: serializes_memory_rollout_with_agents_removed_but_environment_kept (行 12-73)
├── 测试 2: count_outcomes_sums_token_usage_across_all_jobs (行 75-118)
└── 测试 3: count_outcomes_keeps_usage_empty_when_no_job_reports_it (行 120-135)
```

### 依赖

| 依赖 | 用途 |
|------|------|
| `super::JobOutcome` | 作业结果类型 |
| `super::JobResult` | 作业结果结构 |
| `super::aggregate_stats` | 被测函数 |
| `super::job::serialize_filtered_rollout_response_items` | 被测函数 |
| `codex_protocol::models::ContentItem` | 测试数据 |
| `codex_protocol::models::ResponseItem` | 测试数据 |
| `codex_protocol::protocol::RolloutItem` | 测试数据 |
| `codex_protocol::protocol::TokenUsage` | 测试数据 |
| `pretty_assertions::assert_eq` | 清晰的测试失败输出 |

## 依赖与外部交互

### 测试框架

- 使用标准 Rust 测试框架 (`#[test]`)
- 使用 `pretty_assertions` 提供清晰的 diff 输出

### 测试数据

- 手动构建 `ResponseItem` 和 `ContentItem` 结构
- 使用具体的消息内容测试过滤逻辑

## 风险、边界与改进建议

### 当前覆盖缺口

1. **模型调用**:
   - 没有测试实际的模型调用逻辑
   - `job::sample` 函数未覆盖

2. **数据库交互**:
   - 没有测试作业声明和状态更新
   - `claim_startup_jobs` 未覆盖

3. **错误处理**:
   - 没有测试失败路径
   - 没有测试重试逻辑

4. **内容过滤边界**:
   - 没有测试空内容
   - 没有测试超大内容
   - 没有测试特殊字符

5. **提示构建**:
   - 没有测试 `build_stage_one_input_message`
   - 没有测试 token 限制截断

### 改进建议

1. **添加模型调用模拟测试**:
```rust
#[tokio::test]
async fn sample_parses_model_output_correctly() {
    // 使用 mock 模型客户端
    // 验证输出解析和 secrets 编辑
}
```

2. **添加数据库集成测试**:
```rust
#[tokio::test]
async fn claim_startup_jobs_filters_by_age() {
    // 使用临时数据库
    // 验证年龄过滤逻辑
}
```

3. **添加错误路径测试**:
```rust
#[test]
fn aggregate_stats_handles_mixed_outcomes() {
    // 测试各种结果组合
}
```

4. **添加边界测试**:
```rust
#[test]
fn serialize_handles_empty_rollout() {
    let serialized = serialize_filtered_rollout_response_items(&[]);
    assert_eq!(serialized, "[]");
}
```

5. **添加性能测试**:
   - 测试大 rollout 的处理性能
   - 测试并发作业的性能

6. **使用属性测试**:
   - 使用 `proptest` 生成随机 rollout 内容
   - 验证过滤逻辑的不变性
