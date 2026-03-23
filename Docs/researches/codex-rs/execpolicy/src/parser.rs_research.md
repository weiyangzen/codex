# parser.rs 研究文档

## 场景与职责

`parser.rs` 是 `codex-execpolicy` crate 的**策略解析核心模块**，负责将 Starlark 格式的策略文件解析为内存中的策略对象。这是整个策略引擎的"编译器"前端，主要场景包括：

1. **策略文件加载**：将 `.rules` 或 `.codexpolicy` 文件解析为可执行的策略
2. **语法验证**：在加载时捕获语法错误和逻辑错误
3. **示例验证**：验证 `match`/`not_match` 示例是否按预期工作（类似单元测试）
4. **规则展开**：将带替代的模式展开为多个具体规则

该模块使用 Google 的 Starlark 语言（Python 子集）作为策略 DSL，提供灵活且用户友好的配置语法。

## 功能点目的

### 1. `PolicyParser` - 策略解析器

主要解析入口，维护解析状态并构建最终策略：

```rust
pub struct PolicyParser {
    builder: RefCell<PolicyBuilder>,
}
```

使用 `RefCell` 允许在 Starlark 回调中修改解析状态。

### 2. Starlark 内置函数

定义策略 DSL 的三个核心函数：

| 函数 | 用途 |
|------|------|
| `prefix_rule()` | 定义前缀匹配规则 |
| `network_rule()` | 定义网络访问规则 |
| `host_executable()` | 定义主机可执行文件路径映射 |

### 3. 模式解析

支持复杂的模式语法：
- 单 token：`"git"`
- 替代 token：`["bash", "sh"]`
- 嵌套组合：`["npm", ["i", "install"], ["--legacy-peer-deps", "--no-save"]]`

### 4. 示例验证

延迟验证机制：
1. 解析时收集待验证的示例
2. 解析完成后统一验证
3. 验证失败时报告具体位置和原因

## 具体技术实现

### 解析流程

```rust
pub fn parse(&mut self, policy_identifier: &str, policy_file_contents: &str) -> Result<()> {
    // 1. 记录当前待验证示例数量
    let pending_validation_count = self.builder.borrow().pending_example_validations.len();
    
    // 2. 配置 Starlark 方言
    let mut dialect = Dialect::Extended.clone();
    dialect.enable_f_strings = true;
    
    // 3. 解析 AST
    let ast = AstModule::parse(policy_identifier, policy_file_contents.to_string(), &dialect)?;
    
    // 4. 创建执行环境
    let globals = GlobalsBuilder::standard().with(policy_builtins).build();
    let module = Module::new();
    
    // 5. 执行策略文件
    let mut eval = Evaluator::new(&module);
    eval.extra = Some(&self.builder);
    eval.eval_module(ast, &globals)?;
    
    // 6. 验证新增示例
    self.builder.borrow().validate_pending_examples_from(pending_validation_count)?;
    
    Ok(())
}
```

### 模式解析

```rust
fn parse_pattern<'v>(pattern: UnpackList<Value<'v>>) -> Result<Vec<PatternToken>> {
    let tokens: Vec<PatternToken> = pattern
        .items
        .into_iter()
        .map(parse_pattern_token)
        .collect::<Result<_>>()?;
    
    if tokens.is_empty() {
        Err(Error::InvalidPattern("pattern cannot be empty".to_string()))
    } else {
        Ok(tokens)
    }
}

fn parse_pattern_token<'v>(value: Value<'v>) -> Result<PatternToken> {
    if let Some(s) = value.unpack_str() {
        // 字符串 → Single
        Ok(PatternToken::Single(s.to_string()))
    } else if let Some(list) = ListRef::from_value(value) {
        // 列表 → Alts（或单个元素的 Single）
        let tokens: Vec<String> = /* 解析列表元素 */;
        match tokens.as_slice() {
            [] => Err(Error::InvalidPattern("alternatives cannot be empty".to_string())),
            [single] => Ok(PatternToken::Single(single.clone())),
            _ => Ok(PatternToken::Alts(tokens)),
        }
    } else {
        Err(Error::InvalidPattern(/* ... */))
    }
}
```

### 规则展开

```rust
fn prefix_rule<'v>(
    pattern: UnpackList<Value<'v>>,
    decision: Option<&'v str>,
    // ...
) -> anyhow::Result<NoneType> {
    let pattern_tokens = parse_pattern(pattern)?;
    let (first_token, remaining_tokens) = pattern_tokens.split_first().unwrap();
    let rest: Arc<[PatternToken]> = remaining_tokens.to_vec().into();
    
    // 为第一 token 的每个替代创建规则
    let rules: Vec<RuleRef> = first_token
        .alternatives()
        .iter()
        .map(|head| {
            Arc::new(PrefixRule {
                pattern: PrefixPattern {
                    first: Arc::from(head.as_str()),
                    rest: rest.clone(),
                },
                decision,
                justification,
            }) as RuleRef
        })
        .collect();
    
    // 添加规则和待验证示例
    builder.add_pending_example_validation(rules.clone(), matches, not_matches, location);
    rules.into_iter().for_each(|rule| builder.add_rule(rule));
    Ok(NoneType)
}
```

关键设计：**只有第一 token 的替代会展开为多个规则**，后续 token 的替代保留在 `PatternToken::Alts` 中。

### 示例解析

支持两种格式：

```rust
fn parse_examples<'v>(examples: UnpackList<Value<'v>>) -> Result<Vec<Vec<String>>> {
    examples.items.into_iter().map(parse_example).collect()
}

fn parse_example<'v>(value: Value<'v>) -> Result<Vec<String>> {
    if let Some(raw) = value.unpack_str() {
        // 字符串：使用 shlex 分词
        parse_string_example(raw)
    } else if let Some(list) = ListRef::from_value(value) {
        // 列表：直接解析为 token 数组
        parse_list_example(list)
    } else {
        Err(Error::InvalidExample(/* ... */))
    }
}
```

### 错误定位

```rust
fn error_location_from_file_span(span: FileSpan) -> ErrorLocation {
    let resolved = span.resolve_span();
    ErrorLocation {
        path: span.filename().to_string(),
        range: TextRange {
            start: TextPosition {
                line: resolved.begin.line + 1,      // 0-based → 1-based
                column: resolved.begin.column + 1,
            },
            end: TextPosition {
                line: resolved.end.line + 1,
                column: resolved.end.column + 1,
            },
        },
    }
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `decision` | 决策解析 |
| `error` | 错误类型和位置信息 |
| `executable_name` | 可执行文件名处理 |
| `policy` | `Policy` 构建 |
| `rule` | 规则类型定义 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `starlark` | Starlark 语言解析和执行 |
| `multimap` | 多值映射存储规则 |
| `shlex` | Shell 风格字符串分词 |
| `codex_utils_absolute_path` | 绝对路径类型 |

### Starlark 集成

使用 `starlark` crate 的以下功能：
- `AstModule::parse`：解析源代码为 AST
- `GlobalsBuilder`：注册内置函数
- `Evaluator`：执行代码
- `#[starlark_module]`：定义内置函数宏

## 风险、边界与改进建议

### 风险点

1. **RefCell 运行时借用**：`RefCell` 在运行时检查借用规则，错误的借用模式会导致 panic
2. **Starlark 版本锁定**：重度依赖 `starlark` crate，升级可能引入破坏性变更
3. **示例验证性能**：每个示例都执行完整策略匹配，大量示例时性能下降
4. **递归限制**：Starlark 默认有递归深度限制，复杂策略可能触发

### 边界条件

1. **空模式**：拒绝空 pattern（`[]`）
2. **空替代**：拒绝空替代列表（`[[]]`）
3. **空示例**：拒绝空字符串或空列表示例
4. **无效 shlex**：字符串示例必须有有效的 shell 语法
5. **绝对路径**：`host_executable` 要求绝对路径

### 改进建议

1. **性能优化**：
   - 使用并行验证示例
   - 缓存解析结果
   - 增量解析（只重新解析变更的文件）

2. **更好的错误消息**：
   ```
   error: invalid pattern at test.rules:10:5
    --> pattern = ["git", []]
    |                  ^^^ empty alternatives not allowed
   ```

3. **更多内置函数**：
   - `include()`：包含其他策略文件
   - `variable()`：定义可复用的变量
   - `macro()`：定义可复用的规则模板

4. **类型检查**：
   - 在解析时检查更多类型错误
   - 提供 LSP 支持

5. **IDE 支持**：
   - 语法高亮定义
   - 自动补全
   - 跳转到定义

6. **测试框架**：
   - 更丰富的测试断言
   - 测试覆盖率报告
   - 模糊测试

### 代码示例

策略文件示例（`example.codexpolicy`）：

```starlark
prefix_rule(
    pattern = ["git", "reset", "--hard"],
    decision = "forbidden",
    justification = "destructive operation",
    match = [["git", "reset", "--hard"]],
    not_match = [["git", "reset", "--keep"]],
)

host_executable(
    name = "git",
    paths = ["/usr/bin/git", "/opt/homebrew/bin/git"],
)
```

解析和使用：

```rust
let mut parser = PolicyParser::new();
parser.parse("example.codexpolicy", policy_src)?;
let policy = parser.build();

let evaluation = policy.check(&["git", "reset", "--hard"], &|_| Decision::Prompt);
assert_eq!(evaluation.decision, Decision::Forbidden);
```
