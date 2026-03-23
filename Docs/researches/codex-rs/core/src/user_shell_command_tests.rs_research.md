# user_shell_command_tests.rs 研究文档

## 场景与职责

`user_shell_command_tests.rs` 是 `user_shell_command.rs` 的配套测试模块，负责验证用户 Shell 命令格式化功能的正确性。测试覆盖：

1. **片段匹配**：验证 `USER_SHELL_COMMAND_FRAGMENT` 能正确识别用户 Shell 命令文本
2. **基本格式化**：验证标准执行输出的格式化
3. **输出选择**：验证优先使用聚合输出而非单独的标准输出/错误

## 功能点目的

### 测试用例设计意图

| 测试函数 | 目的 |
|----------|------|
| `detects_user_shell_command_text_variants` | 验证片段匹配逻辑能识别有效格式 |
| `formats_basic_record` | 验证基本执行结果的格式化输出 |
| `uses_aggregated_output_over_streams` | 验证聚合输出的优先级 |

## 具体技术实现

### 测试 1：片段匹配

```rust
#[test]
fn detects_user_shell_command_text_variants()
```

**测试内容**：
1. 验证包含 `<user_shell_command>` 标签的文本被识别
2. 验证普通命令文本不被识别

**关键技术点**：
- 使用 `USER_SHELL_COMMAND_FRAGMENT.matches_text()`
- 验证 `ContextualUserFragmentDefinition` 的匹配逻辑

### 测试 2：基本格式化

```rust
#[tokio::test]
async fn formats_basic_record()
```

**测试流程**：
1. 构造 `ExecToolCallOutput`：
   - 退出码：0
   - 标准输出："hi"
   - 标准错误：空
   - 聚合输出："hi"
   - 时长：1 秒
   - 未超时

2. 使用 `make_session_and_context()` 创建测试上下文

3. 调用 `user_shell_command_record_item` 生成 `ResponseItem`

4. 验证生成的消息内容：
   - 包含 `<user_shell_command>` 标签
   - 包含命令 `echo hi`
   - 包含退出码 `0`
   - 包含时长 `1.0000 seconds`
   - 包含输出 `hi`

**关键技术点**：
- 使用 `make_session_and_context()` 获取 `TurnContext`
- 解构 `ResponseItem` 验证内容
- 使用 `pretty_assertions::assert_eq` 比较完整字符串

### 测试 3：聚合输出优先级

```rust
#[tokio::test]
async fn uses_aggregated_output_over_streams()
```

**测试流程**：
1. 构造 `ExecToolCallOutput`：
   - 退出码：42
   - 标准输出："stdout-only"
   - 标准错误："stderr-only"
   - 聚合输出："combined output wins"（与 stdout/stderr 不同）
   - 时长：120 毫秒

2. 调用 `format_user_shell_command_record`

3. 验证输出使用聚合输出内容

**关键技术点**：
- 验证聚合输出优先于单独的 stdout/stderr
- 验证毫秒级时长格式化（`0.1200 seconds`）

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `USER_SHELL_COMMAND_FRAGMENT` | `contextual_user_message.rs:75` |
| `user_shell_command_record_item` | `user_shell_command.rs:45` |
| `format_user_shell_command_record` | `user_shell_command.rs:36` |
| `format_exec_output_str` | `tools.rs:98` |

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `ExecToolCallOutput` | 构造测试执行输出 |
| `StreamOutput` | 包装输出字符串 |
| `make_session_and_context` | 创建测试上下文 |
| `TurnContext` | 提供截断策略 |
| `ContentItem` | 解构响应内容 |
| `pretty_assertions::assert_eq` | 更好的断言输出 |

## 依赖与外部交互

### 测试数据构造

```rust
ExecToolCallOutput {
    exit_code: 0,
    stdout: StreamOutput::new("hi".to_string()),
    stderr: StreamOutput::new(String::new()),
    aggregated_output: StreamOutput::new("hi".to_string()),
    duration: Duration::from_secs(1),
    timed_out: false,
}
```

### 异步测试

```rust
#[tokio::test]
async fn formats_basic_record()
```

- 使用 `make_session_and_context()` 需要异步运行时
- 测试函数标记为 `async`

## 风险、边界与改进建议

### 当前测试覆盖的不足

1. **缺少超时场景测试**
   - 未测试 `timed_out: true` 时的输出
   - 应验证超时提示是否包含在输出中

2. **缺少大输出测试**
   - 未测试截断策略生效时的行为
   - 应验证长输出被正确截断

3. **缺少特殊字符测试**
   - 未测试命令或输出包含 XML 特殊字符的情况
   - 应测试 `<`, `>`, `&` 等字符

4. **缺少非零退出码测试**
   - 虽然测试 2 使用了退出码 42，但未验证错误处理
   - 应明确测试错误场景的格式化

5. **缺少空输出测试**
   - 未测试命令无输出的情况

### 改进建议

1. **添加超时测试**
```rust
#[tokio::test]
async fn includes_timeout_notice_for_timed_out_commands() {
    let exec_output = ExecToolCallOutput {
        timed_out: true,
        // ...
    };
    // 验证输出包含超时提示
}
```

2. **添加特殊字符测试**
```rust
#[tokio::test]
async fn handles_special_xml_characters() {
    let exec_output = ExecToolCallOutput {
        aggregated_output: StreamOutput::new("output with <tag> & ampersand".to_string()),
        // ...
    };
    // 验证 XML 正确转义或处理
}
```

3. **添加截断测试**
```rust
#[tokio::test]
async fn truncates_long_output() {
    let long_output = "x".repeat(100_000);
    let exec_output = ExecToolCallOutput {
        aggregated_output: StreamOutput::new(long_output),
        // ...
    };
    // 验证输出被截断
}
```

4. **添加空命令测试**
```rust
#[tokio::test]
async fn handles_empty_command() {
    let item = user_shell_command_record_item("", &exec_output, &turn_context);
    // 验证行为合理
}
```

### 潜在风险

1. **测试与实现耦合**
   - 测试验证完整的格式化字符串
   - 格式变更会导致测试失败

2. **异步复杂性**
   - 需要 `tokio` 运行时
   - 增加了测试启动开销

3. **依赖测试辅助函数**
   - `make_session_and_context` 的实现变化可能影响测试

### 测试质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 覆盖率 | 中 | 基本场景覆盖，缺少边界情况 |
| 可读性 | 高 | 测试意图清晰 |
| 维护性 | 中 | 字符串匹配可能脆弱 |
| 可靠性 | 高 | 不依赖外部系统 |
