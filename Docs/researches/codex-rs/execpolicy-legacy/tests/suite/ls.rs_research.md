# ls.rs 研究文档

## 场景与职责

`ls.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试 `ls` (列出目录内容) 命令的策略验证逻辑。`ls` 是一个高频使用的只读命令，具有多个常用选项（如 `-a`, `-l`）和灵活的参数模式。

## 功能点目的

### 1. 无参数调用支持

验证 `ls` 不带参数时能够正常工作（列出当前目录）。

### 2. 选项验证

验证策略正确识别和处理：
- 有效选项：`-a`, `-l`, `-1`
- 无效选项：如 `-z`

### 3. 选项捆绑 (Option Bundling) 检测

验证当前策略对 `-al` 这样的捆绑选项的处理（当前拒绝，未来可能支持）。

### 4. 文件参数识别

验证非选项参数被正确识别为 `ReadableFile` 类型。

### 5. 选项位置灵活性

验证 `ls` 允许选项出现在文件参数之后（如 `ls foo -l`）。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `test_ls_no_args` | 验证无参数调用 | `MatchedExec::Match` 成功 |
| `test_ls_dash_a_dash_l` | 验证多个有效选项 | `MatchedExec::Match` 成功 |
| `test_ls_dash_z` | 验证无效选项被拒绝 | `UnknownOption` 错误 |
| `test_ls_dash_al` | 验证捆绑选项当前被拒绝 | `UnknownOption` 错误 |
| `test_ls_one_file_arg` | 验证单文件参数 | `MatchedExec::Match` 成功 |
| `test_ls_multiple_file_args` | 验证多文件参数 | `MatchedExec::Match` 成功 |
| `test_ls_multiple_flags_and_file_args` | 验证选项与文件混合 | `MatchedExec::Match` 成功 |
| `test_flags_after_file_args` | 验证选项在文件后 | `MatchedExec::Match` 成功 |

### 详细测试分析

#### test_ls_no_args

```rust
#[test]
fn test_ls_no_args() {
    let policy = setup();
    let ls = ExecCall::new("ls", &[]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new("ls", vec![], &["/bin/ls", "/usr/bin/ls"])
        }),
        policy.check(&ls)
    );
}
```

**策略配置** (`default.policy`):
```python
define_program(
    program="ls",
    system_path=["/bin/ls", "/usr/bin/ls"],
    options=[
        flag("-1"),
        flag("-a"),
        flag("-l"),
    ],
    args=[ARG_RFILES_OR_CWD],  # 零个或多个可读文件，或隐含当前目录
)
```

`ARG_RFILES_OR_CWD` 的基数为 `ZeroOrMore`，允许空参数列表。

#### test_ls_dash_a_dash_l

```rust
#[test]
fn test_ls_dash_a_dash_l() {
    let policy = setup();
    let args = &["-a", "-l"];
    let ls_a_l = ExecCall::new("ls", args);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "ls".into(),
                flags: vec![MatchedFlag::new("-a"), MatchedFlag::new("-l")],
                system_path: ["/bin/ls".into(), "/usr/bin/ls".into()].into(),
                ..Default::default()
            }
        }),
        policy.check(&ls_a_l)
    );
}
```

成功匹配返回：
- `flags`: 包含两个 `MatchedFlag` 条目
- `args`: 空（因为没有文件参数）
- 使用 `..Default::default()` 填充其余字段

#### test_ls_dash_z

```rust
#[test]
fn test_ls_dash_z() {
    let policy = setup();
    let ls_z = ExecCall::new("ls", &["-z"]);
    assert_eq!(
        Err(Error::UnknownOption {
            program: "ls".into(),
            option: "-z".into()
        }),
        policy.check(&ls_z)
    );
}
```

注释说明：`-z` 当前是无效选项，但 `ls` 有很多选项，未来可能被添加。

#### test_ls_dash_al (选项捆绑)

```rust
#[test]
fn test_ls_dash_al() {
    let policy = setup();
    let ls_al = ExecCall::new("ls", &["-al"]);
    assert_eq!(
        Err(Error::UnknownOption {
            program: "ls".into(),
            option: "-al".into()
        }),
        policy.check(&ls_al)
    );
}
```

注释说明：当前失败，但 `option_bundling=True` 实现后应该通过。

**策略定义中的选项捆绑**:
```python
define_program(
    program="ls",
    option_bundling=False,  # 当前未启用
    ...
)
```

#### test_ls_one_file_arg

```rust
#[test]
fn test_ls_one_file_arg() -> Result<()> {
    let policy = setup();
    let ls_one_file_arg = ExecCall::new("ls", &["foo"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new(
                "ls",
                vec![MatchedArg::new(0, ArgType::ReadableFile, "foo")?],
                &["/bin/ls", "/usr/bin/ls"]
            )
        }),
        policy.check(&ls_one_file_arg)
    );
    Ok(())
}
```

#### test_ls_multiple_file_args

```rust
#[test]
fn test_ls_multiple_file_args() -> Result<()> {
    let policy = setup();
    let ls_multiple_file_args = ExecCall::new("ls", &["foo", "bar", "baz"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new(
                "ls",
                vec![
                    MatchedArg::new(0, ArgType::ReadableFile, "foo")?,
                    MatchedArg::new(1, ArgType::ReadableFile, "bar")?,
                    MatchedArg::new(2, ArgType::ReadableFile, "baz")?,
                ],
                &["/bin/ls", "/usr/bin/ls"]
            )
        }),
        policy.check(&ls_multiple_file_args)
    );
    Ok(())
}
```

#### test_ls_multiple_flags_and_file_args

```rust
#[test]
fn test_ls_multiple_flags_and_file_args() -> Result<()> {
    let policy = setup();
    let ls_multiple_flags_and_file_args = ExecCall::new("ls", &["-l", "-a", "foo", "bar", "baz"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "ls".into(),
                flags: vec![MatchedFlag::new("-l"), MatchedFlag::new("-a")],
                args: vec![
                    MatchedArg::new(2, ArgType::ReadableFile, "foo")?,
                    MatchedArg::new(3, ArgType::ReadableFile, "bar")?,
                    MatchedArg::new(4, ArgType::ReadableFile, "baz")?,
                ],
                system_path: ["/bin/ls".into(), "/usr/bin/ls".into()].into(),
                ..Default::default()
            }
        }),
        policy.check(&ls_multiple_flags_and_file_args)
    );
    Ok(())
}
```

注意文件参数的索引从 2 开始（因为 `-l` 和 `-a` 占据了索引 0 和 1）。

#### test_flags_after_file_args

```rust
#[test]
fn test_flags_after_file_args() -> Result<()> {
    let policy = setup();
    let ls_flags_after_file_args = ExecCall::new("ls", &["foo", "-l"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "ls".into(),
                flags: vec![MatchedFlag::new("-l")],
                args: vec![MatchedArg::new(0, ArgType::ReadableFile, "foo")?],
                system_path: ["/bin/ls".into(), "/usr/bin/ls".into()].into(),
                ..Default::default()
            }
        }),
        policy.check(&ls_flags_after_file_args)
    );
    Ok(())
}
```

注释说明：虽然 `ls` 实际上不允许选项在文件参数之后，但策略当前接受此模式。TODO 提到应该扩展 `define_program()` 来配置此行为。

## 关键代码路径与文件引用

### 选项解析流程

```
ExecCall::new("ls", &["-l", "-a", "foo"])
    └── ProgramSpec::check()
        ├── 解析 "-l":
        │   └── 查找 allowed_options["-l"]
        │   └── 发现 OptMeta::Flag
        │   └── matched_flags.push(MatchedFlag("-l"))
        ├── 解析 "-a":
        │   └── 同上
        ├── 解析 "foo":
        │   └── args.push(PositionalArg { index: 2, value: "foo" })
        └── resolve_observed_args_with_patterns(args, [ARG_RFILES_OR_CWD])
            └── 匹配成功
```

### 核心类型

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `ArgMatcher::ReadableFilesOrCwd` | `src/arg_matcher.rs` | 匹配零个或多个可读文件 |
| `MatchedFlag` | `src/valid_exec.rs` | 匹配成功的标志 |
| `OptMeta::Flag` | `src/opt.rs` | 无值选项元数据 |
| `Error::UnknownOption` | `src/error.rs` | 未知选项错误 |

### 基数对比

| 匹配器 | 基数 | 说明 |
|--------|------|------|
| `ReadableFiles` | `AtLeastOne` | 至少一个文件 |
| `ReadableFilesOrCwd` | `ZeroOrMore` | 零个或多个文件 |

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::ArgType;
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedArg;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::MatchedFlag;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::Result;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

### 策略配置

```python
define_program(
    program="ls",
    system_path=["/bin/ls", "/usr/bin/ls"],
    options=[
        flag("-1"),
        flag("-a"),
        flag("-l"),
    ],
    args=[ARG_RFILES_OR_CWD],
)
```

## 风险、边界与改进建议

### 当前风险

1. **选项位置灵活性不一致**: 策略允许选项在文件后，但实际的 `ls` 命令可能不支持
2. **选项捆绑未实现**: `-al` 被拒绝，但用户可能期望它工作
3. **有限选项覆盖**: 仅支持 `-1`, `-a`, `-l`，其他常用选项如 `-h` (人类可读大小) 未包含

### 边界情况

1. **空目录**: `ARG_RFILES_OR_CWD` 允许空参数，隐含使用当前目录
2. **重复选项**: 测试未覆盖同一选项多次使用（如 `ls -l -l`）
3. **长选项**: 策略仅定义短选项，未涉及 `--all`, `--long` 等长选项

### 改进建议

1. **实现选项捆绑**:
   ```python
   define_program(
       program="ls",
       option_bundling=True,  # 启用 -al -> -a -l 解析
       ...
   )
   ```

2. **增加更多选项**:
   ```python
   options=[
       flag("-1"),
       flag("-a"),
       flag("-l"),
       flag("-h"),  # 人类可读格式
       flag("-t"),  # 按时间排序
       flag("-r"),  # 反向排序
       flag("-S"),  # 按大小排序
   ],
   ```

3. **选项位置配置**:
   ```python
   define_program(
       program="ls",
       allow_flags_after_args=False,  # 禁止选项在文件后
       ...
   )
   ```

4. **增加重复选项测试**:
   ```rust
   #[test]
   fn test_ls_duplicate_flags() {
       let policy = setup();
       let ls = ExecCall::new("ls", &["-l", "-l"]);
       // 验证行为（接受或拒绝）
   }
   ```

5. **长选项支持**:
   ```python
   options=[
       flag("-a"),
       flag("--all"),  # 长选项别名
       ...
   ],
   ```
