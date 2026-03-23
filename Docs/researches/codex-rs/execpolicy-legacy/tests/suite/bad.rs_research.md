# bad.rs 研究文档

## 场景与职责

`bad.rs` 是 `codex-execpolicy-legacy`  crate 的集成测试文件，属于测试套件 (`tests/suite`) 的一部分。其核心职责是验证**负向示例列表 (bad list)** 的有效性，确保所有被标记为"应该被拒绝"的命令调用确实会被策略检查器拒绝。

该测试与 `good.rs` 形成互补：
- `good.rs`: 验证正向示例列表 (should_match) 中的命令都能通过策略检查
- `bad.rs`: 验证负向示例列表 (should_not_match) 中的命令都会被策略拒绝

## 功能点目的

### 1. 负向示例验证

在策略配置 (`default.policy`) 中，每个程序定义可以包含 `should_not_match` 列表，包含不应该被策略接受的命令参数组合。例如：

```python
define_program(
    program="cat",
    ...
    should_not_match=[
        [],  # cat 不带参数从 stdin 读取，不适合当前用例
        ["-l", "file.txt"],  # 不自动批准咨询锁定
    ]
)
```

### 2. 安全边界确认

确保策略引擎能够正确识别并拒绝潜在危险或不合适的命令调用，这是整个执行策略系统的核心安全机制之一。

## 具体技术实现

### 测试结构

```rust
use codex_execpolicy_legacy::NegativeExamplePassedCheck;
use codex_execpolicy_legacy::get_default_policy;

#[test]
fn verify_everything_in_bad_list_is_rejected() {
    let policy = get_default_policy().expect("failed to load default policy");
    let violations = policy.check_each_bad_list_individually();
    assert_eq!(Vec::<NegativeExamplePassedCheck>::new(), violations);
}
```

### 关键流程

1. **加载默认策略**: 调用 `get_default_policy()` 加载嵌入的 `default.policy` 文件
2. **批量检查**: 调用 `policy.check_each_bad_list_individually()` 遍历所有程序定义的 `should_not_match` 列表
3. **结果验证**: 确保返回的违规列表为空（即所有 bad example 都被正确拒绝）

### 核心数据结构

**NegativeExamplePassedCheck** (位于 `src/program.rs`):
```rust
pub struct NegativeExamplePassedCheck {
    pub program: String,
    pub args: Vec<String>,
}
```

当某个负向示例意外通过了策略检查时，会生成此结构记录违规信息。

**Policy::check_each_bad_list_individually** (位于 `src/policy.rs`):
```rust
pub fn check_each_bad_list_individually(&self) -> Vec<NegativeExamplePassedCheck> {
    let mut violations = Vec::new();
    for (_program, spec) in self.programs.flat_iter() {
        violations.extend(spec.verify_should_not_match_list());
    }
    violations
}
```

**ProgramSpec::verify_should_not_match_list** (位于 `src/program.rs`):
```rust
pub fn verify_should_not_match_list(&self) -> Vec<NegativeExamplePassedCheck> {
    let mut violations = Vec::new();
    for bad in &self.should_not_match {
        let exec_call = ExecCall {
            program: self.program.clone(),
            args: bad.clone(),
        };
        if self.check(&exec_call).is_ok() {
            violations.push(NegativeExamplePassedCheck {
                program: self.program.clone(),
                args: bad.clone(),
            });
        }
    }
    violations
}
```

## 关键代码路径与文件引用

### 调用链

```
bad.rs::verify_everything_in_bad_list_is_rejected
    └── get_default_policy()
        └── PolicyParser::new("#default", DEFAULT_POLICY).parse()
    └── policy.check_each_bad_list_individually()
        └── ProgramSpec::verify_should_not_match_list()
            └── ProgramSpec::check()
```

### 相关文件

| 文件 | 职责 |
|------|------|
| `tests/suite/bad.rs` | 本测试文件 |
| `src/lib.rs` | 库入口，导出 `get_default_policy` 和 `NegativeExamplePassedCheck` |
| `src/policy.rs` | `Policy` 结构体，实现 `check_each_bad_list_individually` |
| `src/program.rs` | `ProgramSpec` 结构体，实现 `verify_should_not_match_list` |
| `src/default.policy` | 默认策略配置，定义各程序的 `should_not_match` 列表 |

## 依赖与外部交互

### 内部依赖

- `codex_execpolicy_legacy::NegativeExamplePassedCheck`: 违规检查结果类型
- `codex_execpolicy_legacy::get_default_policy`: 默认策略加载函数

### 策略配置示例

`default.policy` 中定义的负向示例：

```python
# cat 程序
define_program(
    program="cat",
    ...
    should_not_match=[
        [],  # 拒绝无参数调用
        ["-l", "file.txt"],  # 拒绝 -l 选项
    ]
)

# cp 程序
define_program(
    program="cp",
    ...
    should_not_match=[
        ["foo"],  # 拒绝只有一个参数（缺少目标）
    ]
)

# printenv 程序 (无参数版本)
define_program(
    program="printenv",
    ...
    should_not_match=[["PATH"]],  # 拒绝带参数的调用
)
```

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖不完整**: 仅验证预定义的 `should_not_match` 列表，不覆盖所有可能的危险命令组合
2. **策略漂移**: 如果 `default.policy` 更新但测试未同步，可能导致安全边界变化未被检测
3. **单一失败点**: 所有验证在一个测试中完成，失败时难以快速定位具体哪个示例出了问题

### 边界情况

1. **空策略**: 如果 `should_not_match` 列表为空，测试自动通过
2. **重复定义**: 同一程序多次定义时，会分别验证每个定义的负向示例
3. **错误类型不区分**: 只关心是否被拒绝，不关心具体的拒绝原因

### 改进建议

1. **细化错误报告**: 当测试失败时，输出具体的违规示例详情：
   ```rust
   if !violations.is_empty() {
       for v in &violations {
           eprintln!("FAIL: {} {:?} should have been rejected", v.program, v.args);
       }
   }
   ```

2. **分程序测试**: 考虑为每个程序单独创建测试，便于定位问题：
   ```rust
   #[test]
   fn verify_cat_bad_list() { ... }
   
   #[test]
   fn verify_cp_bad_list() { ... }
   ```

3. **扩展验证**: 除了预定义列表，可增加对已知危险模式的通用测试

4. **文档同步**: 确保 `should_not_match` 中每个示例都有注释说明为何被拒绝
