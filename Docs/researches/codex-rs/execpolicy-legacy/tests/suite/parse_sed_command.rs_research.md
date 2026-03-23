# parse_sed_command.rs 研究文档

## 场景与职责

`parse_sed_command.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试 `parse_sed_command` 函数的 sed 命令解析逻辑。由于 GNU sed 支持危险的 `e` 标志（可执行任意 shell 命令），策略引擎需要严格限制允许的 sed 命令格式。

## 功能点目的

### 1. 安全的 Sed 命令白名单

验证 `parse_sed_command` 函数只能识别和允许特定格式的 sed 命令，拒绝所有可能包含危险操作的命令。

### 2. 行范围打印命令验证

当前实现仅支持 `122,202p` 格式的命令（打印指定行范围），这是 sed 最常见的安全用法之一。

### 3. 危险命令拒绝

确保任何不符合严格白名单格式的命令都被拒绝，防止命令注入或任意代码执行。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `parses_simple_print_command` | 验证标准行范围打印命令 | `Ok(())` |
| `rejects_malformed_print_command` | 验证格式错误的命令被拒绝 | `SedCommandNotProvablySafe` 错误 |

### 详细测试分析

#### parses_simple_print_command

```rust
#[test]
fn parses_simple_print_command() {
    assert_eq!(parse_sed_command("122,202p"), Ok(()));
}
```

测试验证最简单的安全 sed 命令格式：
- 起始行号：`122`
- 逗号分隔：`,`
- 结束行号：`202`
- 打印命令：`p`

#### rejects_malformed_print_command

```rust
#[test]
fn rejects_malformed_print_command() {
    assert_eq!(
        parse_sed_command("122,202"),
        Err(Error::SedCommandNotProvablySafe {
            command: "122,202".to_string(),
        })
    );
    assert_eq!(
        parse_sed_command("122202"),
        Err(Error::SedCommandNotProvablySafe {
            command: "122202".to_string(),
        })
    );
}
```

测试验证两种格式错误：
1. `"122,202"` - 缺少 `p` 后缀
2. `"122202"` - 缺少逗号分隔符

### parse_sed_command 实现

位于 `src/sed_command.rs`:

```rust
pub fn parse_sed_command(sed_command: &str) -> Result<()> {
    // For now, we parse only commands like `122,202p`.
    if let Some(stripped) = sed_command.strip_suffix("p")
        && let Some((first, rest)) = stripped.split_once(",")
        && first.parse::<u64>().is_ok()
        && rest.parse::<u64>().is_ok()
    {
        return Ok(());
    }

    Err(Error::SedCommandNotProvablySafe {
        command: sed_command.to_string(),
    })
}
```

解析逻辑：
1. 检查字符串以 `"p"` 结尾（打印命令）
2. 去掉 `"p"` 后，检查剩余部分包含逗号
3. 逗号前后都必须是有效的 `u64` 数字

### 在策略中的使用

`parse_sed_command` 通过 `ArgType::SedCommand` 在参数验证中使用 (位于 `src/arg_type.rs`):

```rust
impl ArgType {
    pub fn validate(&self, value: &str) -> Result<()> {
        match self {
            ...
            ArgType::SedCommand => parse_sed_command(value),
            ...
        }
    }
}
```

### 策略配置中的 Sed 支持

`default.policy` 中的 sed 定义：

```python
# Unfortunately, `sed` is difficult to secure because GNU sed supports an `e`
# flag where `s/pattern/replacement/e` would run `replacement` as a shell
# command every time `pattern` is matched. For example, try the following on
# Ubuntu (which uses GNU sed, unlike macOS):
#
# ```shell
# $ yes | head -n 4 > /tmp/yes.txt
# $ sed 's/y/echo hi/e' /tmp/yes.txt
# hi
# hi
# hi
# hi
# ```
#
# As you can see, `echo hi` got executed four times. In order to support some
# basic sed functionality, we implement a bespoke `ARG_SED_COMMAND` that matches
# only "known safe" sed commands.
common_sed_flags = [
    # We deliberately do not support -i or -f.
    flag("-n"),
    flag("-u"),
]
sed_system_path = ["/usr/bin/sed"]

# When -e is not specified, the first argument must be a valid sed command.
define_program(
    program="sed",
    options=common_sed_flags,
    args=[ARG_SED_COMMAND, ARG_RFILES],
    system_path=sed_system_path,
)

# When -e is required, all arguments are assumed to be readable files.
define_program(
    program="sed",
    options=common_sed_flags + [
        opt("-e", ARG_SED_COMMAND, required=True),
    ],
    args=[ARG_RFILES],
    system_path=sed_system_path,
)
```

关键安全决策：
1. **不支持 `-i`**：就地编辑可能破坏文件
2. **不支持 `-f`**：从文件读取脚本可能包含任意命令
3. **仅支持白名单命令格式**：`122,202p` 形式的行范围打印

## 关键代码路径与文件引用

### 调用链

```
sed.rs::test_sed_print_specific_lines
    └── ExecCall::new("sed", &["-n", "122,202p", "hello.txt"])
        └── policy.check(&cp)
            └── ProgramSpec::check()
                └── resolve_observed_args_with_patterns()
                    └── MatchedArg::new(1, ArgType::SedCommand, "122,202p")
                        └── ArgType::SedCommand.validate("122,202p")
                            └── parse_sed_command("122,202p")
                                ├── strip_suffix("p") -> Some("122,202")
                                ├── split_once(",") -> Some(("122", "202"))
                                ├── "122".parse::<u64>() -> Ok(122)
                                ├── "202".parse::<u64>() -> Ok(202)
                                └── Ok(())
```

### 相关文件

| 文件 | 职责 |
|------|------|
| `tests/suite/parse_sed_command.rs` | 本测试文件 |
| `src/sed_command.rs` | `parse_sed_command` 函数实现 |
| `src/arg_type.rs` | `ArgType::SedCommand` 及验证逻辑 |
| `src/arg_matcher.rs` | `ArgMatcher::SedCommand` 定义 |
| `src/default.policy` | sed 策略定义 |

### 核心类型

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `parse_sed_command` | `src/sed_command.rs` | sed 命令解析函数 |
| `ArgType::SedCommand` | `src/arg_type.rs` | sed 命令参数类型 |
| `ArgMatcher::SedCommand` | `src/arg_matcher.rs` | sed 命令匹配器 |
| `Error::SedCommandNotProvablySafe` | `src/error.rs` | 不安全 sed 命令错误 |

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::parse_sed_command;
```

注意：此测试直接测试 `parse_sed_command` 函数，不通过完整的策略检查流程。

### 被测试函数签名

```rust
pub fn parse_sed_command(sed_command: &str) -> Result<()>
```

- 输入：候选 sed 命令字符串
- 输出：`Ok(())` 表示安全可接受，`Err(Error::SedCommandNotProvablySafe)` 表示不安全

## 风险、边界与改进建议

### 当前风险

1. **过度限制**: 当前仅支持 `122,202p` 格式，许多合法的 sed 用法被拒绝
2. **行号溢出**: 未测试极大行号（如超过 `u64::MAX`）的处理
3. **格式变体**: 不支持 `1p`（单行）、`1,$p`（到文件末尾）等常见变体
4. **其他安全命令**: 不支持 `d`（删除）、`q`（退出）等其他安全命令

### 边界情况

1. **空字符串**: 未测试空字符串输入
2. **零行号**: `0` 作为行号在某些 sed 实现中有效（第一行之前）
3. **起始大于结束**: `202,122p` 在语法上可通过验证，但逻辑上可能无意义
4. **前导零**: `012,034p` 的解析行为

### 改进建议

1. **扩展支持的命令格式**:
   ```rust
   pub fn parse_sed_command(sed_command: &str) -> Result<()> {
       // 现有：行范围打印
       if is_range_print(sed_command) {
           return Ok(());
       }
       
       // 新增：单行打印
       if is_single_line_print(sed_command) {
           return Ok(());
       }
       
       // 新增：到文件末尾
       if is_range_to_end_print(sed_command) {
           return Ok(());
       }
       
       Err(Error::SedCommandNotProvablySafe { ... })
   }
   ```

2. **增加边界测试**:
   ```rust
   #[test]
   fn test_edge_cases() {
       // 空字符串
       assert!(parse_sed_command("").is_err());
       
       // 极大行号
       assert!(parse_sed_command("1,18446744073709551615p").is_ok());
       
       // 起始大于结束
       assert!(parse_sed_command("202,122p").is_ok()); // 或根据策略决定
       
       // 前导零
       assert!(parse_sed_command("01,10p").is_ok());
   }
   ```

3. **支持 `$` 表示文件末尾**:
   ```rust
   // 支持 1,$p（打印所有行）
   fn is_range_to_end_print(s: &str) -> bool {
       // 实现解析逻辑
   }
   ```

4. **增加注释和文档**:
   ```rust
   /// Parses a sed command to determine if it is provably safe.
   ///
   /// Currently supported formats:
   /// - `N,Mp`: Print lines N through M (e.g., "122,202p")
   ///
   /// All other commands are rejected as potentially unsafe.
   pub fn parse_sed_command(sed_command: &str) -> Result<()> { ... }
   ```

5. **考虑使用正则表达式**:
   ```rust
   use regex_lite::Regex;
   
   lazy_static::lazy_static! {
       static ref SAFE_SED_PATTERN: Regex = 
           Regex::new(r"^(\d+),(\d+)p$").unwrap();
   }
   ```

6. **行号顺序验证**:
   ```rust
   if first.parse::<u64>()? > rest.parse::<u64>()? {
       // 起始行号大于结束行号，可能无效
   }
   ```
