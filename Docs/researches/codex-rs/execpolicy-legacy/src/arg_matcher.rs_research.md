# arg_matcher.rs 研究文档

## 场景与职责

`arg_matcher.rs` 定义了执行策略引擎中用于匹配命令行参数的模式类型 `ArgMatcher`。它是策略规则与实际参数之间的桥梁，负责：

1. **定义参数匹配模式**：支持从字面量到复杂类型（如文件路径、正整数）的多种匹配模式
2. **支持 Starlark 集成**：通过实现 Starlark 的 `StarlarkValue` trait，允许在 `.policy` 文件中使用这些匹配器
3. **提供基数信息**：每个匹配器知道它期望匹配多少个参数（一个、至少一个、零个或多个）
4. **映射到 ArgType**：将匹配模式转换为用于验证和类型标记的 `ArgType`

## 功能点目的

### ArgMatcher 枚举

| 变体 | 目的 | 使用场景 |
|------|------|----------|
| `Literal(String)` | 精确匹配特定字符串值 | 固定参数值，如 `printenv PATH` 中的 "PATH" |
| `OpaqueNonFile` | 匹配非文件路径的任意值 | 不关心的普通字符串参数 |
| `ReadableFile` | 匹配单个可读文件路径 | 源文件参数，如 `cat file.txt` |
| `WriteableFile` | 匹配单个可写文件路径 | 目标文件参数，如 `cp src dest` 中的 dest |
| `ReadableFiles` | 匹配一个或多个可读文件 | 多源文件，如 `cat file1 file2` |
| `ReadableFilesOrCwd` | 匹配零个或多个可读文件，空列表表示当前目录 | `ls` 无参数时默认为当前目录 |
| `PositiveInteger` | 匹配正整数 | `head -n 10` 中的行数 |
| `SedCommand` | 匹配安全的 sed 命令 | 限制 sed 命令防止代码注入 |
| `UnverifiedVarargs` | 匹配任意数量的参数，不做验证 | 透传参数给底层命令 |

### ArgMatcherCardinality 枚举

表示匹配器期望的参数数量：
- `One`：恰好一个参数
- `AtLeastOne`：至少一个参数
- `ZeroOrMore`：零个或多个参数

## 具体技术实现

### Starlark 集成

```rust
#[starlark_value(type = "ArgMatcher")]
impl<'v> StarlarkValue<'v> for ArgMatcher {
    type Canonical = ArgMatcher;
}
```

通过 `starlark_value` 宏实现 Starlark 值接口，使得匹配器可以在 `.policy` 文件中作为常量使用（如 `ARG_RFILE`、`ARG_WFILE` 等）。

### UnpackValue 实现

```rust
impl<'v> UnpackValue<'v> for ArgMatcher {
    fn unpack_value_impl(value: Value<'v>) -> starlark::Result<Option<Self>> {
        if let Some(str) = value.downcast_ref::<StarlarkStr>() {
            // 字符串字面量自动转为 Literal 匹配器
            Ok(Some(ArgMatcher::Literal(str.as_str().to_string())))
        } else {
            Ok(value.downcast_ref::<ArgMatcher>().cloned())
        }
    }
}
```

支持两种解包方式：
1. 字符串字面量 → 自动包装为 `ArgMatcher::Literal`
2. 预定义的匹配器常量（如 `ARG_RFILE`）→ 直接克隆

### 基数计算逻辑

```rust
pub fn cardinality(&self) -> ArgMatcherCardinality {
    match self {
        // 单参数类型
        ArgMatcher::Literal(_) | ArgMatcher::OpaqueNonFile | ... => ArgMatcherCardinality::One,
        // 至少一个
        ArgMatcher::ReadableFiles => ArgMatcherCardinality::AtLeastOne,
        // 零个或多个
        ArgMatcher::ReadableFilesOrCwd | ArgMatcher::UnverifiedVarargs => ArgMatcherCardinality::ZeroOrMore,
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/execpolicy-legacy/src/arg_matcher.rs` (118 行)

### 核心依赖
- `arg_type.rs`：`ArgMatcher::arg_type()` 方法返回 `ArgType`
- `policy_parser.rs`：在 Starlark 环境中注册匹配器常量

### 使用位置
- `policy_parser.rs:48-61`：注册全局匹配器常量
  ```rust
  module.set("ARG_OPAQUE_VALUE", heap.alloc(ArgMatcher::OpaqueNonFile));
  module.set("ARG_RFILE", heap.alloc(ArgMatcher::ReadableFile));
  // ... 其他常量
  ```
- `arg_resolver.rs`：使用 `cardinality()` 进行参数分区匹配
- `default.policy`：实际使用这些常量定义程序规则

### 类型转换链
```
ArgMatcher (策略定义) 
    ↓ arg_type()
ArgType (验证/标记)
    ↓ validate()
验证结果
```

## 依赖与外部交互

### 外部 crate
- `starlark`：提供 Starlark 语言集成
- `allocative`：内存分配追踪
- `derive_more`：派生 `Display` trait

### 模块间依赖
```
arg_matcher.rs
    ↑ 使用 arg_type::ArgType
    ↓ 被 policy_parser 注册为 Starlark 常量
    ↓ 被 arg_resolver 用于参数匹配
```

## 风险、边界与改进建议

### 当前限制

1. **变参模式限制**：`arg_resolver.rs` 的实现限制只能有一个变参模式（`AtLeastOne` 或 `ZeroOrMore`），且必须位于前缀和后缀模式之间
   ```rust
   // 有效: [Literal, ReadableFiles, Literal]
   // 无效: [ReadableFiles, ReadableFiles] - 多个变参模式
   ```

2. **字符串自动转换的歧义**：`UnpackValue` 将字符串转为 `Literal`，这可能与预期行为不符
   ```python
   # 在 .policy 中
   args=["--help"]  # 实际创建的是 ArgMatcher::Literal("--help")
   ```

3. **缺少组合匹配器**：无法表达 "A 或 B" 这样的逻辑，只能定义多个 `define_program` 规则

### 边界情况

1. **空字符串处理**：`Literal("")` 可以匹配空参数，但 `ReadableFile` 会在验证阶段拒绝空字符串
2. **路径规范化**：匹配器本身不处理路径，仅标记类型，实际验证在 `execv_checker.rs` 中进行

### 改进建议

1. **支持多个变参模式**：改进 `arg_resolver.rs` 的分区算法，支持更复杂的模式组合
2. **添加否定匹配器**：`Not(ArgMatcher)` 用于排除特定模式
3. **正则匹配器**：`Regex(&str)` 支持正则表达式匹配
4. **条件匹配器**：`If(Condition, ArgMatcher)` 支持条件匹配
5. **文档生成**：从匹配器定义自动生成 `.policy` 文件文档

### 安全考虑

- `UnverifiedVarargs` 是一个潜在的安全风险点，因为它接受任意参数而不验证
- 建议在策略文件中限制 `UnverifiedVarargs` 的使用，并配合 `forbidden_substrings` 进行黑名单过滤
