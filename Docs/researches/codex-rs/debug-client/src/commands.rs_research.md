# commands.rs 深度研究文档

## 场景与职责

`commands.rs` 是 debug-client 的命令解析模块，负责将用户输入的行解析为结构化命令或消息。它是用户界面层与核心业务逻辑之间的适配器，提供简单的命令行界面（CLI）解析功能。

**核心定位**：
- 解析交互式输入，区分普通消息和斜杠命令
- 提供类型安全的命令枚举，供主循环处理
- 包含完整的单元测试覆盖

**使用场景**：
- 用户在 `>` 提示符下输入 `:help`、`:new` 等命令
- 用户直接输入文本消息发送给 AI
- 命令参数解析和验证

## 功能点目的

### 1. 输入动作枚举

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputAction {
    Message(String),      // 普通文本消息
    Command(UserCommand), // 结构化命令
}
```

**设计意图**：
- 区分用户意图：发送消息 vs 执行控制命令
- `Message` 包装原始文本，保留用户输入原样
- `Command` 提供类型安全，避免字符串比较

### 2. 用户命令枚举

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UserCommand {
    Help,           // :help, :h
    Quit,           // :quit, :q, :exit
    NewThread,      // :new
    Resume(String), // :resume <thread-id>
    Use(String),    // :use <thread-id>
    RefreshThread,  // :refresh-thread
}
```

**命令设计原则**：
- 简洁：使用单字母别名（`h`, `q`）提升效率
- 直观：命令名称自解释（`new`, `resume`, `use`）
- 参数化：`Resume` 和 `Use` 需要线程 ID 参数

### 3. 解析错误类型

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseError {
    EmptyCommand,                    // ":" 后无内容
    MissingArgument { name: &'static str },  // 缺少必需参数
    UnknownCommand { command: String },      // 未知命令
}
```

**错误信息**（行24-34）：
```rust
impl ParseError {
    pub fn message(&self) -> String {
        match self {
            Self::EmptyCommand => "empty command after ':'".to_string(),
            Self::MissingArgument { name } => format!("missing required argument: {name}"),
            Self::UnknownCommand { command } => format!("unknown command: {command}"),
        }
    }
}
```

**设计特点**：
- 使用 `'static str` 避免分配，参数名是编译期常量
- 错误消息用户友好，直接可用

### 4. 输入解析函数

```rust
pub fn parse_input(line: &str) -> Result<Option<InputAction>, ParseError>
```

**解析逻辑**（行36-76）：

1. **空输入处理**（行37-40）：
   ```rust
   let trimmed = line.trim();
   if trimmed.is_empty() {
       return Ok(None);  // 忽略空行
   }
   ```

2. **消息 vs 命令区分**（行42-44）：
   ```rust
   let Some(command_line) = trimmed.strip_prefix(':') else {
       return Ok(Some(InputAction::Message(trimmed.to_string())));
   };
   ```
   - 不以 `:` 开头 → 普通消息
   - 以 `:` 开头 → 解析为命令

3. **命令分词**（行46-49）：
   ```rust
   let mut parts = command_line.split_whitespace();
   let Some(command) = parts.next() else {
       return Err(ParseError::EmptyCommand);
   };
   ```

4. **命令匹配**（行51-75）：
   ```rust
   match command {
       "help" | "h" => Ok(Some(InputAction::Command(UserCommand::Help))),
       "quit" | "q" | "exit" => Ok(Some(InputAction::Command(UserCommand::Quit))),
       // ...
   }
   ```

## 具体技术实现

### 关键流程

**输入处理流程**：
```
用户输入 → trim() → 检查 ':' 前缀
                ↓
        ┌───────┴───────┐
     无 ':'            有 ':'
        ↓                ↓
   Message      split_whitespace()
                     ↓
                match command
                     ↓
              具体命令处理
```

**参数提取模式**：
```rust
"resume" => {
    let thread_id = parts
        .next()
        .ok_or(ParseError::MissingArgument { name: "thread-id" })?;
    Ok(Some(InputAction::Command(UserCommand::Resume(
        thread_id.to_string(),
    ))))
}
```

### 数据结构关系

```
parse_input
    ↓
Result<Option<InputAction>, ParseError>
    ↓
    ├─ Ok(None)                    // 空输入
    ├─ Ok(Some(InputAction::Message(String)))
    └─ Ok(Some(InputAction::Command(UserCommand)))
            ↓
            ├─ Help
            ├─ Quit
            ├─ NewThread
            ├─ Resume(String)      // 带参数
            ├─ Use(String)         // 带参数
            └─ RefreshThread
```

### 测试覆盖

模块包含完整的单元测试（行78-156），覆盖：

| 测试函数 | 测试场景 |
|----------|----------|
| `parses_message` | 普通消息解析 |
| `parses_help_command` | `:help` 命令 |
| `parses_new_thread` | `:new` 命令 |
| `parses_resume` | `:resume thr_123` 带参数 |
| `parses_use` | `:use thr_456` 带参数 |
| `parses_refresh_thread` | `:refresh-thread` 命令 |
| `rejects_missing_resume_arg` | 缺少参数错误 |
| `rejects_missing_use_arg` | 缺少参数错误 |

**测试风格**：
- 使用 `pretty_assertions::assert_eq` 提供清晰差异
- 测试命名清晰，描述被测行为
- 覆盖正常路径和错误路径

## 关键代码路径与文件引用

### 内部依赖

无直接内部依赖，纯逻辑模块。

### 外部依赖

| Crate | 用途 |
|-------|------|
| `pretty_assertions` | 测试断言美化（dev-dependency）|

### 调用关系

**被调用方**（来自 main.rs）：
```rust
// main.rs:121
match parse_input(&line) {
    Ok(None) => continue,
    Ok(Some(InputAction::Message(message))) => { /* 发送消息 */ }
    Ok(Some(InputAction::Command(command))) => { /* 处理命令 */ }
    Err(err) => { /* 显示错误 */ }
}
```

**命令处理**（main.rs:151-237）：
```rust
fn handle_command(
    command: UserCommand,
    client: &AppServerClient,
    output: &Output,
    approval_policy: AskForApproval,
    cli: &Cli,
) -> bool  // 返回 false 表示退出
```

## 依赖与外部交互

### 与主循环的交互

```
main.rs 输入循环
    ↓
parse_input(line)
    ↓
InputAction::Message → client.send_turn()
    ↓
InputAction::Command → handle_command()
    ↓
    ├─ Help → print_help()
    ├─ Quit → return false (退出循环)
    ├─ NewThread → client.request_thread_start()
    ├─ Resume → client.request_thread_resume()
    ├─ Use → client.use_thread()
    └─ RefreshThread → client.request_thread_list()
```

### 错误处理策略

| 错误类型 | 处理方式 | 用户可见性 |
|----------|----------|------------|
| `EmptyCommand` | 显示错误消息 | 高 |
| `MissingArgument` | 显示错误消息 | 高 |
| `UnknownCommand` | 显示错误消息 | 高 |

所有错误通过 `err.message()` 转换为字符串，经 `output.client_line()` 显示在 stderr。

## 风险、边界与改进建议

### 当前风险

**1. 参数解析简单**
```rust
let thread_id = parts.next().ok_or(...)?;
```
- 仅支持单参数命令
- 不支持带空格的参数（如 `"thread name"`）
- 不支持可选参数或参数默认值

**2. 命令扩展性**
- 使用 `match` 硬编码所有命令
- 添加新命令需要修改多处：枚举、解析、测试

**3. 无命令补全**
- 不支持 Tab 补全
- 不支持历史记录

### 边界情况

**1. 空白字符处理**
```rust
let trimmed = line.trim();  // 去除两端空白
```
- 中间的多余空白由 `split_whitespace()` 处理
- 但参数内部不能包含空白（无引号支持）

**2. 大小写敏感**
```rust
match command {
    "help" | "h" => ...  // 仅小写
}
```
- `:Help` 会被识别为未知命令

**3. 空命令**
```rust
let Some(command_line) = trimmed.strip_prefix(':') else { ... };
```
- 输入 `:` 单独一行 → `EmptyCommand` 错误
- 输入 `:   `（冒号后只有空白）→ 同样错误

### 改进建议

**1. 支持带空格的参数**
```rust
// 建议：添加引号支持
:resume "thread id with spaces"
```

实现思路：
```rust
fn parse_quoted_args(input: &str) -> Vec<String> {
    // 处理引号内的空格
}
```

**2. 命令别名配置**
```rust
// 建议：从配置文件加载别名
[aliases]
h = "help"
ls = "refresh-thread"
```

**3. 帮助自动生成**
```rust
// 建议：从命令枚举派生帮助文本
#[derive(CommandHelp)]
#[help("show this help")]
Help,
```

**4. 模糊匹配**
```rust
// 建议：对未知命令提供建议
UnknownCommand { command } => {
    let suggestions = fuzzy_match(command, KNOWN_COMMANDS);
    Err(ParseError::UnknownCommandWithSuggestions { command, suggestions })
}
```

**5. 参数验证**
```rust
// 建议：验证 thread-id 格式
"resume" => {
    let thread_id = parts.next().ok_or(...)?;
    if !is_valid_thread_id(thread_id) {
        return Err(ParseError::InvalidArgument { 
            name: "thread-id", 
            reason: "must start with 'thr_'" 
        });
    }
    ...
}
```

### 代码质量

**优点**：
- 简单清晰，职责单一
- 完整测试覆盖
- 错误类型明确

**可改进点**：
- 使用 `&'static str` 限制错误消息的动态生成能力
- 可考虑使用 `thiserror` 简化错误定义
- 可考虑使用 `strum` 实现命令字符串的自动映射

### 与 AGENTS.md 规范符合度

检查项目规范：
- ✅ 使用 `format!` 内联变量（行29, 31）
- ✅ 避免 `bool` 或 `Option` 参数（本模块无函数参数）
- ✅ 测试使用 `pretty_assertions::assert_eq`
- ✅ 模块小于 500 LoC（实际 156 行）

无违规项。
