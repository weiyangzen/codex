# pwd.rs 研究文档

## 场景与职责

`pwd.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，专门测试 `pwd` (打印工作目录) 命令的策略验证逻辑。`pwd` 是一个非常安全的只读命令，不接受文件参数，因此其策略相对简单。

## 功能点目的

### 1. 无参数调用验证

验证 `pwd` 最基本的用法（不带任何参数）被策略接受。

### 2. 标准选项支持

验证策略支持 `pwd` 的两个标准选项：
- `-L`: 打印逻辑当前目录（包含符号链接）
- `-P`: 打印物理当前目录（解析所有符号链接）

### 3. 额外参数拒绝

验证 `pwd` 不接受任何位置参数，任何额外参数都应被拒绝。

## 具体技术实现

### 测试用例概览

| 测试函数 | 目的 | 预期结果 |
|---------|------|---------|
| `test_pwd_no_args` | 验证无参数调用 | `MatchedExec::Match` 成功 |
| `test_pwd_capital_l` | 验证 `-L` 选项 | `MatchedExec::Match` 成功 |
| `test_pwd_capital_p` | 验证 `-P` 选项 | `MatchedExec::Match` 成功 |
| `test_pwd_extra_args` | 验证额外参数被拒绝 | `UnexpectedArguments` 错误 |

### 详细测试分析

#### test_pwd_no_args

```rust
#[test]
fn test_pwd_no_args() {
    let policy = setup();
    let pwd = ExecCall::new("pwd", &[]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "pwd".into(),
                ..Default::default()
            }
        }),
        policy.check(&pwd)
    );
}
```

**策略配置** (`default.policy`):
```python
# Note that `pwd` is generally implemented as a shell built-in. It does not
# accept any arguments.
define_program(
    program="pwd",
    options=[
        flag("-L"),
        flag("-P"),
    ],
    args=[],
)
```

注意：策略注释提到 `pwd` 通常是 shell 内置命令，不接受任何参数。

成功匹配使用 `..Default::default()` 填充 `ValidExec` 的其他字段：
- `flags`: 空向量
- `opts`: 空向量
- `args`: 空向量
- `system_path`: 空向量（策略未指定）

#### test_pwd_capital_l

```rust
#[test]
fn test_pwd_capital_l() {
    let policy = setup();
    let pwd = ExecCall::new("pwd", &["-L"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "pwd".into(),
                flags: vec![MatchedFlag::new("-L")],
                ..Default::default()
            }
        }),
        policy.check(&pwd)
    );
}
```

验证 `-L` 选项被正确识别为 `MatchedFlag`。

#### test_pwd_capital_p

```rust
#[test]
fn test_pwd_capital_p() {
    let policy = setup();
    let pwd = ExecCall::new("pwd", &["-P"]);
    assert_eq!(
        Ok(MatchedExec::Match {
            exec: ValidExec {
                program: "pwd".into(),
                flags: vec![MatchedFlag::new("-P")],
                ..Default::default()
            }
        }),
        policy.check(&pwd)
    );
}
```

验证 `-P` 选项被正确识别。

#### test_pwd_extra_args

```rust
#[test]
fn test_pwd_extra_args() {
    let policy = setup();
    let pwd = ExecCall::new("pwd", &["foo", "bar"]);
    assert_eq!(
        Err(Error::UnexpectedArguments {
            program: "pwd".to_string(),
            args: vec![
                PositionalArg {
                    index: 0,
                    value: "foo".to_string()
                },
                PositionalArg {
                    index: 1,
                    value: "bar".to_string()
                },
            ],
        }),
        policy.check(&pwd)
    );
}
```

验证额外参数被拒绝，错误包含详细的参数信息：
- `program`: 程序名称
- `args`: 意外的位置参数列表，包含索引和值

### 参数解析流程

```
ExecCall::new("pwd", &["foo", "bar"])
    └── ProgramSpec::check()
        ├── 解析 "foo":
        │   └── 不以 "-" 开头
        │   └── args.push(PositionalArg { index: 0, value: "foo" })
        ├── 解析 "bar":
        │   └── args.push(PositionalArg { index: 1, value: "bar" })
        └── resolve_observed_args_with_patterns(args, [])
            └── 策略 args=[] 为空
            └── 所有位置参数都是意外的
            └── Error::UnexpectedArguments
```

## 关键代码路径与文件引用

### 核心类型

| 名称 | 定义位置 | 用途 |
|------|---------|------|
| `ValidExec` | `src/valid_exec.rs` | 验证通过的执行定义 |
| `MatchedFlag` | `src/valid_exec.rs` | 匹配成功的标志 |
| `PositionalArg` | `src/arg_resolver.rs` | 位置参数结构 |
| `Error::UnexpectedArguments` | `src/error.rs` | 意外参数错误 |

### ValidExec 结构

```rust
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct ValidExec {
    pub program: String,
    pub flags: Vec<MatchedFlag>,
    pub opts: Vec<MatchedOpt>,
    pub args: Vec<MatchedArg>,
    pub system_path: Vec<String>,
}
```

`ValidExec` 实现了 `Default` trait，允许使用 `..Default::default()` 快速创建实例。

### 空参数模式

`pwd` 的策略定义 `args=[]` 表示不接受任何位置参数。这与 `ARG_RFILES_OR_CWD`（零个或多个文件）不同：

| 程序 | args 配置 | 含义 |
|------|----------|------|
| `pwd` | `[]` | 不接受任何位置参数 |
| `ls` | `[ARG_RFILES_OR_CWD]` | 接受零个或多个文件 |
| `cp` | `[ARG_RFILES, ARG_WFILE]` | 至少一个源文件 + 一个目标文件 |

## 依赖与外部交互

### 测试依赖

```rust
use codex_execpolicy_legacy::Error;
use codex_execpolicy_legacy::ExecCall;
use codex_execpolicy_legacy::MatchedExec;
use codex_execpolicy_legacy::MatchedFlag;
use codex_execpolicy_legacy::Policy;
use codex_execpolicy_legacy::PositionalArg;
use codex_execpolicy_legacy::ValidExec;
use codex_execpolicy_legacy::get_default_policy;
```

注意：此测试导入了 `PositionalArg`，因为 `Error::UnexpectedArguments` 包含 `Vec<PositionalArg>`。

### 策略配置

```python
define_program(
    program="pwd",
    options=[
        flag("-L"),
        flag("-P"),
    ],
    args=[],
)
```

注意：策略未指定 `system_path`，因此 `ValidExec.system_path` 为空。

## 风险、边界与改进建议

### 当前风险

1. **shell 内置命令处理**: 注释提到 `pwd` 通常是 shell 内置命令，但策略未特别处理内置命令与外部命令的区别
2. **选项组合未测试**: 未测试 `-L` 和 `-P` 同时使用的情况（虽然通常无意义）
3. **无效选项**: 未测试其他选项（如 `-h`）的拒绝

### 边界情况

1. **互斥选项**: `-L` 和 `-P` 在逻辑上互斥，但策略允许同时使用
2. **重复选项**: 未测试同一选项多次使用（如 `pwd -L -L`）
3. **大小写敏感**: 策略定义大写选项，未涉及小写变体

### 改进建议

1. **增加互斥选项测试**:
   ```rust
   #[test]
   fn test_pwd_both_flags() {
       let policy = setup();
       let pwd = ExecCall::new("pwd", &["-L", "-P"]);
       // 验证是否接受或拒绝同时使用
       // 实际行为：当前策略接受
   }
   ```

2. **增加无效选项测试**:
   ```rust
   #[test]
   fn test_pwd_invalid_flag() {
       let policy = setup();
       let pwd = ExecCall::new("pwd", &["-h"]);
       assert_eq!(
           Err(Error::UnknownOption { ... }),
           policy.check(&pwd)
       );
   }
   ```

3. **考虑内置命令特殊处理**:
   ```python
   define_program(
       program="pwd",
       is_shell_builtin=True,  #  hypothetical
       ...
   )
   ```

4. **增加选项组合测试**:
   ```rust
   #[test]
   fn test_pwd_flag_combinations() -> Result<()> {
       let policy = setup();
       
       // 仅 -L
       let pwd_l = ExecCall::new("pwd", &["-L"]);
       assert!(policy.check(&pwd_l).is_ok());
       
       // 仅 -P
       let pwd_p = ExecCall::new("pwd", &["-P"]);
       assert!(policy.check(&pwd_p).is_ok());
       
       // -L -P
       let pwd_lp = ExecCall::new("pwd", &["-L", "-P"]);
       assert!(policy.check(&pwd_lp).is_ok());
       
       // -P -L
       let pwd_pl = ExecCall::new("pwd", &["-P", "-L"]);
       assert!(policy.check(&pwd_pl).is_ok());
       
       Ok(())
   }
   ```

5. **system_path 考虑**: 虽然 `pwd` 通常是内置命令，但可考虑添加常见外部实现路径：
   ```python
   define_program(
       program="pwd",
       system_path=["/bin/pwd", "/usr/bin/pwd"],
       ...
   )
   ```
