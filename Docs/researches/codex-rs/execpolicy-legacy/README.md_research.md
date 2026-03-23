# README.md 研究文档

## 场景与职责

`README.md` 是 `codex-execpolicy-legacy` crate 的用户文档和 API 参考。它详细说明了该遗留执行策略引擎的设计目标、使用方式、策略文件格式和输出类型。该文档面向需要理解和使用执行策略验证功能的开发者和用户。

## 功能点目的

### 1. 设计目标说明
- 将提议的 `execv(3)` 命令分类为四种状态：`safe`、`match`、`forbidden`、`unverified`
- 强调"安全"不是运行时成功的保证，而是权限边界的确认

### 2. 使用示例展示
- CLI 使用方式：`cargo run -p codex-execpolicy-legacy -- check ls -l foo`
- JSON 输出格式说明

### 3. 策略文件格式文档
- 使用 Starlark 作为策略文件格式的原因（支持宏、安全、可复现）
- `define_program()` 规则的语法和语义

### 4. 输出类型详细说明
- `safe`: 命令被验证为安全
- `match`: 命令匹配规则但需要调用者判断（涉及文件写入）
- `forbidden`: 命令被明确禁止

## 具体技术实现

### 核心分类系统

```
execv(3) 调用
    │
    ├──► safe - 安全执行（如 ls -l）
    │
    ├──► match - 匹配规则但需判断（如 cp src dest）
    │
    ├──► forbidden - 明确禁止（如 applied deploy）
    │
    └──► unverified - 无法验证，需用户决定
```

### 命令执行示例

**输入**:
```shell
cargo run -p codex-execpolicy-legacy -- check ls -l foo | jq
```

**输出**:
```json
{
  "result": "safe",
  "match": {
    "program": "ls",
    "flags": [{"name": "-l"}],
    "opts": [],
    "args": [
      {"index": 1, "type": "ReadableFile", "value": "foo"}
    ],
    "system_path": ["/bin/ls", "/usr/bin/ls"]
  }
}
```

### 策略规则定义

```python
define_program(
    program="cp",
    options=[
        flag("-r"),
        flag("-R"),
        flag("--recursive"),
    ],
    args=[ARG_RFILES, ARG_WFILE],  # 读文件列表 + 写文件
    system_path=["/bin/cp", "/usr/bin/cp"],
    should_match=[["foo", "bar"]],      # 正向测试用例
    should_not_match=[["foo"]],          # 负向测试用例
)
```

### 参数类型常量

| 常量 | 含义 |
|------|------|
| `ARG_RFILES` | 一个或多个可读文件 |
| `ARG_WFILE` | 单个可写文件 |
| `ARG_RFILES_OR_CWD` | 可读文件列表或当前目录 |
| `ARG_OPAQUE_VALUE` | 非文件的不透明值 |
| `ARG_POS_INT` | 正整数 |
| `ARG_SED_COMMAND` | 安全的 sed 命令 |
| `ARG_UNVERIFIED_VARARGS` | 未验证的变长参数 |

### 退出码设计

- `0`: 成功（safe 或 match，除非 `--require-safe`）
- `12`: match 但 `--require-safe` 启用（`MATCHED_BUT_WRITES_FILES_EXIT_CODE`）
- `13`: unverified（`MIGHT_BE_SAFE_EXIT_CODE`）
- `14`: forbidden（`FORBIDDEN_EXIT_CODE`）

## 关键代码路径与文件引用

### 实现文件
- `src/lib.rs` - 库入口，导出公共 API
- `src/main.rs` - CLI 实现，包含 `Output` enum 和退出码逻辑
- `src/policy.rs` - `Policy` 结构体，主检查逻辑
- `src/policy_parser.rs` - Starlark 策略文件解析
- `src/program.rs` - `ProgramSpec` 和匹配逻辑
- `src/arg_matcher.rs` - 参数匹配器定义
- `src/arg_resolver.rs` - 参数解析逻辑
- `src/arg_type.rs` - 参数类型枚举
- `src/valid_exec.rs` - `ValidExec` 和匹配结果结构
- `src/execv_checker.rs` - 高级检查器（含文件系统验证）
- `src/exec_call.rs` - `ExecCall` 结构体

### 策略文件
- `src/default.policy` - 内置默认策略

### 测试
- `tests/suite/good.rs` - 验证 `should_match` 用例
- `tests/suite/bad.rs` - 验证 `should_not_match` 用例

## 依赖与外部交互

### Starlark 运行时
- 使用 `starlark-rust` 库解析执行 `.policy` 文件
- 策略文件使用 Python-like 语法

### CLI 集成
```
CLI (main.rs)
    │
    ├──► PolicyParser::parse() ──► Policy
    │
    └──► Policy::check() ──► MatchedExec
                │
                ├──► Match { exec: ValidExec }
                ├──► Forbidden { reason, cause }
                └──► Err(Error)
```

### 库 API 使用模式
```rust
// 1. 加载策略
let policy = get_default_policy()?;

// 2. 创建执行调用
let exec_call = ExecCall { program, args };

// 3. 检查匹配
match policy.check(&exec_call)? {
    MatchedExec::Match { exec } => { /* 验证文件路径 */ },
    MatchedExec::Forbidden { reason, cause } => { /* 拒绝执行 */ },
}

// 4. 高级检查（含文件系统验证）
let checker = ExecvChecker::new(policy);
let program_path = checker.check(valid_exec, &cwd, &readable, &writeable)?;
```

### 与新版策略引擎的关系
- `codex-execpolicy` 是新的前缀规则引擎
- `codex-execpolicy-legacy` 是原始实现
- 两者并存，legacy 版本逐步被替换

## 风险、边界与改进建议

### 风险

1. **策略文件完整性**
   - `default.policy` 的完整性通过单元测试验证
   - 但策略语言仍在演进，可能导致向后兼容问题

2. **命令解析复杂性**
   - 不支持 `--` 参数终止符（`DoubleDashNotSupportedYet` 错误）
   - 选项捆绑（option bundling）标记为 PLANNED 但未实现
   - 组合格式（`--option=value`）标记为 PLANNED 但未实现

3. **sed 命令安全性**
   - GNU sed 的 `e` 标志可以执行任意命令
   - 当前实现仅支持简单的 `122,202p` 格式
   - `sed_command.rs` 的解析器非常有限

4. **Windows 支持不完整**
   - `execv_checker.rs` 中的 `is_executable_file` 对 Windows 只有占位实现
   - 未检查 `PATHEXT` 环境变量

### 边界

1. **安全边界**
   - 只能验证命令结构，不能验证运行时行为
   - 文件存在性检查不是安全保证的一部分
   - 相对路径需要 `cwd` 上下文才能验证

2. **功能边界**
   - 不支持管道、重定向等 shell 特性（纯 `execv` 检查）
   - 不支持环境变量检查
   - 不支持动态库依赖检查

3. **性能边界**
   - 每次检查都需要遍历所有匹配的规则
   - Starlark 解析在加载时完成，但规则匹配是运行时操作

### 改进建议

1. **功能完善**
   - 实现 `--` 支持（`src/program.rs` 第 116-119 行）
   - 完成选项捆绑和组合格式支持
   - 完善 Windows 可执行文件检测

2. **安全增强**
   - 扩展 sed 命令解析器，支持更多安全子集
   - 添加命令超时和资源限制检查
   - 考虑添加网络访问控制

3. **测试覆盖**
   - 增加模糊测试（fuzzing）验证解析器鲁棒性
   - 添加更多边缘情况测试（空参数、超长参数、Unicode 等）
   - 测试不同平台的路径处理

4. **迁移策略**
   - 明确 deprecation 时间表
   - 提供从 legacy 到新版策略引擎的自动迁移工具
   - 统一两套策略引擎的 API 接口

5. **文档改进**
   - 为策略文件的 Starlark DSL 编写完整语法规范
   - 添加更多实际使用示例
   - 记录常见错误和解决方案

6. **监控和可观测性**
   - 添加 metrics 收集策略匹配统计
   - 记录被拒绝的命令模式用于策略改进
   - 提供策略覆盖率的分析工具
