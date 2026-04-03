# exec_call.rs 研究文档

## 场景与职责

`exec_call.rs` 定义了执行策略引擎中最基础的输入数据结构，负责：

1. **命令表示**：封装程序名和参数列表，表示一个待验证的 execv 调用
2. **构造便利**：提供简单的构造函数，便于测试和 CLI 使用
3. **格式化输出**：实现 Display trait，便于日志和调试
4. **序列化支持**：支持 JSON 序列化，用于 CLI 输入输出

该模块是整个策略验证流程的入口数据结构，所有验证都围绕 `ExecCall` 进行。

## 功能点目的

### 1. ExecCall 结构

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ExecCall {
    pub program: String,      // 程序名（如 "ls"）
    pub args: Vec<String>,    // 参数列表（如 ["-l", "foo"]）
}
```

**设计决策**：
- 使用 `String` 而非 `&str`：拥有所有权，避免生命周期问题
- 使用 `Vec<String>` 而非 `Vec<&str>`：支持从各种来源构造
- 实现 `Clone`：便于在错误和结果中复制
- 实现 `Serialize`：支持 JSON 序列化

### 2. 构造函数

```rust
impl ExecCall {
    pub fn new(program: &str, args: &[&str]) -> Self {
        Self {
            program: program.to_string(),
            args: args.iter().map(|&s| s.into()).collect(),
        }
    }
}
```

**使用场景**：
- 测试代码：快速创建测试用例
- CLI 解析：从命令行参数构造

### 3. Display 实现

```rust
impl Display for ExecCall {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.program)?;
        for arg in &self.args {
            write!(f, " {arg}")?;
        }
        Ok(())
    }
}
```

**输出格式**：`program arg1 arg2 ...`
- 简单空格分隔
- 不进行 shell 转义（仅用于显示）

## 具体技术实现

### 数据结构

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ExecCall {
    pub program: String,
    pub args: Vec<String>,
}
```

### 方法实现

**new()**：
```rust
pub fn new(program: &str, args: &[&str]) -> Self
```
- 接受字符串切片，便于测试使用字面量
- 内部转换为 `String` 和 `Vec<String>`

**Display**：
```rust
impl Display for ExecCall {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result
```
- 格式：`program arg1 arg2 ...`
- 注意：参数中的空格不会被转义

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/exec_call.rs`

### 依赖文件
- 无直接依赖（基础类型）

### 被依赖文件

| 文件 | 使用场景 |
|------|----------|
| `policy.rs` | `Policy::check(exec_call)` 的输入 |
| `program.rs` | `ProgramSpec::check(exec_call)` 的输入 |
| `execv_checker.rs` | `ExecvChecker::r#match(exec_call)` 的输入 |
| `main.rs` | CLI 解析为 `ExecArg`，转换为 ExecCall |
| `error.rs` | 多个错误变体包含 ExecCall |
| `tests/suite/*.rs` | 测试用例构造 |

### 数据流

```
CLI / 测试代码
  └── ExecCall::new("ls", &["-l", "foo"])
      └── policy.check(&exec_call)
          └── program_spec.check(exec_call)
              ├── 解析选项
              ├── 解析位置参数
              └── 返回 MatchedExec
                  ├── Match { exec: ValidExec }
                  ├── Forbidden { cause, reason }
                  └── 错误（包含原始 ExecCall）
```

### 序列化示例

```json
{
  "program": "ls",
  "args": ["-l", "foo"]
}
```

用于：
- CLI JSON 输入（`check-json` 子命令）
- 错误输出中的上下文信息
- 日志记录

## 依赖与外部交互

### 外部 crate
- `serde`：`Serialize` 派生
- `std::fmt::Display`：格式化输出

### 内部依赖
- 无

## 风险、边界与改进建议

### 风险点

1. **无参数验证**
   - `ExecCall` 接受任意字符串
   - 不验证：空程序名、空参数、非法字符等
   - 验证在后续阶段进行

2. **Display 不转义**
   ```rust
   let call = ExecCall::new("echo", &["hello world"]);
   println!("{}", call);  // 输出: echo hello world
   // 无法区分: echo "hello world" 和 echo hello world
   ```

3. **大小写敏感**
   - 程序名大小写敏感
   - `ExecCall::new("LS", &[])` 和 `"ls"` 被视为不同

4. **路径解析**
   - 不包含路径信息
   - `/bin/ls` 和 `ls` 被视为不同程序

### 边界情况

1. **空程序名**
   ```rust
   ExecCall::new("", &[])  // 允许，但会导致 NoSpecForProgram 错误
   ```

2. **空参数列表**
   ```rust
   ExecCall::new("ls", &[])  // 常见情况，表示无参数调用
   ```

3. **包含空字符串的参数**
   ```rust
   ExecCall::new("echo", &[""])  // 允许，表示空参数
   ```

4. **参数包含特殊字符**
   ```rust
   ExecCall::new("echo", &["$HOME", "`whoami`"])  // 原样存储，不解释
   ```

### 改进建议

1. **添加验证构造函数**
   ```rust
   impl ExecCall {
       pub fn try_new(program: &str, args: &[&str]) -> Result<Self, Error> {
           if program.is_empty() {
               return Err(Error::EmptyProgramName);
           }
           // 其他验证...
           Ok(Self::new(program, args))
       }
   }
   ```

2. **改进 Display 实现**
   ```rust
   impl Display for ExecCall {
       fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
           write!(f, "{}", shell_escape(&self.program))?;
           for arg in &self.args {
               write!(f, " {}", shell_escape(arg))?;
           }
           Ok(())
       }
   }
   ```

3. **添加元数据**
   ```rust
   pub struct ExecCall {
       pub program: String,
       pub args: Vec<String>,
       pub working_dir: Option<PathBuf>,  // 添加工作目录
       pub env: Option<HashMap<String, String>>,  // 添加环境变量
   }
   ```

4. **支持反序列化**
   ```rust
   #[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
   pub struct ExecCall {
       // ...
   }
   ```

5. **添加辅助方法**
   ```rust
   impl ExecCall {
       pub fn arg(&self, index: usize) -> Option<&str> {
           self.args.get(index).map(|s| s.as_str())
       }
       
       pub fn first_arg(&self) -> Option<&str> {
           self.args.first().map(|s| s.as_str())
       }
       
       pub fn is_empty(&self) -> bool {
           self.args.is_empty()
       }
   }
   ```

6. **实现 From  trait**
   ```rust
   impl From<Vec<String>> for ExecCall {
       fn from(mut parts: Vec<String>) -> Self {
           if parts.is_empty() {
               Self::new("", &[])
           } else {
               let program = parts.remove(0);
               Self { program, args: parts }
           }
       }
   }
   ```

7. **测试覆盖**
   - 添加边界值测试
   - 测试特殊字符处理
   - 测试序列化/反序列化
