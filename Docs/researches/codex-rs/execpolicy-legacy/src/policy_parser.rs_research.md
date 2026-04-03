# policy_parser.rs 研究文档

## 场景与职责

`policy_parser.rs` 是执行策略引擎的策略解析模块，负责：

1. **Starlark 解析**：使用 starlark-rust 库解析策略文件
2. **DSL 实现**：提供 `define_program()`, `flag()`, `opt()` 等内置函数
3. **策略构建**：收集解析结果并构建 Policy 对象
4. **常量注入**：向 Starlark 环境注入预定义的 ArgMatcher 常量

该模块是策略定义的入口，将 Starlark DSL 转换为可执行的策略规则。

## 功能点目的

### 1. PolicyParser 结构

```rust
pub struct PolicyParser {
    policy_source: String,      // 策略源标识（文件名）
    unparsed_policy: String,    // 策略文件内容
}
```

提供 `parse()` 方法将策略文本转换为 `Policy` 对象。

### 2. 解析流程

1. **配置方言**：启用 f-strings 等扩展特性
2. **解析 AST**：将策略文本解析为 Starlark AST
3. **创建环境**：构建包含内置函数的 Globals
4. **注入常量**：注册 ARG_* 常量到模块
5. **执行策略**：运行 Starlark 代码，收集规则
6. **构建策略**：将收集的规则转换为 Policy

### 3. 内置函数

**define_program()**：
```rust
fn define_program(
    program: String,
    system_path: Option<UnpackList<String>>,
    option_bundling: Option<bool>,
    combined_format: Option<bool>,
    options: Option<UnpackList<Opt>>,
    args: Option<UnpackList<ArgMatcher>>,
    forbidden: Option<String>,
    should_match: Option<UnpackList<UnpackList<String>>>,
    should_not_match: Option<UnpackList<UnpackList<String>>>,
    eval: &mut Evaluator,
) -> anyhow::Result<NoneType>
```

**forbid_substrings()**：
- 添加禁止的子字符串列表

**forbid_program_regex()**：
- 添加禁止的程序名正则表达式

**opt() / flag()**：
- 创建 Opt 对象

### 4. 预定义常量

| 常量 | ArgMatcher |
|------|-----------|
| ARG_OPAQUE_VALUE | OpaqueNonFile |
| ARG_RFILE | ReadableFile |
| ARG_WFILE | WriteableFile |
| ARG_RFILES | ReadableFiles |
| ARG_RFILES_OR_CWD | ReadableFilesOrCwd |
| ARG_POS_INT | PositiveInteger |
| ARG_SED_COMMAND | SedCommand |
| ARG_UNVERIFIED_VARARGS | UnverifiedVarargs |

## 具体技术实现

### 解析实现

```rust
impl PolicyParser {
    pub fn parse(&self) -> starlark::Result<Policy> {
        // 1. 配置方言
        let mut dialect = Dialect::Extended.clone();
        dialect.enable_f_strings = true;
        
        // 2. 解析 AST
        let ast = AstModule::parse(&self.policy_source, self.unparsed_policy.clone(), &dialect)?;
        
        // 3. 创建环境
        let globals = GlobalsBuilder::extended_by(&[LibraryExtension::Typing])
            .with(policy_builtins)
            .build();
        
        // 4. 创建模块并注入常量
        let module = Module::new();
        let heap = Heap::new();
        module.set("ARG_OPAQUE_VALUE", heap.alloc(ArgMatcher::OpaqueNonFile));
        // ... 其他常量
        
        // 5. 执行策略
        let policy_builder = PolicyBuilder::new();
        {
            let mut eval = Evaluator::new(&module);
            eval.extra = Some(&policy_builder);
            eval.eval_module(ast, &globals)?;
        }
        
        // 6. 构建策略
        let policy = policy_builder.build();
        policy.map_err(|e| starlark::Error::new_kind(starlark::ErrorKind::Other(e.into())))
    }
}
```

### PolicyBuilder

```rust
#[derive(Debug, ProvidesStaticType)]
struct PolicyBuilder {
    programs: RefCell<MultiMap<String, ProgramSpec>>,
    forbidden_program_regexes: RefCell<Vec<ForbiddenProgramRegex>>,
    forbidden_substrings: RefCell<Vec<String>>,
}
```

使用 `RefCell` 允许在 Starlark 执行期间可变借用。

### define_program 实现

```rust
fn define_program<'v>(
    program: String,
    system_path: Option<UnpackList<String>>,
    option_bundling: Option<bool>,
    combined_format: Option<bool>,
    options: Option<UnpackList<Opt>>,
    args: Option<UnpackList<ArgMatcher>>,
    forbidden: Option<String>,
    should_match: Option<UnpackList<UnpackList<String>>>,
    should_not_match: Option<UnpackList<UnpackList<String>>>,
    eval: &mut Evaluator,
) -> anyhow::Result<NoneType> {
    // 设置默认值
    let option_bundling = option_bundling.unwrap_or(false);
    let system_path = system_path.map_or_else(Vec::new, |v| v.items.to_vec());
    // ...
    
    // 处理选项，检查重复
    let mut allowed_options = HashMap::<String, Opt>::new();
    for opt in options {
        let name = opt.name().to_string();
        if allowed_options.insert(name.clone(), opt).is_some() {
            return Err(anyhow::format_err!("duplicate flag: {name}"));
        }
    }
    
    // 创建 ProgramSpec
    let program_spec = ProgramSpec::new(...);
    
    // 添加到 builder
    let policy_builder = eval.extra.as_ref().unwrap()
        .downcast_ref::<PolicyBuilder>().unwrap();
    policy_builder.add_program_spec(program_spec);
    
    Ok(NoneType)
}
```

### opt 和 flag 实现

```rust
fn opt(name: String, r#type: ArgMatcher, required: Option<bool>) -> anyhow::Result<Opt> {
    Ok(Opt::new(
        name,
        OptMeta::Value(r#type.arg_type()),
        required.unwrap_or(false),
    ))
}

fn flag(name: String) -> anyhow::Result<Opt> {
    Ok(Opt::new(name, OptMeta::Flag, /*required*/ false))
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/policy_parser.rs`

### 依赖文件
- `codex-rs/execpolicy-legacy/src/arg_matcher.rs`：ArgMatcher
- `codex-rs/execpolicy-legacy/src/opt.rs`：Opt, OptMeta
- `codex-rs/execpolicy-legacy/src/program.rs`：ProgramSpec
- `codex-rs/execpolicy-legacy/src/policy.rs`：Policy, ForbiddenProgramRegex

### 被依赖文件
- `codex-rs/execpolicy-legacy/src/lib.rs`：公开 PolicyParser
- `codex-rs/execpolicy-legacy/src/main.rs`：加载自定义策略
- `codex-rs/execpolicy-legacy/src/execv_checker.rs`：测试使用
- `tests/suite/*.rs`：测试使用

### 解析流程

```
PolicyParser::new(source, content)
  └── parse()
      ├── AstModule::parse()  // 解析 Starlark
      ├── GlobalsBuilder::with(policy_builtins)  // 注册内置函数
      ├── module.set(ARG_*, ...)  // 注入常量
      ├── Evaluator::eval_module()  // 执行策略
      │   └── define_program() / flag() / opt() / ...
      │       └── PolicyBuilder::add_program_spec()
      └── PolicyBuilder::build()
          └── Policy::new()
```

## 依赖与外部交互

### 外部 crate
- `starlark`：Starlark 语言实现
  - `AstModule`, `Dialect`, `GlobalsBuilder`
  - `Evaluator`, `Module`, `Heap`
  - `starlark_module` 宏
  - `ProvidesStaticType`
- `multimap::MultiMap`：多值映射
- `regex_lite::Regex`：正则表达式
- `log::info`：日志

### 标准库
- `std::cell::RefCell`：内部可变性
- `std::collections::HashMap`：选项去重

### 内部依赖
- `ArgMatcher`, `Opt`, `OptMeta`
- `ProgramSpec`, `Policy`
- `ForbiddenProgramRegex`

## 风险、边界与改进建议

### 风险点

1. **unwrap 使用**
   ```rust
   let policy_builder = eval
       .extra
       .as_ref()
       .unwrap()
       .downcast_ref::<PolicyBuilder>()
       .unwrap();
   ```
   - 使用 `#[expect(clippy::unwrap_used)]` 抑制警告
   - 如果 `eval.extra` 未设置会 panic

2. **Starlark 执行安全**
   - Starlark 是受限语言，但仍有风险
   - 无限循环、内存耗尽等
   - 建议：添加执行超时和资源限制

3. **错误信息质量**
   - Starlark 错误可能难以理解的
   - 建议：包装错误，提供更友好的消息

4. **RefCell 运行时开销**
   - 每次 `add_program_spec` 都借用 RefCell
   - 性能敏感场景可能有影响

### 边界情况

1. **空策略文件**
   ```rust
   // 解析成功，但 Policy 为空
   // -> 所有检查返回 NoSpecForProgram
   ```

2. **重复程序定义**
   ```rust
   // MultiMap 允许重复
   // 同一程序多个规则按顺序匹配
   ```

3. **重复选项定义**
   ```rust
   // 在 define_program 中检查
   // -> 返回错误 "duplicate flag: {name}"
   ```

4. **无效正则**
   ```rust
   // forbid_program_regex() 中编译
   // -> 返回 regex 编译错误
   ```

### 改进建议

1. **错误改进**
   ```rust
   // 包装 Starlark 错误
   pub enum ParseError {
       Starlark(starlark::Error),
       InvalidRegex(String),
       DuplicateFlag { program: String, flag: String },
   }
   ```

2. **性能优化**
   ```rust
   // 预编译常用正则
   lazy_static! {
       static ref VALID_FLAG: Regex = Regex::new(r"^-[a-zA-Z]$").unwrap();
   }
   ```

3. **语法验证**
   ```rust
   // 验证选项名格式
   if !name.starts_with('-') {
       return Err(anyhow::format_err!("invalid option name: {name}"));
   }
   ```

4. **增量解析**
   ```rust
   // 支持从多个文件加载策略
   pub fn parse_multi(&self, sources: &[(&str, &str)]) -> starlark::Result<Policy> {
       // 合并多个策略文件
   }
   ```

5. **调试支持**
   ```rust
   // 添加解析日志
   log::debug!("Parsing program: {}", program);
   log::debug!("Registered {} options", allowed_options.len());
   ```

6. **类型安全**
   ```rust
   // 使用 newtype 模式
   pub struct ProgramName(String);
   pub struct FlagName(String);
   ```

7. **测试覆盖**
   - 添加语法错误测试
   - 添加重复定义测试
   - 添加无效正则测试
