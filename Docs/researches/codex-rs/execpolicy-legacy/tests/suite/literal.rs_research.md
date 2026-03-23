# literal.rs 研究文档

## 场景与职责

`literal.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试**字面量参数匹配 (Literal Arg Matching)** 功能。该功能允许策略定义要求特定位置的参数必须是预定义的固定字符串值，常用于验证子命令或特定关键字。

## 功能点目的

### 1. 子命令验证

许多命令行工具使用子命令模式（如 `git clone`、`docker run`），需要验证第一个参数是允许的子命令。

### 2. 精确值约束

确保特定位置的参数必须是预定义的固定值，不接受变体或拼写差异。

### 3. 策略 DSL 功能验证

验证 Starlark 策略 DSL 中通过字符串字面量定义参数匹配器的功能正常工作。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `test_invalid_subcommand` | 验证字面量匹配和子命令验证 | 有效子命令通过，无效子命令拒绝 |

### 详细测试分析

#### test_invalid_subcommand

```rust
#[test]
fn test_invalid_subcommand() -> Result<()> {
    // 定义内联策略
    let unparsed_policy = r#"
define_program(
    program="fake_executable",
    args=["subcommand", "sub-subcommand"],
)
"#;
    let parser = PolicyParser::new("test_invalid_subcommand", unparsed_policy);
    let policy = parser.parse().expect("failed to parse policy");
    
    // 测试有效调用
    let valid_call = ExecCall::new("fake_executable", &["subcommand", "sub-subcommand"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new(
                "fake_executable",
                vec![
                    MatchedArg::new(0, ArgType::Literal("subcommand".to_string()), "subcommand")?,
                    MatchedArg::new(
                        1,
                        ArgType::Literal("sub-subcommand".to_string()),
                        "sub-subcommand"
                    )?,
                ],
                &[]
            )
        }),
        policy.check(&valid_call)
    );

    // 测试无效调用
    let invalid_call = ExecCall::new("fake_executable", &["subcommand", "not-a-real-subcommand"]);
    assert_eq!(
        Err(Error::LiteralValueDidNotMatch {
            expected: "sub-subcommand".to_string(),
            actual: "not-a-real-subcommand".to_string()
        }),
        policy.check(&invalid_call)
    );
    Ok(())
}
```

### 关键机制解析

#### 1. 内联策略定义

测试使用内联的 Starlark 策略定义，而非默认策略：
```rust
let unparsed_policy = r#"
define_program(
    program="fake_executable",
    args=["subcommand", "sub-subcommand"],
)
"#;
```

注意 `args` 数组中使用的是字符串字面量 `"subcommand"` 而非预定义的常量如 `ARG_RFILES`。

#### 2. 字面量到 ArgMatcher 的转换

在 `policy_parser.rs` 中，`ArgMatcher` 支持从字符串字面量解包：

```rust
// src/arg_matcher.rs
impl<'v> UnpackValue<'v> for ArgMatcher {
    type Error = starlark::Error;

    fn unpack_value_impl(value: Value<'v>) -> starlark::Result<Option<Self>> {
        if let Some(str) = value.downcast_ref::<StarlarkStr>() {
            Ok(Some(ArgMatcher::Literal(str.as_str().to_string())))
        } else {
            Ok(value.downcast_ref::<ArgMatcher>().cloned())
        }
    }
}
```

当 Starlark 解析 `"subcommand"` 时，它被转换为 `ArgMatcher::Literal("subcommand".to_string())`。

#### 3. 字面量验证逻辑

`ArgType::Literal` 的验证 (位于 `src/arg_type.rs`):

```rust
ArgType::Literal(literal_value) => {
    if value != *literal_value {
        Err(Error::LiteralValueDidNotMatch {
            expected: literal_value.clone(),
            actual: value.to_string(),
        })
    } else {
        Ok(())
    }
}
```

严格的字符串相等性检查，区分大小写，不允许额外空格。

#### 4. 成功匹配的结构

```rust
MatchedExec::Match {
    exec: ValidExec::new(
        "fake_executable",
        vec![
            MatchedArg::new(0, ArgType::Literal("subcommand".to_string()), "subcommand")?,
            MatchedArg::new(1, ArgType::Literal("sub-subcommand".to_string()), "sub-subcommand")?,
        ],
        &[]
    )
}
```

- `ArgType::Literal`: 记录预期的字面量值
- 实际值与预期值匹配时验证通过

#### 5. 失败错误类型

```rust
Error::LiteralValueDidNotMatch {
    expected: "sub-subcommand".to_string(),
    actual: "not-a-real-subcommand".to_string()
}
```

错误包含明确的预期值和实际值，便于调试。

## 关键代码路径与文件引用

### 字面量匹配流程

```
PolicyParser::parse()
    └── 解析 args=["subcommand", "sub-subcommand"]
        └── ArgMatcher::unpack_value_impl()
            └── ArgMatcher::Literal("subcommand")
            └── ArgMatcher::Literal("sub-subcommand")
    └── 构建 ProgramSpec
        └── arg_patterns = [Literal("subcommand"), Literal("sub-subcommand")]

policy.check(&exec_call)
    └── ProgramSpec::check()
        └── resolve_observed_args_with_patterns()
            ├── 前缀匹配: Literal("subcommand")
            │   └── 验证 "subcommand" == "subcommand" ✓
            └── 后缀匹配: Literal("sub-subcommand")
                └── 验证 "sub-subcommand" == "not-a-real-subcommand" ✗
                    └── Error::LiteralValueDidNotMatch
```

### 核心类型

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `ArgMatcher::Literal` | `src/arg_matcher.rs` | 字面量匹配器 |
| `ArgType::Literal` | `src/arg_type.rs` | 字面量参数类型 |
| `Error::LiteralValueDidNotMatch` | `src/error.rs` | 字面量不匹配错误 |
| `PolicyParser` | `src/policy_parser.rs` | 策略解析器 |
| `UnpackValue` | starlark crate | 值解包 trait |

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::ArgType;
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedArg;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::PolicyParser;
use codex_execpolicy_legacy::Result;
use codex_execpolicy_legacy::ValidExec;
```

注意：与大多数其他测试不同，此测试使用 `PolicyParser` 直接解析内联策略，而非 `get_default_policy()`。

### Starlark 集成

测试依赖 Starlark 配置 DSL 的以下特性：
- 字符串字面量解析
- `UnpackValue` trait 实现
- `define_program` 内置函数

## 风险、边界与改进建议

### 当前风险

1. **单一测试覆盖**: 仅测试了两个字面量参数的连续匹配，未测试：
   - 字面量与非字面量混合
   - 可选的字面量参数
   - 字面量变体列表（如接受多个有效子命令）

2. **大小写敏感**: 字面量匹配区分大小写，但测试未验证此行为

3. **空字符串**: 未测试空字符串字面量的处理

### 边界情况

1. **基数**: `ArgMatcher::Literal` 的基数为 `One`，恰好匹配一个参数
2. **位置敏感**: 字面量匹配严格依赖参数位置
3. **无回退**: 如果字面量不匹配，不会尝试其他匹配器

### 改进建议

1. **增加混合模式测试**:
   ```rust
   let unparsed_policy = r#"
define_program(
    program="git",
    args=["clone", ARG_RFILE],  // 字面量 + 非字面量混合
)
"#;
   ```

2. **增加大小写敏感测试**:
   ```rust
   let invalid_call = ExecCall::new("fake_executable", &["SubCommand", "sub-subcommand"]);
   // 验证 "SubCommand" != "subcommand" 被拒绝
   ```

3. **增加多子命令支持测试**:
   ```rust
   // 测试如何支持多个有效子命令
   // 可能需要 ArgMatcher::OneOf 或类似机制
   ```

4. **文档示例**: 在 `default.policy` 中添加字面量使用的实际示例

5. **错误消息改进**: 当前错误消息仅显示预期和实际值，可增加位置信息：
   ```rust
   Error::LiteralValueDidNotMatch {
       position: 1,
       expected: "sub-subcommand".to_string(),
       actual: "not-a-real-subcommand".to_string()
   }
   ```
