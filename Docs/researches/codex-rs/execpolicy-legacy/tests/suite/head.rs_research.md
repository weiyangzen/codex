# head.rs 研究文档

## 场景与职责

`head.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试 `head` 命令的策略验证逻辑。`head` 用于显示文件开头部分，是一个相对安全的只读命令，但其 `-n` (行数) 和 `-c` (字节数) 选项需要验证参数值为正整数。

## 功能点目的

### 1. 无参数调用处理

验证 `head` 不带参数时的策略行为。虽然技术上合法（从 stdin 读取），但策略可能出于安全考虑要求至少一个文件参数。

### 2. 选项值类型验证

验证 `-n` 选项的值必须是**正整数**（大于 0），拒绝：
- 零 (`0`)
- 负数 (`-1`)
- 浮点数 (`1.5`, `1.0`)

### 3. 文件参数识别

验证非选项参数被正确识别为 `ReadableFile` 类型。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `test_head_no_args` | 验证无参数调用 | `VarargMatcherDidNotMatchAnything` 错误 |
| `test_head_one_file_no_flags` | 验证单文件调用 | `MatchedExec::Match` 成功 |
| `test_head_one_flag_one_file` | 验证 `-n` 选项使用 | `MatchedExec::Match` 成功 |
| `test_head_invalid_n_as_0` | 验证 `-n 0` 被拒绝 | `InvalidPositiveInteger` 错误 |
| `test_head_invalid_n_as_nonint_float` | 验证 `-n 1.5` 被拒绝 | `InvalidPositiveInteger` 错误 |
| `test_head_invalid_n_as_float` | 验证 `-n 1.0` 被拒绝 | `InvalidPositiveInteger` 错误 |
| `test_head_invalid_n_as_negative_int` | 验证 `-n -1` 被拒绝 | `OptionFollowedByOptionInsteadOfValue` 错误 |

### 详细测试分析

#### test_head_no_args

```rust
#[test]
fn test_head_no_args() {
    let policy = setup();
    let head = ExecCall::new("head", &[]);
    assert_eq!(
        Err(Error::VarargMatcherDidNotMatchAnything {
            program: "head".to_string(),
            matcher: ArgMatcher::ReadableFiles,
        }),
        policy.check(&head)
    )
}
```

**注释说明**: 虽然 `head` 无参数时从 stdin 读取是合法的，但策略出于当前用例考虑拒绝此模式。

**策略配置** (`default.policy`):
```python
define_program(
    program="head",
    system_path=["/bin/head", "/usr/bin/head"],
    options=[
        opt("-c", ARG_POS_INT),
        opt("-n", ARG_POS_INT),
    ],
    args=[ARG_RFILES],  # 至少一个可读文件
)
```

`ARG_RFILES` (ReadableFiles) 要求至少匹配一个参数，因此空参数列表会被拒绝。

#### test_head_one_file_no_flags

```rust
#[test]
fn test_head_one_file_no_flags() -> Result<()> {
    let policy = setup();
    let head = ExecCall::new("head", &["src/extension.ts"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new(
                "head",
                vec![MatchedArg::new(
                    0,
                    ArgType::ReadableFile,
                    "src/extension.ts"
                )?],
                &["/bin/head", "/usr/bin/head"]
            )
        }),
        policy.check(&head)
    );
    Ok(())
}
```

成功匹配的结构：
- `MatchedArg::new(0, ArgType::ReadableFile, "src/extension.ts")` - 参数索引 0，类型为可读文件

#### test_head_one_flag_one_file

```rust
#[test]
fn test_head_one_flag_one_file() -> Result<()> {
    let policy = setup();
    let head = ExecCall::new("head", &["-n", "100", "src/extension.ts"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "head".to_string(),
                flags: vec![],
                opts: vec![
                    MatchedOpt::new("-n", "100", ArgType::PositiveInteger)
                        .expect("should validate")
                ],
                args: vec![MatchedArg::new(
                    2,
                    ArgType::ReadableFile,
                    "src/extension.ts"
                )?],
                system_path: vec!["/bin/head".to_string(), "/usr/bin/head".to_string()],
            }
        }),
        policy.check(&head)
    );
    Ok(())
}
```

关键观察：
- `-n` 被识别为 `MatchedOpt`，值为 `"100"`，类型为 `PositiveInteger`
- 文件参数索引为 2（因为 `-n` 和 `100` 占据了索引 0 和 1）

#### 无效值测试系列

**test_head_invalid_n_as_0**:
```rust
assert_eq!(
    Err(Error::InvalidPositiveInteger { value: "0".to_string() }),
    policy.check(&head)
)
```

**test_head_invalid_n_as_nonint_float**:
```rust
assert_eq!(
    Err(Error::InvalidPositiveInteger { value: "1.5".to_string() }),
    policy.check(&head)
)
```

**test_head_invalid_n_as_float**:
```rust
assert_eq!(
    Err(Error::InvalidPositiveInteger { value: "1.0".to_string() }),
    policy.check(&head)
)
```

**test_head_invalid_n_as_negative_int**:
```rust
assert_eq!(
    Err(Error::OptionFollowedByOptionInsteadOfValue {
        program: "head".to_string(),
        option: "-n".to_string(),
        value: "-1".to_string(),
    }),
    policy.check(&head)
)
```

注意：负数 `-1` 被识别为另一个选项而非无效值，因此产生不同的错误类型。

### 正整数验证逻辑

`ArgType::PositiveInteger` 的验证逻辑 (位于 `src/arg_type.rs`):

```rust
ArgType::PositiveInteger => match value.parse::<u64>() {
    Ok(0) => Err(Error::InvalidPositiveInteger {
        value: value.to_string(),
    }),
    Ok(_) => Ok(()),
    Err(_) => Err(Error::InvalidPositiveInteger {
        value: value.to_string(),
    }),
},
```

验证规则：
1. 必须能解析为 `u64`
2. 不能为零
3. 不能包含小数点

## 关键代码路径与文件引用

### 选项解析流程

```
ExecCall::new("head", &["-n", "100", "file.txt"])
    └── policy.check(&cp)
        └── ProgramSpec::check()
            ├── 解析 "-n": 查找 allowed_options
            │   └── 发现 OptMeta::Value(PositiveInteger)
            │   └── expecting_option_value = Some(("-n", PositiveInteger))
            ├── 解析 "100": 发现 expecting_option_value
            │   └── MatchedOpt::new("-n", "100", PositiveInteger)
            │   └── PositiveInteger.validate("100") -> Ok(())
            ├── 解析 "file.txt": 普通参数
            │   └── 加入 args 列表
            └── resolve_observed_args_with_patterns()
                └── 匹配 ARG_RFILES
```

### 核心类型

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `Opt` | `src/opt.rs` | 选项定义（flag 或 value） |
| `OptMeta::Value` | `src/opt.rs` | 带值的选项元数据 |
| `ArgType::PositiveInteger` | `src/arg_type.rs` | 正整数参数类型 |
| `MatchedOpt` | `src/valid_exec.rs` | 匹配成功的选项 |
| `Error::InvalidPositiveInteger` | `src/error.rs` | 正整数验证错误 |
| `Error::OptionFollowedByOptionInsteadOfValue` | `src/error.rs` | 选项值被解释为选项的错误 |

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::ArgMatcher;
use codex_execpolicy_legacy::ArgType;
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedArg;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::MatchedOpt;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::Result;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

### 策略配置

```python
define_program(
    program="head",
    system_path=["/bin/head", "/usr/bin/head"],
    options=[
        opt("-c", ARG_POS_INT),  # 字节数限制
        opt("-n", ARG_POS_INT),  # 行数限制
    ],
    args=[ARG_RFILES],
)
```

## 风险、边界与改进建议

### 当前风险

1. **`-c` 选项未测试**: 虽然策略定义了 `-c` 选项，但测试仅覆盖 `-n`
2. **大数处理**: 未测试极大正整数（如 `u64::MAX`）的处理
3. **多文件场景**: 未测试 `head` 处理多个文件的情况

### 边界情况

1. **零值处理**: `0` 被明确拒绝，这与某些 `head` 实现的行为一致
2. **负数识别**: `-1` 被识别为选项而非无效正整数，这是命令行解析的通用行为
3. **浮点数**: 即使是 `1.0` 也被拒绝，确保严格的整数语义

### 改进建议

1. **增加 `-c` 选项测试**:
   ```rust
   #[test]
   fn test_head_c_option() -> Result<()> {
       let policy = setup();
       let head = ExecCall::new("head", &["-c", "1024", "file.txt"]);
       // 验证 -c 选项被正确识别
       Ok(())
   }
   ```

2. **增加边界值测试**:
   ```rust
   #[test]
   fn test_head_n_max_value() -> Result<()> {
       let policy = setup();
       let head = ExecCall::new("head", &["-n", "18446744073709551615", "file.txt"]);
       // 测试 u64::MAX
       Ok(())
   }
   ```

3. **增加多文件测试**:
   ```rust
   #[test]
   fn test_head_multiple_files() -> Result<()> {
       let policy = setup();
       let head = ExecCall::new("head", &["file1.txt", "file2.txt"]);
       // 验证多文件处理
       Ok(())
   }
   ```

4. **考虑 stdin 场景**: 如果业务需求变化，可能需要重新评估无参数调用的策略

5. **错误消息改进**: 当前错误仅说明"无效正整数"，可提供更具体的指导（如"必须是大于 0 的整数"）
