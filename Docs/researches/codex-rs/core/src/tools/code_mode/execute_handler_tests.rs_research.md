# execute_handler_tests.rs 研究文档

## 场景与职责

`execute_handler_tests.rs` 是 `execute_handler.rs` 的**单元测试模块**，负责验证参数解析逻辑的正确性。该测试文件通过 `#[path = "execute_handler_tests.rs"]` 属性在 `execute_handler.rs` 中被条件编译引入。

**核心定位**：
- 测试 `parse_freeform_args` 函数的各种输入场景
- 验证 pragma 解析的正确性和错误处理
- 确保边界情况得到正确处理

## 功能点目的

### 1. 无 Pragma 场景测试
```rust
#[test]
fn parse_freeform_args_without_pragma() {
    let args = parse_freeform_args("output_text('ok');").expect("parse args");
    assert_eq!(args.code, "output_text('ok');");
    assert_eq!(args.yield_time_ms, None);
    assert_eq!(args.max_output_tokens, None);
}
```
- 验证普通 JavaScript 代码（无 pragma）被正确解析
- 确认 `yield_time_ms` 和 `max_output_tokens` 默认为 `None`

### 2. 带 Pragma 场景测试
```rust
#[test]
fn parse_freeform_args_with_pragma() {
    let input = concat!(
        "// @exec: {\"yield_time_ms\": 15000, \"max_output_tokens\": 2000}\n",
        "output_text('ok');",
    );
    let args = parse_freeform_args(input).expect("parse args");
    assert_eq!(args.code, "output_text('ok');");
    assert_eq!(args.yield_time_ms, Some(15_000));
    assert_eq!(args.max_output_tokens, Some(2_000));
}
```
- 验证 pragma 被正确解析并提取
- 确认代码部分（pragma 后的内容）被正确分离
- 验证数值参数被正确解析为 `Some(value)`

### 3. 未知字段拒绝测试
```rust
#[test]
fn parse_freeform_args_rejects_unknown_key() {
    let err = parse_freeform_args("// @exec: {\"nope\": 1}\noutput_text('ok');")
        .expect_err("expected error");
    assert_eq!(
        err.to_string(),
        "exec pragma only supports `yield_time_ms` and `max_output_tokens`; got `nope`"
    );
}
```
- 验证未知字段被正确拒绝
- 确认错误消息清晰指明问题

### 4. 缺少源码拒绝测试
```rust
#[test]
fn parse_freeform_args_rejects_missing_source() {
    let err = parse_freeform_args("// @exec: {\"yield_time_ms\": 10}").expect_err("expected error");
    assert_eq!(
        err.to_string(),
        "exec pragma must be followed by JavaScript source on subsequent lines"
    );
}
```
- 验证 pragma 后必须有实际代码
- 防止用户只发送 pragma 而无实际执行内容

## 具体技术实现

### 测试结构
```rust
use super::parse_freeform_args;  // 引入被测函数
use pretty_assertions::assert_eq; // 美观的断言输出

// 测试用例 1: 无 pragma
// 测试用例 2: 带 pragma
// 测试用例 3: 未知字段
// 测试用例 4: 缺少源码
```

### 测试覆盖分析

| 测试函数 | 覆盖场景 | 被测代码路径 |
|---------|---------|-------------|
| `parse_freeform_args_without_pragma` | 普通代码输入 | 第 103-107, 119-120 行 |
| `parse_freeform_args_with_pragma` | 有效 pragma | 第 115-184 行（完整流程） |
| `parse_freeform_args_rejects_unknown_key` | 未知字段检查 | 第 148-156 行 |
| `parse_freeform_args_rejects_missing_source` | 空代码检查 | 第 123-127 行 |

### 未覆盖的边界情况

根据 `execute_handler.rs` 的实现，以下场景**未被测试覆盖**：

1. **空输入**
   ```rust
   if input.trim().is_empty() { ... }
   ```
   第 103-107 行的空输入检查

2. **pragma 格式错误**
   ```rust
   let value: serde_json::Value = serde_json::from_str(directive).map_err(...)
   ```
   第 137-141 行的 JSON 解析错误

3. **pragma 非对象**
   ```rust
   let object = value.as_object().ok_or_else(|| { ... })
   ```
   第 142-147 行的非对象检查

4. **数值超出安全整数范围**
   ```rust
   if pragma.yield_time_ms.is_some_and(|yield_time_ms| yield_time_ms > MAX_JS_SAFE_INTEGER)
   ```
   第 164-180 行的数值范围检查

5. **pragma 仅包含空白**
   ```rust
   let directive = pragma.trim();
   if directive.is_empty() { ... }
   ```
   第 129-135 行的空白 pragma 检查

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler_tests.rs`

### 被测文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler.rs`
  - 第 220-222 行引入测试模块：
    ```rust
    #[cfg(test)]
    #[path = "execute_handler_tests.rs"]
    mod execute_handler_tests;
    ```

### 被测函数
- `execute_handler.rs` 第 102-185 行的 `parse_freeform_args` 函数

### 测试依赖
| crate | 用途 |
|-------|------|
| `pretty_assertions` | 提供 `assert_eq` 宏，失败时输出美观的 diff |

## 依赖与外部交互

### 模块关系
```
execute_handler.rs
    │
    ├──> 正常编译：execute_handler_tests.rs 不参与
    │
    └──> test 编译：#[cfg(test)] 激活
             │
             └──> mod execute_handler_tests;
                      │
                      └──> execute_handler_tests.rs 内容内联
```

### 测试执行
```bash
# 运行特定测试
cargo test -p codex-core parse_freeform_args_without_pragma

# 运行所有 execute_handler 测试
cargo test -p codex-core execute_handler

# 运行所有 code_mode 测试
cargo test -p codex-core code_mode
```

## 风险、边界与改进建议

### 风险点

1. **测试覆盖不足**
   - 当前仅测试了 4 个场景，而 `parse_freeform_args` 有 10+ 个错误分支
   - 关键边界（如数值溢出、空 pragma）未测试

2. **测试与实现耦合**
   - 错误消息字符串硬编码在测试中
   - 如果修改错误消息，测试会失败（这可能是好事，也可能是维护负担）

3. **无集成测试**
   - 仅测试了参数解析，未测试完整的 `execute` 方法
   - 无法验证与 `CodeModeService`、`CodeModeProcess` 的集成

### 边界情况

1. **换行符处理**
   - 测试使用 `concat!` 宏和 `\n`，但 Windows 平台可能使用 `\r\n`
   - 实际代码使用 `splitn(2, '\n')`，可能无法正确处理 `\r\n`

2. **Unicode 输入**
   - 测试未覆盖包含 Unicode 的 pragma 或代码
   - 实际代码使用 `&str`，应该支持，但未验证

3. **超大数值**
   - 测试使用合理的数值（15000, 2000）
   - 未测试接近 `MAX_JS_SAFE_INTEGER` 的边界值

### 改进建议

1. **增加边界测试**
   ```rust
   #[test]
   fn parse_freeform_args_rejects_empty_input() {
       let err = parse_freeform_args("").expect_err("expected error");
       assert!(err.to_string().contains("non-empty"));
   }

   #[test]
   fn parse_freeform_args_rejects_invalid_json() {
       let err = parse_freeform_args("// @exec: invalid json\ncode();").expect_err("expected error");
       assert!(err.to_string().contains("valid JSON"));
   }

   #[test]
   fn parse_freeform_args_rejects_non_object_pragma() {
       let err = parse_freeform_args("// @exec: [1, 2, 3]\ncode();").expect_err("expected error");
       assert!(err.to_string().contains("JSON object"));
   }

   #[test]
   fn parse_freeform_args_rejects_overflow_yield_time() {
       let err = parse_freeform_args("// @exec: {\"yield_time_ms\": 9007199254740992}\ncode();")
           .expect_err("expected error");
       assert!(err.to_string().contains("safe integer"));
   }
   ```

2. **增加正边界测试**
   ```rust
   #[test]
   fn parse_freeform_args_accepts_max_safe_integer() {
       let input = "// @exec: {\"yield_time_ms\": 9007199254740991}\ncode();";
       let args = parse_freeform_args(input).expect("parse args");
       assert_eq!(args.yield_time_ms, Some(9007199254740991));
   }
   ```

3. **使用参数化测试**
   ```rust
   use test_case::test_case;

   #[test_case("// @exec: {}\ncode();", Some(0), None ; "empty object")]
   #[test_case("// @exec: {\"yield_time_ms\": 100}\ncode();", Some(100), None ; "only yield_time")]
   #[test_case("// @exec: {\"max_output_tokens\": 500}\ncode();", None, Some(500) ; "only max_tokens")]
   fn parse_pragma_variations(input: &str, expected_yield: Option<u64>, expected_tokens: Option<usize>) {
       let args = parse_freeform_args(input).expect("parse args");
       assert_eq!(args.yield_time_ms, expected_yield);
       assert_eq!(args.max_output_tokens, expected_tokens);
   }
   ```

4. **添加集成测试**
   - 在 `codex-rs/core/tests/` 或 `codex-rs/core/src/tools/code_mode/tests/` 添加
   - 使用 mock 的 `CodeModeProcess` 测试完整执行流程

5. **测试文档化**
   - 为每个测试添加文档注释，说明测试目的和覆盖的代码路径
   - 例如：
     ```rust
     /// Test: parse_freeform_args_without_pragma
     /// Covers: execute_handler.rs:103-107, 119-120
     /// Scenario: User sends raw JavaScript without any pragma
     ```
