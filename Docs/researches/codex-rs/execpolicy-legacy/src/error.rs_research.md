# error.rs 研究文档

## 场景与职责

`error.rs` 定义了执行策略引擎的统一错误类型系统，负责：

1. **错误分类**：将各种验证失败场景分类为具体的错误类型
2. **结构化错误信息**：提供详细的错误上下文，便于调试和用户反馈
3. **序列化支持**：支持将错误序列化为 JSON，供 CLI 输出
4. **类型别名**：提供方便的 `Result<T>` 类型别名

该模块是整个策略引擎的错误处理基础，确保所有错误都能被一致地处理和报告。

## 功能点目的

### 1. Error 枚举

定义了 20 种具体错误类型，覆盖策略验证的各个阶段：

#### 策略定义错误
- `NoSpecForProgram`：程序没有对应的策略规则
- `MultipleVarargPatterns`：规则包含多个可变参数模式

#### 选项解析错误
- `OptionMissingValue`：选项需要值但未提供
- `OptionFollowedByOptionInsteadOfValue`：选项值位置是另一个选项
- `UnknownOption`：遇到未定义的选项
- `MissingRequiredOptions`：缺少必需的选项
- `DoubleDashNotSupportedYet`：`--` 分隔符暂不支持

#### 参数解析错误
- `UnexpectedArguments`：多余的未匹配参数
- `NotEnoughArgs`：参数数量不足
- `VarargMatcherDidNotMatchAnything`：可变参数模式未匹配任何参数

#### 参数验证错误
- `LiteralValueDidNotMatch`：字面量值不匹配
- `EmptyFileName`：文件名为空
- `InvalidPositiveInteger`：无效的正整数
- `SedCommandNotProvablySafe`：sed 命令不安全

#### 文件路径错误
- `ReadablePathNotInReadableFolders`：可读路径不在允许的目录中
- `WriteablePathNotInWriteableFolders`：可写路径不在允许的目录中
- `CannotCheckRelativePath`：无法检查相对路径（缺少 CWD）
- `CannotCanonicalizePath`：路径规范化失败

#### 内部错误
- `InternalInvariantViolation`：内部不变量被破坏
- `RangeStartExceedsEnd` / `RangeEndOutOfBounds`：范围错误
- `PrefixOverlapsSuffix`：前缀和后缀参数重叠

### 2. Result 类型别名

```rust
pub type Result<T> = std::result::Result<T, Error>;
```

提供统一的错误类型，简化函数签名。

## 具体技术实现

### 数据结构

```rust
#[serde_as]
#[derive(Debug, Eq, PartialEq, Serialize)]
#[serde(tag = "type")]  // 使用内部标签序列化
pub enum Error {
    NoSpecForProgram { program: String },
    OptionMissingValue { program: String, option: String },
    // ... 其他变体
    CannotCanonicalizePath {
        file: String,
        #[serde_as(as = "DisplayFromStr")]
        error: std::io::ErrorKind,
    },
}
```

### 序列化特性

**#[serde(tag = "type")]**：
- 使用内部标签模式序列化
- JSON 输出示例：
```json
{
  "type": "NoSpecForProgram",
  "program": "unknown_cmd"
}
```

**serde_as 和 DisplayFromStr**：
- 用于 `CannotCanonicalizePath` 中的 `std::io::ErrorKind`
- 将错误类型转换为字符串表示

### 错误变体详解

**参数相关错误**：
```rust
UnexpectedArguments {
    program: String,
    args: Vec<PositionalArg>,  // 包含原始索引和值
}
```

**文件路径错误**：
```rust
ReadablePathNotInReadableFolders {
    file: PathBuf,
    folders: Vec<PathBuf>,  // 允许的目录列表
}
```

**内部错误**：
```rust
InternalInvariantViolation {
    message: String,  // 描述被破坏的不变量
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/error.rs`

### 依赖文件
- 无直接依赖（基础类型）

### 被依赖文件

| 文件 | 使用场景 |
|------|----------|
| `arg_matcher.rs` | 作为返回类型 |
| `arg_resolver.rs` | 各种解析错误 |
| `arg_type.rs` | 参数验证错误 |
| `execv_checker.rs` | 文件路径检查错误 |
| `policy.rs` | 策略检查错误 |
| `policy_parser.rs` | 解析错误转换 |
| `program.rs` | 程序验证错误 |
| `valid_exec.rs` | 匹配参数创建错误 |
| `main.rs` | 错误序列化输出 |

### 错误传播路径

```
program.rs:ProgramSpec::check()
  ├── 选项解析错误 -> Error::UnknownOption, Error::OptionMissingValue
  ├── arg_resolver::resolve_observed_args_with_patterns()
  │   └── Error::NotEnoughArgs, Error::UnexpectedArguments, etc.
  └── MatchedArg::new()
      └── ArgType::validate()
          └── Error::LiteralValueDidNotMatch, Error::InvalidPositiveInteger, etc.

execv_checker.rs:ExecvChecker::check()
  └── Error::ReadablePathNotInReadableFolders, etc.

main.rs:check_command()
  └── 序列化 Error 为 JSON 输出
```

## 依赖与外部交互

### 外部 crate
- `serde`：序列化支持
  - `Serialize` 派生
  - `serde_as` 属性
- `serde_with`：提供 `DisplayFromStr`
- `std::path::PathBuf`：文件路径类型

### 内部依赖
- `arg_resolver::PositionalArg`：用于 `UnexpectedArguments` 和 `NotEnoughArgs`
- `arg_matcher::ArgMatcher`：用于 `NotEnoughArgs` 和 `VarargMatcherDidNotMatchAnything`

## 风险、边界与改进建议

### 风险点

1. **错误信息泄露**
   - `UnexpectedArguments` 和 `NotEnoughArgs` 包含完整的参数列表
   - 可能泄露敏感信息（如密码、密钥）
   - 建议：添加参数脱敏或截断

2. **PathBuf 序列化**
   - 使用默认的 PathBuf 序列化
   - 在非 UTF-8 路径上可能失败

3. **io::ErrorKind 转换**
   - 使用 `DisplayFromStr` 序列化
   - 反序列化时可能丢失具体信息

4. **错误类型膨胀**
   - 20 种错误类型可能过多
   - 某些类型可以合并（如范围错误）

### 边界情况

1. **空字符串处理**
   ```rust
   Error::EmptyFileName {}  // 无上下文，不知道哪个参数
   ```
   - 建议：添加参数索引或名称

2. **内部错误暴露**
   ```rust
   InternalInvariantViolation { message: String }
   ```
   - 可能暴露实现细节
   - 建议：生产环境隐藏详细信息

3. **范围错误**
   ```rust
   RangeStartExceedsEnd { start: usize, end: usize }
   RangeEndOutOfBounds { end: usize, len: usize }
   ```
   - 这些是内部错误，用户不应看到
   - 建议：转换为更友好的错误

### 改进建议

1. **错误分类层级**
   ```rust
   pub enum Error {
       UserInput(UserInputError),      // 用户可修复
       PolicyViolation(PolicyError),   // 策略限制
       Internal(InternalError),        // 程序错误
       Io(std::io::Error),             // 系统错误
   }
   ```

2. **添加错误代码**
   ```rust
   impl Error {
       pub fn code(&self) -> &'static str {
           match self {
               Error::NoSpecForProgram { .. } => "E001",
               Error::UnknownOption { .. } => "E002",
               // ...
           }
       }
   }
   ```

3. **敏感信息处理**
   ```rust
   UnexpectedArguments {
       program: String,
       args: Vec<MaskedArg>,  // 脱敏后的参数
   }
   ```

4. **错误链支持**
   ```rust
   pub enum Error {
       // ...
       #[serde(skip)]
       Cause { source: Box<Error>, context: String },
   }
   ```

5. **本地化支持**
   ```rust
   impl Error {
       pub fn message(&self, locale: &str) -> String {
           // 根据语言返回本地化消息
       }
   }
   ```

6. **错误恢复提示**
   ```rust
   impl Error {
       pub fn suggestion(&self) -> Option<String> {
           match self {
               Error::UnknownOption { option, .. } => {
                   Some(format!("Did you mean '{}'?, try '--help'", option))
               }
               _ => None,
           }
       }
   }
   ```

7. **测试覆盖**
   - 添加每个错误类型的序列化/反序列化测试
   - 验证错误消息的格式
   - 测试边界值（如极大索引）

8. **文档改进**
   - 为每个错误类型添加示例
   - 说明常见原因和解决方法
