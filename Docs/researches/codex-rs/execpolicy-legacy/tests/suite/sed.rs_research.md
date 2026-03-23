# sed.rs 研究文档

## 场景与职责

`sed.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试 `sed` (流编辑器) 命令的策略验证逻辑。`sed` 是一个功能强大的文本处理工具，但由于 GNU sed 支持危险的 `e` 标志（可执行任意 shell 命令），策略引擎对其有严格的限制。

## 功能点目的

### 1. 安全 Sed 命令验证

验证策略正确识别和允许安全的 sed 命令格式（如行范围打印），拒绝可能包含危险操作的命令。

### 2. 选项组合验证

测试 sed 的选项组合：
- `-n`: 静默模式（不自动打印每行）
- `-e`: 显式指定 sed 命令脚本

### 3. 危险命令拒绝

验证包含 `e` 标志的替换命令被拒绝，防止任意代码执行。

### 4. 必需选项验证

验证当不使用 `-e` 选项时，第一个参数必须是有效的 sed 命令。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `test_sed_print_specific_lines` | 验证标准行打印命令 | `MatchedExec::Match` 成功 |
| `test_sed_print_specific_lines_with_e_flag` | 验证 `-e` 选项使用 | `MatchedExec::Match` 成功 |
| `test_sed_reject_dangerous_command` | 验证危险命令被拒绝 | `SedCommandNotProvablySafe` 错误 |
| `test_sed_verify_e_or_pattern_is_required` | 验证必需选项检查 | `MissingRequiredOptions` 错误 |

### 详细测试分析

#### test_sed_print_specific_lines

```rust
#[test]
fn test_sed_print_specific_lines() -> Result<()> {
    let policy = setup();
    let sed = ExecCall::new("sed", &["-n", "122,202p", "hello.txt"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "sed".to_string(),
                flags: vec![MatchedFlag::new("-n")],
                args: vec![
                    MatchedArg::new(1, ArgType::SedCommand, "122,202p")?,
                    MatchedArg::new(2, ArgType::ReadableFile, "hello.txt")?,
                ],
                system_path: vec!["/usr/bin/sed".to_string()],
                ..Default::default()
            }
        }),
        policy.check(&sed)
    );
    Ok(())
}
```

**命令结构分析**:
- `-n`: 静默模式标志
- `"122,202p"`: sed 命令（打印 122-202 行）
- `"hello.txt"`: 输入文件

**策略匹配**:
- `-n` 被识别为 `MatchedFlag`
- `"122,202p"` 被识别为 `ArgType::SedCommand`
- `"hello.txt"` 被识别为 `ArgType::ReadableFile`

注意参数索引：`-n` 是索引 0，`"122,202p"` 是索引 1，`"hello.txt"` 是索引 2。

#### test_sed_print_specific_lines_with_e_flag

```rust
#[test]
fn test_sed_print_specific_lines_with_e_flag() -> Result<()> {
    let policy = setup();
    let sed = ExecCall::new("sed", &["-n", "-e", "122,202p", "hello.txt"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "sed".to_string(),
                flags: vec![MatchedFlag::new("-n")],
                opts: vec![
                    MatchedOpt::new("-e", "122,202p", ArgType::SedCommand)
                        .expect("should validate")
                ],
                args: vec![MatchedArg::new(3, ArgType::ReadableFile, "hello.txt")?],
                system_path: vec!["/usr/bin/sed".to_string()],
            }
        }),
        policy.check(&sed)
    );
    Ok(())
}
```

**与无 `-e` 版本的区别**:
- sed 命令 `"122,202p"` 作为 `-e` 选项的值，而非位置参数
- 使用 `MatchedOpt` 而非 `MatchedArg` 表示
- 文件参数索引变为 3（因为 `-n`, `-e`, `122,202p` 占据索引 0-2）

**策略配置**:
```python
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

#### test_sed_reject_dangerous_command

```rust
#[test]
fn test_sed_reject_dangerous_command() {
    let policy = setup();
    let sed = ExecCall::new("sed", &["-e", "s/y/echo hi/e", "hello.txt"]);
    assert_eq!(
        Err(Error::SedCommandNotProvablySafe {
            command: "s/y/echo hi/e".to_string(),
        }),
        policy.check(&sed)
    );
}
```

**危险命令分析**:
- `s/y/echo hi/e`: 替换命令，使用 `e` 标志
- `e` 标志的含义：将替换结果作为 shell 命令执行
- 攻击示例：`yes | sed 's/y/echo hi/e'` 会执行 `echo hi` 多次

**安全限制**:
```rust
// src/sed_command.rs
pub fn parse_sed_command(sed_command: &str) -> Result<()> {
    // 仅支持 "122,202p" 格式
    if let Some(stripped) = sed_command.strip_suffix("p")
        && let Some((first, rest)) = stripped.split_once(",")
        && first.parse::<u64>().is_ok()
        && rest.parse::<u64>().is_ok()
    {
        return Ok(());
    }
    Err(Error::SedCommandNotProvablySafe { ... })
}
```

#### test_sed_verify_e_or_pattern_is_required

```rust
#[test]
fn test_sed_verify_e_or_pattern_is_required() {
    let policy = setup();
    let sed = ExecCall::new("sed", &["122,202p"]);
    assert_eq!(
        Err(Error::MissingRequiredOptions {
            program: "sed".to_string(),
            options: vec!["-e".to_string()],
        }),
        policy.check(&sed)
    );
}
```

**策略背景**:
```python
# When -e is not specified, the first argument must be a valid sed command.
define_program(
    program="sed",
    options=common_sed_flags,
    args=[ARG_SED_COMMAND, ARG_RFILES],
    system_path=sed_system_path,
)

# When -e is required...
define_program(
    program="sed",
    options=common_sed_flags + [
        opt("-e", ARG_SED_COMMAND, required=True),
    ],
    args=[ARG_RFILES],
    ...
)
```

注意：测试使用第二个策略定义（`-e` 为必需），因此不带 `-e` 的调用被拒绝。

## 关键代码路径与文件引用

### 策略选择流程

```
policy.check(ExecCall::new("sed", &["122,202p"]))
    └── 查找 "sed" 的 ProgramSpec 列表
    ├── 第一个定义: args=[ARG_SED_COMMAND, ARG_RFILES]
    │   └── 尝试匹配
    │       └── 解析 "122,202p" 为 ARG_SED_COMMAND
    │       └── 需要更多参数（ARG_RFILES 未满足）
    │       └── 失败
    └── 第二个定义: options=[..., opt("-e", ..., required=True)], args=[ARG_RFILES]
        └── 尝试匹配
            └── 解析 "122,202p" 为普通参数
            └── 检查必需选项: -e 未提供
            └── Error::MissingRequiredOptions
```

### 核心类型

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `ArgType::SedCommand` | `src/arg_type.rs` | sed 命令参数类型 |
| `MatchedOpt` | `src/valid_exec.rs` | 匹配成功的选项 |
| `Opt::required` | `src/opt.rs` | 选项是否必需 |
| `Error::MissingRequiredOptions` | `src/error.rs` | 缺少必需选项错误 |
| `Error::SedCommandNotProvablySafe` | `src/error.rs` | 不安全 sed 命令错误 |

### 必需选项检查

位于 `src/program.rs`:

```rust
// Verify all required options are present.
let matched_opt_names: HashSet<String> = matched_opts
    .iter()
    .map(|opt| opt.name().to_string())
    .collect();
if !matched_opt_names.is_superset(&self.required_options) {
    let mut options = self.required_options
        .difference(&matched_opt_names)
        .map(String::from)
        .collect::<Vec<_>>();
    options.sort();
    return Err(Error::MissingRequiredOptions {
        program: self.program.clone(),
        options,
    });
}
```

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::ArgType;
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedArg;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::MatchedFlag;
use codex_execpolicy_legacy::MatchedOpt;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::Result;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

### 策略配置

```python
common_sed_flags = [
    flag("-n"),
    flag("-u"),
]
sed_system_path = ["/usr/bin/sed"]

# 策略 1: 第一个参数是 sed 命令
define_program(
    program="sed",
    options=common_sed_flags,
    args=[ARG_SED_COMMAND, ARG_RFILES],
    system_path=sed_system_path,
)

# 策略 2: -e 选项指定 sed 命令
define_program(
    program="sed",
    options=common_sed_flags + [
        opt("-e", ARG_SED_COMMAND, required=True),
    ],
    args=[ARG_RFILES],
    system_path=sed_system_path,
)
```

## 风险、边界与改进建议

### 当前风险

1. **过度限制**: 仅支持 `122,202p` 格式，许多合法的 sed 用法被拒绝
2. **策略歧义**: 两个 `sed` 定义可能导致意外的策略选择
3. **未测试的选项**: `-u` (unbuffered) 选项未在测试中覆盖
4. **多 `-e` 选项**: 未测试多个 `-e` 选项的场景

### 边界情况

1. **空命令**: `sed -e ""` 的处理
2. **多文件**: `sed -n "1p" file1 file2` 的处理
3. **命令顺序**: `-e` 与其他选项的顺序

### 改进建议

1. **增加 `-u` 选项测试**:
   ```rust
   #[test]
   fn test_sed_unbuffered_flag() -> Result<()> {
       let policy = setup();
       let sed = ExecCall::new("sed", &["-u", "-n", "1p", "file.txt"]);
       // 验证 -u 被正确识别
       Ok(())
   }
   ```

2. **增加多 `-e` 选项测试**:
   ```rust
   #[test]
   fn test_sed_multiple_e_flags() -> Result<()> {
       let policy = setup();
       let sed = ExecCall::new("sed", &["-e", "1p", "-e", "2p", "file.txt"]);
       // 验证多个 -e 选项
       Ok(())
   }
   ```

3. **增加多文件测试**:
   ```rust
   #[test]
   fn test_sed_multiple_files() -> Result<()> {
       let policy = setup();
       let sed = ExecCall::new("sed", &["-n", "1p", "file1.txt", "file2.txt"]);
       // 验证多文件处理
       Ok(())
   }
   ```

4. **扩展安全命令格式**:
   ```rust
   // src/sed_command.rs
   pub fn parse_sed_command(sed_command: &str) -> Result<()> {
       // 现有：行范围打印
       if is_range_print(sed_command) {
           return Ok(());
       }
       
       // 新增：单行打印
       if is_single_line_print(sed_command) {
           return Ok(());
       }
       
       // 新增：删除命令（仅行范围）
       if is_range_delete(sed_command) {
           return Ok(());
       }
       
       Err(Error::SedCommandNotProvablySafe { ... })
   }
   ```

5. **增加明确的安全注释**:
   ```rust
   /// SECURITY: This parser is intentionally restrictive.
   /// Only a whitelist of known-safe sed commands are accepted.
   /// Any command not matching the whitelist is rejected.
   pub fn parse_sed_command(sed_command: &str) -> Result<()> { ... }
   ```

6. **考虑策略合并**: 两个 `sed` 定义可能导致混淆，考虑是否可以通过更灵活的参数模式合并为一个定义
