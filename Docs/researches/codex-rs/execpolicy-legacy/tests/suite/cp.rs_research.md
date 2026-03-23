# cp.rs 研究文档

## 场景与职责

`cp.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试 `cp` (复制文件) 命令的策略验证逻辑。`cp` 是一个具有**破坏性潜力**的命令（会覆盖目标文件），因此其策略定义需要精确控制参数模式，确保安全使用。

## 功能点目的

### 1. 参数数量验证

确保 `cp` 命令必须至少有两个参数：
- 源文件（一个或多个）
- 目标文件（一个）

### 2. 参数类型验证

验证策略正确识别：
- 源文件参数为 `ReadableFile` 类型
- 目标文件参数为 `WriteableFile` 类型

### 3. 递归复制选项支持

验证策略允许 `-r`, `-R`, `--recursive` 选项用于目录复制。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `test_cp_no_args` | 验证无参数调用被拒绝 | `NotEnoughArgs` 错误 |
| `test_cp_one_arg` | 验证单参数调用被拒绝 | `VarargMatcherDidNotMatchAnything` 错误 |
| `test_cp_one_file` | 验证标准两参数调用 | `MatchedExec::Match` 成功 |
| `test_cp_multiple_files` | 验证多源文件复制 | `MatchedExec::Match` 成功 |

### 详细测试分析

#### test_cp_no_args

```rust
#[test]
fn test_cp_no_args() {
    let policy = setup();
    let cp = ExecCall::new("cp", &[]);
    assert_eq!(
        Err(Error::NotEnoughArgs {
            program: "cp".to_string(),
            args: vec![],
            arg_patterns: vec![ArgMatcher::ReadableFiles, ArgMatcher::WriteableFile]
        }),
        policy.check(&cp)
    )
}
```

**策略配置** (`default.policy`):
```python
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],  # 至少一个可读文件 + 一个可写文件
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[["foo", "bar"]],
    should_not_match=[["foo"]],  # 只有一个参数应该被拒绝
)
```

错误类型 `NotEnoughArgs` 在参数解析阶段产生，当实际参数数量无法满足 `arg_patterns` 要求时触发。

#### test_cp_one_arg

```rust
#[test]
fn test_cp_one_arg() {
    let policy = setup();
    let cp = ExecCall::new("cp", &["foo/bar"]);
    assert_eq!(
        Err(Error::VarargMatcherDidNotMatchAnything {
            program: "cp".to_string(),
            matcher: ArgMatcher::ReadableFiles,
        }),
        policy.check(&cp)
    );
}
```

这里验证当只有一个参数时，`ARG_RFILES` (ReadableFiles) 匹配器因需要至少一个文件而失败。

#### test_cp_one_file

```rust
#[test]
fn test_cp_one_file() -> Result<()> {
    let policy = setup();
    let cp = ExecCall::new("cp", &["foo/bar", "../baz"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new(
                "cp",
                vec![
                    MatchedArg::new(0, ArgType::ReadableFile, "foo/bar")?,
                    MatchedArg::new(1, ArgType::WriteableFile, "../baz")?,
                ],
                &["/bin/cp", "/usr/bin/cp"]
            )
        }),
        policy.check(&cp)
    );
    Ok(())
}
```

成功匹配的返回结构：
- `MatchedExec::Match`: 表示策略检查通过
- `ValidExec`: 包含验证后的执行信息
  - `program`: "cp"
  - `args`: 两个 `MatchedArg`，分别标记为 `ReadableFile` 和 `WriteableFile`
  - `system_path`: 建议的系统路径优先级列表

#### test_cp_multiple_files

```rust
#[test]
fn test_cp_multiple_files() -> Result<()> {
    let policy = setup();
    let cp = ExecCall::new("cp", &["foo", "bar", "baz"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec::new(
                "cp",
                vec![
                    MatchedArg::new(0, ArgType::ReadableFile, "foo")?,
                    MatchedArg::new(1, ArgType::ReadableFile, "bar")?,
                    MatchedArg::new(2, ArgType::WriteableFile, "baz")?,
                ],
                &["/bin/cp", "/usr/bin/cp"]
            )
        }),
        policy.check(&cp)
    );
    Ok(())
}
```

多文件复制场景：前两个参数被识别为 `ReadableFile`，最后一个被识别为 `WriteableFile`。这符合 `cp` 的语义：多个源文件复制到最后一个目标（必须是目录）。

### 参数解析流程

```
ExecCall::new("cp", &["foo", "bar", "baz"])
    └── policy.check(&cp)
        └── 查找 "cp" 的 ProgramSpec
        └── 解析选项 (无)
        └── resolve_observed_args_with_patterns()
            ├── 前缀匹配: ARG_RFILES (ReadableFiles) - 匹配 "foo", "bar"
            └── 后缀匹配: ARG_WFILE (WriteableFile) - 匹配 "baz"
        └── 返回 MatchedExec::Match
```

## 关键代码路径与文件引用

### 核心类型和函数

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `ExecCall` | `src/exec_call.rs` | 表示程序调用请求 |
| `Policy::check` | `src/policy.rs` | 主策略检查入口 |
| `ProgramSpec::check` | `src/program.rs` | 程序级别检查 |
| `ArgMatcher::ReadableFiles` | `src/arg_matcher.rs` | 匹配一个或多个可读文件 |
| `ArgMatcher::WriteableFile` | `src/arg_matcher.rs` | 匹配单个可写文件 |
| `MatchedExec` | `src/program.rs` | 匹配结果枚举 |
| `ValidExec` | `src/valid_exec.rs` | 验证通过的执行定义 |
| `MatchedArg` | `src/valid_exec.rs` | 匹配成功的参数 |

### 参数匹配器基数 (Cardinality)

```rust
// src/arg_matcher.rs
pub enum ArgMatcherCardinality {
    One,           // 匹配恰好一个参数
    AtLeastOne,    // 匹配至少一个参数 (ReadableFiles)
    ZeroOrMore,    // 匹配零个或多个参数
}
```

`ReadableFiles` 的基数是 `AtLeastOne`，`WriteableFile` 的基数是 `One`。

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::ArgMatcher;
use codex_execpolicy_legacy::ArgType;
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedArg;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::Result;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

### 策略配置

`default.policy` 中的 `cp` 定义：
```python
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[["foo", "bar"]],
    should_not_match=[["foo"]],
)
```

## 风险、边界与改进建议

### 当前风险

1. **路径遍历风险**: 测试用例使用 `"../baz"` 作为目标路径，策略仅验证参数类型，不验证路径是否在允许范围内
2. **目录复制验证不足**: 测试未覆盖 `-r` 选项的实际使用
3. **覆盖风险**: `cp` 会静默覆盖目标文件，策略未提供覆盖保护机制

### 边界情况

1. **符号链接**: 策略不区分普通文件和符号链接
2. **特殊文件**: 设备文件、管道等特殊文件类型未特殊处理
3. **递归深度**: 无限制递归复制的风险控制

### 改进建议

1. **增加递归选项测试**:
   ```rust
   #[test]
   fn test_cp_recursive() -> Result<()> {
       let policy = setup();
       let cp = ExecCall::new("cp", &["-r", "src_dir", "dest_dir"]);
       // 验证 -r 选项被正确识别
       Ok(())
   }
   ```

2. **增加路径验证测试**: 测试策略对绝对路径、相对路径、包含 `..` 的路径的处理

3. **安全增强建议**:
   - 考虑添加 `--backup` 选项的自动要求
   - 对覆盖现有文件的操作增加额外确认机制
   - 限制可写目标路径的范围（如必须在特定目录下）

4. **错误消息改进**: 当前错误类型较为通用，可提供更具体的上下文信息
