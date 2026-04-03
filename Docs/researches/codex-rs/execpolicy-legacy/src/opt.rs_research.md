# opt.rs 研究文档

## 场景与职责

`opt.rs` 定义了执行策略引擎中的命令行选项（option/flag）类型，负责：

1. **选项定义**：表示命令行选项的结构和元数据
2. **选项分类**：区分无值标志（flag）和带值选项（opt）
3. **必需选项支持**：标记必须提供的选项
4. **Starlark 集成**：支持在 Starlark DSL 中定义选项

该模块是策略系统中描述命令行选项的基础组件，与 `arg_matcher` 和 `arg_type` 协同工作。

## 功能点目的

### 1. Opt 结构

```rust
#[derive(Clone, Debug, Display, PartialEq, Eq, ProvidesStaticType, NoSerialize, Allocative)]
#[display("opt({})", opt)]
pub struct Opt {
    pub opt: String,       // 选项名（如 "-h", "--help"）
    pub meta: OptMeta,     // 选项元数据
    pub required: bool,    // 是否必需
}
```

**设计考量**：
- 使用 `String` 而非 `&str`：拥有所有权，便于在 Starlark 中传递
- `NoSerialize`：不直接序列化 Opt（通过 ValidExec 中的 MatchedOpt 序列化结果）
- `Allocative`：支持 Starlark 内存追踪

### 2. OptMeta 枚举

```rust
#[derive(Clone, Debug, Display, PartialEq, Eq, ProvidesStaticType, NoSerialize, Allocative)]
#[display("{}", self)]
pub enum OptMeta {
    Flag,           // 无值标志（如 `-l`）
    Value(ArgType), // 带值选项（如 `-n 10`）
}
```

**分类说明**：
- `Flag`：布尔开关，出现时即生效
- `Value(ArgType)`：需要额外参数，值类型由 ArgType 指定

### 3. Starlark 集成

实现了完整的 Starlark 互操作：
- `StarlarkValue`：类型标识
- `UnpackValue`：从 Starlark 解包
- `AllocValue`：在 Starlark 堆上分配

## 具体技术实现

### 数据结构

```rust
pub struct Opt {
    pub opt: String,
    pub meta: OptMeta,
    pub required: bool,
}

pub enum OptMeta {
    Flag,
    Value(ArgType),
}
```

### 方法实现

**构造函数**：
```rust
impl Opt {
    pub fn new(opt: String, meta: OptMeta, required: bool) -> Self {
        Self { opt, meta, required }
    }

    pub fn name(&self) -> &str {
        &self.opt
    }
}
```

**Display 实现**：
```rust
// Opt: "opt(-h)"
// OptMeta::Flag: "Flag"
// OptMeta::Value(ArgType::ReadableFile): "ReadableFile"
```

### Starlark 互操作

**Opt 的 StarlarkValue**：
```rust
#[starlark_value(type = "Opt")]
impl<'v> StarlarkValue<'v> for Opt {
    type Canonical = Opt;
}
```

**UnpackValue 实现**：
```rust
impl<'v> UnpackValue<'v> for Opt {
    type Error = starlark::Error;

    fn unpack_value_impl(value: Value<'v>) -> starlark::Result<Option<Self>> {
        // TODO(mbolin): 是否可以不克隆？
        Ok(value.downcast_ref::<Opt>().cloned())
    }
}
```

注意：当前实现需要克隆，因为无法直接消费 Starlark 值。

**AllocValue 实现**：
```rust
impl<'v> AllocValue<'v> for Opt {
    fn alloc_value(self, heap: &'v Heap) -> Value<'v> {
        heap.alloc_simple(self)
    }
}
```

**OptMeta 的 StarlarkValue**：
```rust
#[starlark_value(type = "OptMeta")]
impl<'v> StarlarkValue<'v> for OptMeta {
    type Canonical = OptMeta;
}
```

注意：OptMeta 没有实现 `UnpackValue` 或 `AllocValue`，意味着：
- 不能在 Starlark 中直接创建 OptMeta
- 通过 `opt()` 和 `flag()` 内置函数间接创建

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/opt.rs`

### 依赖文件
- `codex-rs/execpolicy-legacy/src/arg_type.rs`：ArgType

### 被依赖文件
- `codex-rs/execpolicy-legacy/src/policy_parser.rs`：
  - `opt()` 和 `flag()` 内置函数创建 Opt
  - 在 `define_program()` 中解析 options 参数
- `codex-rs/execpolicy-legacy/src/program.rs`：
  - `ProgramSpec` 存储 `allowed_options: HashMap<String, Opt>`
  - `check()` 方法匹配选项
- `codex-rs/execpolicy-legacy/src/valid_exec.rs`：
  - `MatchedOpt` 表示匹配结果

### 使用流程

**策略定义**：
```python
# default.policy
define_program(
    program="head",
    options=[
        opt("-c", ARG_POS_INT),
        opt("-n", ARG_POS_INT),
    ],
    # ...
)
```

**解析流程**：
```
policy_parser.rs:policy_builtins()
  └── opt(name, type, required)
      └── Opt::new(name, OptMeta::Value(type.arg_type()), required.unwrap_or(false))
          └── define_program() 的 options 参数收集
              └── ProgramSpec::new(..., allowed_options, ...)
```

**验证流程**：
```
program.rs:ProgramSpec::check()
  └── 遍历 exec_call.args
      ├── 匹配到 "-n" -> Opt { opt: "-n", meta: Value(PositiveInteger), required: false }
      ├── 期望下一个参数是 PositiveInteger
      └── 创建 MatchedOpt::new("-n", "100", PositiveInteger)?
          └── ArgType::validate("100")
```

## 依赖与外部交互

### 外部 crate
- `starlark`：Starlark 语言集成
  - `ProvidesStaticType`, `NoSerialize`, `Allocative`
  - `StarlarkValue`, `UnpackValue`, `AllocValue`
  - `starlark_value` 宏
- `derive_more`：`Display` derive 宏

### 内部依赖
- `arg_type::ArgType`：OptMeta::Value 的关联类型

## 风险、边界与改进建议

### 风险点

1. **克隆开销**
   ```rust
   fn unpack_value_impl(value: Value<'v>) -> starlark::Result<Option<Self>> {
       Ok(value.downcast_ref::<Opt>().cloned())  // 克隆
   }
   ```
   - 每次从 Starlark 解包都需要克隆
   - 对于大量选项可能有性能影响

2. **NoSerialize 的权衡**
   - Opt 本身不序列化
   - 但 MatchedOpt（验证结果）序列化
   - 这可能导致混淆

3. **选项名格式**
   - 使用原始字符串（如 "-n", "--name"）
   - 不验证格式合法性
   - 可能接受非法选项名（如 "-" 或 "--"）

4. **必需选项检查时机**
   - 在参数解析后检查
   - 如果选项值解析失败，可能先报错再检查必需性

### 边界情况

1. **空选项名**
   ```rust
   Opt::new("".to_string(), OptMeta::Flag, false)
   // 允许，但可能导致意外行为
   ```

2. **重复选项定义**
   ```rust
   // policy_parser.rs 中检查
   if allowed_options.insert(...).is_some() {
       return Err(anyhow::format_err!("duplicate flag: {name}"));
   }
   ```

3. **选项与参数混淆**
   ```rust
   // head -n -1 file.txt
   // -1 被解析为选项而非数值
   // -> OptionFollowedByOptionInsteadOfValue
   ```

### 改进建议

1. **选项名验证**
   ```rust
   impl Opt {
       pub fn new(opt: String, meta: OptMeta, required: bool) -> Result<Self> {
           if !opt.starts_with('-') {
               return Err(Error::InvalidOptionName(opt));
           }
           Ok(Self { opt, meta, required })
       }
   }
   ```

2. **支持更多选项格式**
   ```rust
   pub enum OptMeta {
       Flag,
       Value(ArgType),
       OptionalValue(ArgType),  // 可选值（如 --color[=when]）
       MultipleValues(ArgType), // 多值（如 -I path1 -I path2）
   }
   ```

3. **优化克隆**
   ```rust
   // 使用 Rc<Opt> 或 Arc<Opt> 减少克隆
   pub struct Opt {
       // ...
   }
   
   // 或使用字符串池
   pub struct Opt {
       opt: Symbol,  // 内部字符串类型
       // ...
   }
   ```

4. **添加默认值支持**
   ```rust
   pub struct Opt {
       opt: String,
       meta: OptMeta,
       required: bool,
       default: Option<String>,  // 默认值
   }
   ```

5. **选项分组**
   ```rust
   pub struct OptGroup {
       name: String,
       opts: Vec<Opt>,
       exclusive: bool,  // 是否互斥
   }
   ```

6. **文档改进**
   ```rust
   /// Command line option that takes a value.
   ///
   /// # Examples
   ///
   /// ```rust
   /// let opt = Opt::new("-n".to_string(), OptMeta::Value(ArgType::PositiveInteger), false);
   /// ```
   ```

7. **测试覆盖**
   - 添加边界值测试
   - 测试 Starlark 互操作
   - 测试 Display 实现
