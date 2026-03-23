# good.rs 研究文档

## 场景与职责

`good.rs` 是 `codex-execpolicy-legacy` crate 的集成测试文件，与 `bad.rs` 形成互补测试对。其核心职责是验证**正向示例列表 (good list)** 的有效性，确保所有被标记为"应该被接受"的命令调用确实能够通过策略检查。

该测试是策略配置正确性的正向验证，确保合法的安全命令不会被错误地拒绝。

## 功能点目的

### 1. 正向示例验证

在策略配置 (`default.policy`) 中，每个程序定义可以包含 `should_match` 列表，包含应该被策略接受的命令参数组合。例如：

```python
define_program(
    program="cat",
    ...
    should_match=[
        ["file.txt"],
        ["-n", "file.txt"],
        ["-b", "file.txt"],
    ],
)
```

### 2. 策略回归保护

确保对策略引擎的修改不会意外地破坏已批准的安全命令模式。

### 3. 配置正确性确认

验证 `default.policy` 中的 `should_match` 列表与实际的策略检查逻辑一致。

## 具体技术实现

### 测试结构

```rust
use codex_execpolicy_legacy::PositiveExampleFailedCheck;
use codex_execpolicy_legacy::get_default_policy;

#[test]
fn verify_everything_in_good_list_is_allowed() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_good_list_individually();
    assert_eq!(Vec::<PositiveExampleFailedCheck>::new(), violations);
}
```

### 关键流程

1. **加载默认策略**: 调用 `get_default_policy()` 加载嵌入的 `default.policy` 文件
2. **批量检查**: 调用 `policy.check_each_good_list_individually()` 遍历所有程序定义的 `should_match` 列表
3. **结果验证**: 确保返回的违规列表为空（即所有 good example 都被正确接受）

### 核心数据结构

**PositiveExampleFailedCheck** (位于 `src/program.rs`):
```rust
pub struct PositiveExampleFailedCheck {
    pub program: String,
    pub args: Vec<String>,
    pub error: Error,
}
```

当某个正向示例意外被策略拒绝时，会生成此结构记录：
- `program`: 程序名称
- `args`: 参数列表
- `error`: 拒绝原因（具体的错误类型）

**Policy::check_each_good_list_individually** (位于 `src/policy.rs`):
```rust
pub fn check_each_good_list_individually(&self) -> Vec<PositiveExampleFailedCheck> {
    let mut violations = Vec::new();
    for (_program, spec) in self.programs.flat_iter() {
        violations.extend(spec.verify_should_match_list());
    }
    violations
}
```

**ProgramSpec::verify_should_match_list** (位于 `src/program.rs`):
```rust
pub fn verify_should_match_list(&self) -> Vec<PositiveExampleFailedCheck> {
    let mut violations = Vec::new();
    for good in &self.should_match {
        let exec_call = ExecCall {
            program: self.program.clone(),
            args: good.clone(),
        };
        match self.check(&exec_call) {
            Ok(_) => {}
            Err(error) => {
                violations.push(PositiveExampleFailedCheck {
                    program: self.program.clone(),
                    args: good.clone(),
                    error,
                });
            }
        }
    }
    violations
}
```

### 与 bad.rs 的对比

| 特性 | good.rs | bad.rs |
|------|---------|--------|
| 验证目标 | should_match 列表 | should_not_match 列表 |
| 期望结果 | 所有示例通过检查 | 所有示例被拒绝 |
| 违规数据结构 | PositiveExampleFailedCheck | NegativeExamplePassedCheck |
| 违规信息 | 包含具体错误原因 | 仅记录程序名和参数 |
| 错误处理 | 捕获并记录错误 | 检查 is_ok() |

## 关键代码路径与文件引用

### 调用链

```
good.rs::verify_everything_in_good_list_is_allowed
    └── get_default_policy()
        └── PolicyParser::new("#default", DEFAULT_POLICY).parse()
    └── policy.check_each_good_list_individually()
        └── ProgramSpec::verify_should_match_list()
            └── ProgramSpec::check()
                └── 选项解析
                └── 参数解析 (arg_resolver.rs)
                └── 类型验证
```

### 相关文件

| 文件 | 职责 |
|------|------|
| `tests/suite/good.rs` | 本测试文件 |
| `src/lib.rs` | 库入口，导出 `get_default_policy` 和 `PositiveExampleFailedCheck` |
| `src/policy.rs` | `Policy` 结构体，实现 `check_each_good_list_individually` |
| `src/program.rs` | `ProgramSpec` 结构体，实现 `verify_should_match_list` |
| `src/default.policy` | 默认策略配置，定义各程序的 `should_match` 列表 |

## 依赖与外部交互

### 内部依赖

- `codex_execpolicy_legacy::PositiveExampleFailedCheck`: 违规检查结果类型
- `codex_execpolicy_legacy::get_default_policy`: 默认策略加载函数

### 策略配置示例

`default.policy` 中定义的正向示例：

```python
# cat 程序
define_program(
    program="cat",
    ...
    should_match=[
        ["file.txt"],
        ["-n", "file.txt"],
        ["-b", "file.txt"],
    ],
)

# cp 程序
define_program(
    program="cp",
    ...
    should_match=[
        ["foo", "bar"],
    ],
)

# printenv 程序 (带参数版本)
define_program(
    program="printenv",
    ...
    should_match=[["PATH"]],
)

# rg 程序
define_program(
    program="rg",
    ...
    should_match=[
        ["-n", "init"],
        ["-n", "init", "."],
        ["-i", "-n", "init", "src"],
        ["--files", "--max-depth", "2", "."],
    ],
)
```

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖不完整**: 仅验证预定义的 `should_match` 列表，不保证所有合法命令都被覆盖
2. **策略与测试不同步**: `should_match` 列表可能滞后于实际支持的命令模式
3. **单一失败点**: 所有验证在一个测试中完成，失败时难以快速定位具体哪个示例出了问题

### 边界情况

1. **空列表处理**: 如果 `should_match` 为空，测试自动通过
2. **多定义程序**: 同一程序多次定义时，会分别验证每个定义的正向示例
3. **错误传播**: `PositiveExampleFailedCheck` 包含完整的错误信息，便于调试

### 改进建议

1. **细化错误报告**: 当测试失败时，输出详细的错误信息：
   ```rust
   if !violations.is_empty() {
       for v in &violations {
           eprintln!("FAIL: {} {:?}", v.program, v.args);
           eprintln!("  Error: {:?}", v.error);
       }
   }
   ```

2. **分程序测试**: 考虑为每个程序单独创建测试：
   ```rust
   #[test]
   fn verify_cat_good_list() { ... }
   
   #[test]
   fn verify_cp_good_list() { ... }
   ```

3. **覆盖度指标**: 增加代码覆盖率检查，确保 `should_match` 覆盖主要的代码路径

4. **动态生成测试**: 考虑使用宏或测试生成器，根据 `default.policy` 自动生成独立测试

5. **与 bad.rs 的协调**: 确保同一程序的 `should_match` 和 `should_not_match` 之间没有重叠或矛盾
