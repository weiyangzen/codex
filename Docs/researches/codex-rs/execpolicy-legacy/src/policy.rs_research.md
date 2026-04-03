# policy.rs 研究文档

## 场景与职责

`policy.rs` 定义了执行策略引擎的核心策略结构，负责：

1. **策略存储**：存储多个程序的规则和禁止模式
2. **命令匹配**：将执行调用与策略规则匹配
3. **禁止检查**：基于正则表达式和子字符串检查禁止的程序和参数
4. **策略验证**：验证策略中的示例列表（should_match/should_not_match）

该模块是策略引擎的入口点，协调各种检查逻辑。

## 功能点目的

### 1. Policy 结构

```rust
pub struct Policy {
    programs: MultiMap<String, ProgramSpec>,  // 程序名 -> 规则列表
    forbidden_program_regexes: Vec<ForbiddenProgramRegex>,  // 禁止的程序模式
    forbidden_substrings_pattern: Option<Regex>,  // 禁止的子字符串模式
}
```

**设计考量**：
- `MultiMap`：一个程序可以有多个规则（如 printenv 的无参数和单参数版本）
- `forbidden_program_regexes`：基于正则的程序名黑名单
- `forbidden_substrings_pattern`：基于子字符串的参数检查

### 2. 命令检查

**check() 方法**：
```rust
pub fn check(&self, exec_call: &ExecCall) -> Result<MatchedExec>
```

检查顺序：
1. 检查程序名是否匹配禁止的正则
2. 检查参数是否包含禁止的子字符串
3. 查找程序的规则列表
4. 按顺序尝试每个规则
5. 返回第一个成功的匹配或最后的错误

### 3. 禁止模式

**ForbiddenProgramRegex**：
```rust
pub struct ForbiddenProgramRegex {
    pub regex: regex_lite::Regex,
    pub reason: String,
}
```

**禁止子字符串**：
- 多个子字符串组合成一个正则表达式
- 使用 `regex_lite::escape` 转义特殊字符
- 格式：`("substring1"|"substring2"|...)`

### 4. 策略验证

**check_each_good_list_individually()**：
- 验证所有 `should_match` 示例确实匹配
- 返回未通过的检查列表

**check_each_bad_list_individually()**：
- 验证所有 `should_not_match` 示例确实不匹配
- 返回意外通过的检查列表

## 具体技术实现

### 构造函数

```rust
impl Policy {
    pub fn new(
        programs: MultiMap<String, ProgramSpec>,
        forbidden_program_regexes: Vec<ForbiddenProgramRegex>,
        forbidden_substrings: Vec<String>,
    ) -> std::result::Result<Self, RegexError> {
        let forbidden_substrings_pattern = if forbidden_substrings.is_empty() {
            None
        } else {
            let escaped_substrings = forbidden_substrings
                .iter()
                .map(|s| regex_lite::escape(s))
                .collect::<Vec<_>>()
                .join("|");
            Some(Regex::new(&format!("({escaped_substrings})"))?)
        };
        Ok(Self {
            programs,
            forbidden_program_regexes,
            forbidden_substrings_pattern,
        })
    }
}
```

### 检查实现

**程序名禁止检查**：
```rust
for ForbiddenProgramRegex { regex, reason } in &self.forbidden_program_regexes {
    if regex.is_match(program) {
        return Ok(MatchedExec::Forbidden {
            cause: Forbidden::Program {
                program: program.clone(),
                exec_call: exec_call.clone(),
            },
            reason: reason.clone(),
        });
    }
}
```

**参数子字符串检查**：
```rust
for arg in args {
    if let Some(regex) = &self.forbidden_substrings_pattern
        && regex.is_match(arg)
    {
        return Ok(MatchedExec::Forbidden {
            cause: Forbidden::Arg {
                arg: arg.clone(),
                exec_call: exec_call.clone(),
            },
            reason: format!("arg `{arg}` contains forbidden substring"),
        });
    }
}
```

**规则匹配**：
```rust
let mut last_err = Err(Error::NoSpecForProgram {
    program: program.clone(),
});
if let Some(spec_list) = self.programs.get_vec(program) {
    for spec in spec_list {
        match spec.check(exec_call) {
            Ok(matched_exec) => return Ok(matched_exec),
            Err(err) => {
                last_err = Err(err);
            }
        }
    }
}
last_err
```

### 验证实现

```rust
pub fn check_each_good_list_individually(&self) -> Vec<PositiveExampleFailedCheck> {
    let mut violations = Vec::new();
    for (_program, spec) in self.programs.flat_iter() {
        violations.extend(spec.verify_should_match_list());
    }
    violations
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/policy.rs`

### 依赖文件
- `codex-rs/execpolicy-legacy/src/exec_call.rs`：ExecCall
- `codex-rs/execpolicy-legacy/src/program.rs`：ProgramSpec, MatchedExec, Forbidden
- `codex-rs/execpolicy-legacy/src/policy_parser.rs`：ForbiddenProgramRegex
- `codex-rs/execpolicy-legacy/src/error.rs`：Error, Result

### 被依赖文件
- `codex-rs/execpolicy-legacy/src/execv_checker.rs`：ExecvChecker 包装 Policy
- `codex-rs/execpolicy-legacy/src/main.rs`：CLI 使用 Policy::check()
- `codex-rs/execpolicy-legacy/src/lib.rs`：公开 Policy
- `tests/suite/*.rs`：测试使用 Policy

### 调用流程

```
main.rs / 测试代码
  └── policy.check(&exec_call)
      ├── 检查禁止的程序正则
      ├── 检查禁止的子字符串
      └── 查找程序规则
          └── 对每个 ProgramSpec
              └── spec.check(exec_call)
                  ├── 解析选项
                  ├── 解析位置参数
                  └── 返回 MatchedExec
```

## 依赖与外部交互

### 外部 crate
- `multimap::MultiMap`：多值映射
- `regex_lite::Regex`：正则表达式

### 内部依赖
- `ExecCall`：输入类型
- `ProgramSpec`, `MatchedExec`, `Forbidden`：程序规则相关
- `ForbiddenProgramRegex`：禁止模式
- `Error`, `Result`：错误处理

## 风险、边界与改进建议

### 风险点

1. **正则表达式性能**
   - 禁止的程序检查使用正则匹配
   - 复杂的正则可能导致 ReDoS
   - 建议：限制正则复杂度或超时

2. **子字符串检查效率**
   ```rust
   // 当前实现：每个参数都检查所有子字符串
   for arg in args {
       if regex.is_match(arg) { ... }
   }
   ```
   - 大量参数时性能下降
   - 建议：使用 Aho-Corasick 等高效算法

3. **错误信息丢失**
   ```rust
   for spec in spec_list {
       match spec.check(exec_call) {
           Ok(matched) => return Ok(matched),
           Err(err) => last_err = Err(err),  // 只保留最后一个错误
       }
   }
   ```
   - 只返回最后一个规则的错误
   - 前面的错误信息丢失

4. **MultiMap 依赖**
   - 使用 `multimap` crate
   - 增加了外部依赖
   - 可以用 `HashMap<String, Vec<ProgramSpec>>` 替代

### 边界情况

1. **空策略**
   ```rust
   // programs 为空
   // -> 所有检查返回 NoSpecForProgram
   ```

2. **无禁止模式**
   ```rust
   // forbidden_program_regexes 为空
   // forbidden_substrings_pattern 为 None
   // -> 跳过禁止检查
   ```

3. **重复程序规则**
   ```rust
   // MultiMap 允许同一程序多个规则
   // 按插入顺序匹配
   ```

4. **正则编译失败**
   ```rust
   // Policy::new 返回 Result，可能因无效正则失败
   ```

### 改进建议

1. **错误聚合**
   ```rust
   pub fn check(&self, exec_call: &ExecCall) -> Result<MatchedExec> {
       // ...
       let mut errors = Vec::new();
       for spec in spec_list {
           match spec.check(exec_call) {
               Ok(matched) => return Ok(matched),
               Err(err) => errors.push(err),
           }
       }
       Err(Error::NoMatchingRule { program, errors })
   }
   ```

2. **优化子字符串检查**
   ```rust
   // 使用 Aho-Corasick 算法
   use aho_corasick::AhoCorasick;
   
   pub struct Policy {
       // ...
       forbidden_substrings: Option<AhoCorasick>,
   }
   ```

3. **添加缓存**
   ```rust
   pub struct Policy {
       // ...
       check_cache: Arc<Mutex<HashMap<ExecCall, MatchedExec>>>,
   }
   ```

4. **支持优先级**
   ```rust
   pub struct ProgramSpec {
       // ...
       priority: i32,  // 规则优先级
   }
   ```

5. **异步支持**
   ```rust
   pub async fn check_async(&self, exec_call: &ExecCall) -> Result<MatchedExec> {
       // 支持异步检查
   }
   ```

6. **统计和监控**
   ```rust
   pub struct PolicyStats {
       total_checks: AtomicU64,
       cache_hits: AtomicU64,
       forbidden_hits: AtomicU64,
   }
   ```

7. **测试覆盖**
   - 添加禁止模式测试
   - 添加多规则匹配测试
   - 添加性能测试
