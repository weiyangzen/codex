# program.rs 研究文档

## 场景与职责

`program.rs` 是执行策略引擎中程序规则的核心实现，负责：

1. **程序规范定义**：`ProgramSpec` 结构定义单个程序的策略规则
2. **命令验证**：检查执行调用是否符合程序规则
3. **选项解析**：解析命令行选项（flags 和 opts）
4. **位置参数匹配**：将剩余参数与 ArgMatcher 模式匹配
5. **示例验证**：验证 should_match 和 should_not_match 示例

该模块实现了策略验证的核心算法，是 `Policy::check()` 的实际执行者。

## 功能点目的

### 1. ProgramSpec 结构

```rust
pub struct ProgramSpec {
    pub program: String,                    // 程序名
    pub system_path: Vec<String>,           // 推荐的可执行路径
    pub option_bundling: bool,              // 是否支持选项捆绑（未实现）
    pub combined_format: bool,              // 是否支持 --opt=value（未实现）
    pub allowed_options: HashMap<String, Opt>, // 允许的选项
    pub arg_patterns: Vec<ArgMatcher>,      // 位置参数模式
    forbidden: Option<String>,              // 禁止原因（如果设置）
    required_options: HashSet<String>,      // 必需选项集合
    should_match: Vec<Vec<String>>,         // 应该匹配的示例
    should_not_match: Vec<Vec<String>>,     // 不应该匹配的示例
}
```

### 2. MatchedExec 枚举

表示验证结果：
```rust
pub enum MatchedExec {
    Match { exec: ValidExec },              // 匹配成功
    Forbidden { cause: Forbidden, reason: String },  // 被禁止
}
```

### 3. Forbidden 枚举

表示禁止的原因：
```rust
pub enum Forbidden {
    Program { program: String, exec_call: ExecCall },  // 程序被禁止
    Arg { arg: String, exec_call: ExecCall },          // 参数被禁止
    Exec { exec: ValidExec },                          // 执行被禁止
}
```

### 4. 检查流程

**ProgramSpec::check()**：
1. 遍历参数，解析选项
2. 收集位置参数
3. 验证必需选项
4. 解析位置参数（调用 arg_resolver）
5. 构建 ValidExec
6. 检查是否被禁止

## 具体技术实现

### 构造函数

```rust
impl ProgramSpec {
    pub fn new(
        program: String,
        system_path: Vec<String>,
        option_bundling: bool,
        combined_format: bool,
        allowed_options: HashMap<String, Opt>,
        arg_patterns: Vec<ArgMatcher>,
        forbidden: Option<String>,
        should_match: Vec<Vec<String>>,
        should_not_match: Vec<Vec<String>>,
    ) -> Self {
        // 从 allowed_options 提取 required_options
        let required_options = allowed_options
            .iter()
            .filter_map(|(name, opt)| {
                if opt.required { Some(name.clone()) } else { None }
            })
            .collect();
        
        Self { ... }
    }
}
```

### 选项解析

```rust
pub fn check(&self, exec_call: &ExecCall) -> Result<MatchedExec> {
    let mut expecting_option_value: Option<(String, ArgType)> = None;
    let mut args = Vec::<PositionalArg>::new();
    let mut matched_flags = Vec::<MatchedFlag>::new();
    let mut matched_opts = Vec::<MatchedOpt>::new();

    for (index, arg) in exec_call.args.iter().enumerate() {
        if let Some(expected) = expecting_option_value {
            // 期望选项值
            if arg.starts_with("-") {
                return Err(Error::OptionFollowedByOptionInsteadOfValue { ... });
            }
            matched_opts.push(MatchedOpt::new(&name, arg, arg_type)?);
            expecting_option_value = None;
        } else if arg == "--" {
            return Err(Error::DoubleDashNotSupportedYet { ... });
        } else if arg.starts_with("-") {
            // 解析选项
            match self.allowed_options.get(arg) {
                Some(opt) => {
                    match &opt.meta {
                        OptMeta::Flag => {
                            matched_flags.push(MatchedFlag { name: arg.clone() });
                            continue;
                        }
                        OptMeta::Value(arg_type) => {
                            expecting_option_value = Some((arg.clone(), arg_type.clone()));
                            continue;
                        }
                    }
                }
                None => return Err(Error::UnknownOption { ... }),
            }
        } else {
            // 位置参数
            args.push(PositionalArg { index, value: arg.clone() });
        }
    }
    
    // 检查是否有未完成的选项值
    if let Some(expected) = expecting_option_value {
        return Err(Error::OptionMissingValue { ... });
    }
    
    // ... 继续处理
}
```

### 必需选项验证

```rust
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
    return Err(Error::MissingRequiredOptions { ... });
}
```

### 禁止检查

```rust
let exec = ValidExec { ... };

match &self.forbidden {
    Some(reason) => Ok(MatchedExec::Forbidden {
        cause: Forbidden::Exec { exec },
        reason: reason.clone(),
    }),
    None => Ok(MatchedExec::Match { exec }),
}
```

### 示例验证

```rust
pub fn verify_should_match_list(&self) -> Vec<PositiveExampleFailedCheck> {
    let mut violations = Vec::new();
    for good in &self.should_match {
        let exec_call = ExecCall {
            program: self.program.clone(),
            args: good.clone(),
        };
        if let Err(error) = self.check(&exec_call) {
            violations.push(PositiveExampleFailedCheck { ... });
        }
    }
    violations
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/program.rs`

### 依赖文件
- `codex-rs/execpolicy-legacy/src/arg_matcher.rs`：ArgMatcher
- `codex-rs/execpolicy-legacy/src/arg_resolver.rs`：PositionalArg, resolve_observed_args_with_patterns
- `codex-rs/execpolicy-legacy/src/error.rs`：Error, Result
- `codex-rs/execpolicy-legacy/src/opt.rs`：Opt, OptMeta
- `codex-rs/execpolicy-legacy/src/valid_exec.rs`：ValidExec, MatchedFlag, MatchedOpt
- `codex-rs/execpolicy-legacy/src/exec_call.rs`：ExecCall

### 被依赖文件
- `codex-rs/execpolicy-legacy/src/policy.rs`：Policy 调用 ProgramSpec::check()
- `codex-rs/execpolicy-legacy/src/lib.rs`：公开类型

### 验证流程

```
Policy::check(exec_call)
  └── 查找 ProgramSpec 列表
      └── ProgramSpec::check(exec_call)
          ├── 选项解析循环
          │   ├── Flag -> matched_flags
          │   ├── Opt with value -> expecting_option_value
          │   └── PositionalArg -> args
          ├── 检查 expecting_option_value（OptionMissingValue）
          ├── resolve_observed_args_with_patterns()
          │   └── 返回 MatchedArg 列表
          ├── 验证 required_options
          ├── 构建 ValidExec
          └── 检查 forbidden
              ├── Some(reason) -> MatchedExec::Forbidden
              └── None -> MatchedExec::Match
```

## 依赖与外部交互

### 标准库
- `std::collections::{HashMap, HashSet}`

### 外部 crate
- `serde::Serialize`

### 内部依赖
- `ArgMatcher`, `ArgType`
- `PositionalArg`, `resolve_observed_args_with_patterns`
- `Opt`, `OptMeta`
- `ValidExec`, `MatchedFlag`, `MatchedOpt`, `MatchedArg`
- `ExecCall`, `Error`

## 风险、边界与改进建议

### 风险点

1. **选项值解析歧义**
   ```rust
   // head -n -1 file
   // -1 被解析为选项而非数值
   // -> OptionFollowedByOptionInsteadOfValue
   ```

2. **-- 不支持**
   ```rust
   // rm -- -file
   // -> DoubleDashNotSupportedYet
   ```

3. **选项捆绑未实现**
   ```rust
   // ls -al
   // -> UnknownOption { option: "-al" }
   ```

4. **= 格式不支持**
   ```rust
   // head -n=10 file
   // 当前不支持
   ```

5. **标志后文件参数**
   ```rust
   // ls file -l
   // 当前允许，但某些命令不允许
   ```

### 边界情况

1. **空参数列表**
   ```rust
   // 程序无参数调用
   // 由 arg_patterns 决定（可能允许或拒绝）
   ```

2. **未知选项**
   ```rust
   // 遇到未在 allowed_options 中定义的选项
   // -> UnknownOption
   ```

3. **选项值缺失**
   ```rust
   // head -n（无值）
   // -> OptionMissingValue
   ```

4. **必需选项缺失**
   ```rust
   // sed 122,202p file（缺少 -e）
   // -> MissingRequiredOptions
   ```

### 改进建议

1. **实现 -- 支持**
   ```rust
   } else if arg == "--" {
       // 剩余所有参数都作为位置参数
       for remaining in &exec_call.args[index+1..] {
           args.push(PositionalArg { index, value: remaining.clone() });
       }
       break;
   }
   ```

2. **实现选项捆绑**
   ```rust
   // 如果 option_bundling 为 true
   if arg.starts_with("-") && arg.len() > 2 && !arg.starts_with("--") {
       for c in arg[1..].chars() {
           let flag = format!("-{c}");
           // 检查每个字符是否为有效 flag
       }
   }
   ```

3. **实现 = 格式**
   ```rust
   if let Some((name, value)) = arg.split_once('=') {
       // 处理 --opt=value 格式
   }
   ```

4. **改进错误信息**
   ```rust
   UnknownOption {
       program: String,
       option: String,
       similar: Vec<String>, // 建议相似的选项
   }
   ```

5. **支持选项位置限制**
   ```rust
   pub struct ProgramSpec {
       // ...
       flags_before_args: bool,  // 标志是否必须在参数前
   }
   ```

6. **测试覆盖**
   - 添加边界值测试
   - 添加复杂选项组合测试
   - 添加错误恢复测试
