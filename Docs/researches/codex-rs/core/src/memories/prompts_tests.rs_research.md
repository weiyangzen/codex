# prompts_tests.rs - 研究文档

## 场景与职责

`prompts_tests.rs` 是 `prompts.rs` 模块的单元测试文件，负责验证提示构建功能的正确性。

### 测试覆盖范围

1. **Token 限制计算**: 验证基于模型上下文窗口的 token 限制计算
2. **默认限制回退**: 验证当模型上下文窗口缺失时的默认限制
3. **内容截断**: 验证大 rollout 内容的正确截断

## 功能点目的

### 测试用例设计

| 测试函数 | 目的 |
|----------|------|
| `build_stage_one_input_message_truncates_rollout_using_model_context_window` | 验证基于模型上下文窗口的截断 |
| `build_stage_one_input_message_uses_default_limit_when_model_context_window_missing` | 验证默认限制回退 |

## 具体技术实现

### 测试 1: 基于模型上下文窗口的截断

```rust
#[test]
fn build_stage_one_input_message_truncates_rollout_using_model_context_window() {
    // 构建超大输入（140万字符）
    let input = format!("{}{}{}", "a".repeat(700_000), "middle", "z".repeat(700_000));
    
    // 配置模型信息
    let mut model_info = model_info_from_slug("gpt-5.2-codex");
    model_info.context_window = Some(123_000);
    
    // 计算期望的 token 限制
    // limit = 123_000 * effective_context_window_percent / 100 * CONTEXT_WINDOW_PERCENT / 100
    let expected_rollout_token_limit = usize::try_from(
        ((123_000_i64 * model_info.effective_context_window_percent) / 100)
            * phase_one::CONTEXT_WINDOW_PERCENT
            / 100,
    ).unwrap();
    
    // 计算期望的截断结果
    let expected_truncated = truncate_text(
        &input,
        TruncationPolicy::Tokens(expected_rollout_token_limit),
    );

    // 构建消息
    let message = build_stage_one_input_message(
        &model_info,
        Path::new("/tmp/rollout.jsonl"),
        Path::new("/tmp"),
        &input,
    ).unwrap();

    // 验证截断特征
    assert!(expected_truncated.contains("tokens truncated"));  // 包含截断标记
    assert!(expected_truncated.starts_with('a'));              // 保留头部
    assert!(expected_truncated.ends_with('z'));                // 保留尾部
    assert!(message.contains(&expected_truncated));            // 消息包含截断内容
}
```

**验证点**:
- 根据模型上下文窗口正确计算 token 限制
- 超大内容被正确截断
- 截断保留头部和尾部（中间截断）
- 截断标记被添加

### 测试 2: 默认限制回退

```rust
#[test]
fn build_stage_one_input_message_uses_default_limit_when_model_context_window_missing() {
    // 构建超大输入
    let input = format!("{}{}{}", "a".repeat(700_000), "middle", "z".repeat(700_000));
    
    // 配置模型信息（无上下文窗口）
    let mut model_info = model_info_from_slug("gpt-5.2-codex");
    model_info.context_window = None;
    
    // 计算期望的截断结果（使用默认限制）
    let expected_truncated = truncate_text(
        &input,
        TruncationPolicy::Tokens(phase_one::DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT),
    );

    // 构建消息
    let message = build_stage_one_input_message(
        &model_info,
        Path::new("/tmp/rollout.jsonl"),
        Path::new("/tmp"),
        &input,
    ).unwrap();

    // 验证使用默认限制
    assert!(message.contains(&expected_truncated));
}
```

**验证点**:
- 当 `context_window` 为 None 时使用默认限制
- 默认限制值为 `DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT` (150,000)

## 关键代码路径与文件引用

### 测试结构

```
prompts_tests.rs
├── 导入被测函数和依赖
├── 测试 1: build_stage_one_input_message_truncates_rollout_using_model_context_window (行 5-31)
└── 测试 2: build_stage_one_input_message_uses_default_limit_when_model_context_window_missing (行 33-51)
```

### 依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 被测函数 |
| `crate::models_manager::model_info::model_info_from_slug` | 模型信息构建 |
| `crate::truncate::TruncationPolicy` | 截断策略 |
| `crate::truncate::truncate_text` | 截断函数 |

## 依赖与外部交互

### 测试框架

- 使用标准 Rust 测试框架 (`#[test]`)

### 测试数据

- 使用 `model_info_from_slug` 获取模型信息
- 手动构建超大字符串（140万字符）测试截断

## 风险、边界与改进建议

### 当前覆盖缺口

1. **`build_consolidation_prompt`**:
   - 没有测试整合提示构建
   - 没有测试选择 diff 渲染

2. **`build_memory_tool_developer_instructions`**:
   - 没有测试异步开发者指令构建
   - 没有测试文件读取失败处理

3. **边界条件**:
   - 没有测试空内容
   - 没有测试零 token 限制
   - 没有测试超大 token 限制

4. **模板渲染**:
   - 没有测试模板渲染失败
   - 没有测试回退格式

### 改进建议

1. **添加整合提示测试**:
```rust
#[test]
fn build_consolidation_prompt_renders_selection_diff() {
    let selection = Phase2InputSelection {
        selected: vec![...],
        previous_selected: vec![...],
        retained_thread_ids: vec![...],
        removed: vec![...],
    };
    let prompt = build_consolidation_prompt(Path::new("/tmp/memories"), &selection);
    assert!(prompt.contains("selected inputs this run"));
    assert!(prompt.contains("newly added"));
    assert!(prompt.contains("retained"));
}
```

2. **添加开发者指令测试**:
```rust
#[tokio::test]
async fn build_memory_tool_developer_instructions_returns_none_for_missing_file() {
    let temp_dir = tempdir().unwrap();
    let result = build_memory_tool_developer_instructions(temp_dir.path()).await;
    assert!(result.is_none());
}
```

3. **添加边界测试**:
```rust
#[test]
fn build_stage_one_input_message_handles_empty_content() {
    let model_info = model_info_from_slug("gpt-5.2-codex");
    let message = build_stage_one_input_message(
        &model_info,
        Path::new("/tmp/rollout.jsonl"),
        Path::new("/tmp"),
        "",
    ).unwrap();
    assert!(message.contains("rollout_contents"));
}
```

4. **添加模板渲染测试**:
   - 测试所有模板字段正确替换
   - 测试特殊字符转义

5. **使用属性测试**:
   - 使用 `proptest` 生成随机模型参数
   - 验证 token 限制计算的单调性
