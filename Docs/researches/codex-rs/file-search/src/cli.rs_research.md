# codex-rs/file-search/src/cli.rs 研究文档

## 场景与职责

`cli.rs` 是 `codex-file-search` crate 的命令行接口定义模块，负责解析用户通过命令行传入的参数。该文件定义了 `Cli` 结构体，使用 `clap` 派生宏实现命令行参数解析，为文件搜索工具提供用户交互入口。

该模块作为库的一部分（通过 `lib.rs` 中的 `pub use cli::Cli` 导出），既服务于独立的 CLI 二进制程序（`main.rs`），也可被其他 crate 以编程方式使用。

## 功能点目的

### 1. 输出格式控制
- **`json: bool`**（`--json`）：控制输出格式为 JSON 或纯文本。默认 `false` 表示纯文本输出，便于人类阅读；`true` 时输出 JSON 行（JSON Lines），便于程序解析。

### 2. 结果数量限制
- **`limit: NonZero<usize>`**（`-l, --limit`）：限制返回的最大结果数，默认 64。使用 `NonZero` 类型确保至少返回一个结果，避免无意义的零值。

### 3. 搜索目录指定
- **`cwd: Option<PathBuf>`**（`-C, --cwd`）：指定搜索的根目录。默认为当前工作目录（`std::env::current_dir()`）。

### 4. 匹配索引计算
- **`compute_indices: bool`**（`--compute-indices`）：是否计算并输出匹配字符的索引位置。这些索引可用于高亮显示匹配部分，仅在终端输出时有效（见 `main.rs` 中的 `show_indices` 逻辑）。

### 5. 线程数控制
- **`threads: NonZero<usize>`（`--threads`）：指定文件遍历的并行线程数，默认 2。

  **设计考量**：注释说明虽然通常默认使用逻辑 CPU 数，但文件树遍历的 I/O 瓶颈限制了并行收益，经验证超过 2 个线程收益甚微。

### 6. 排除模式
- **`exclude: Vec<String>`**（`-e, --exclude`）：支持多次指定的排除模式，使用 `ArgAction::Append` 收集。这些模式被转换为 `ignore` crate 的 override 规则（`!pattern` 形式）进行过滤。

### 7. 搜索模式
- **`pattern: Option<String>`**：位置参数，指定模糊匹配的模式。为 `Option` 类型允许不指定模式（此时 `main.rs` 会回退到列出目录内容）。

## 具体技术实现

### 依赖与宏
```rust
use clap::ArgAction;
use clap::Parser;
```

使用 `clap` 的派生宏 `#[derive(Parser)]` 自动生成命令行解析逻辑：
- `#[command(version)]`：自动添加 `--version` 标志
- `#[clap(long, default_value = "...")]`：定义长选项和默认值
- `#[arg(short, long, action = ArgAction::Append)]`：定义短/长选项并指定追加行为

### 类型安全设计
- 使用 `NonZero<usize>` 确保 `limit` 和 `threads` 在编译期即保证非零，避免运行时检查。
- `Option<PathBuf>` 和 `Option<String>` 明确表示可选参数。

## 关键代码路径与文件引用

| 功能 | 代码路径 | 关联文件 |
|------|----------|----------|
| CLI 解析 | `Cli::parse()` | `main.rs:13` |
| 字段使用 | `cli.json`, `cli.limit`, `cli.cwd` 等 | `main.rs:14-17`, `lib.rs:220-228` |
| 排除模式处理 | `exclude: Vec<String>` → `build_override_matcher()` | `lib.rs:364-378` |
| 线程数传递 | `threads` → `Nucleo::new()` / `WalkBuilder::threads()` | `lib.rs:182-186`, `lib.rs:426` |
| 索引计算 | `compute_indices` → `Matcher` 创建 | `lib.rs:490` |

## 依赖与外部交互

### 直接依赖
- **`clap`**：命令行参数解析，启用 `derive` feature

### 调用方
- **`main.rs`**：二进制入口，调用 `Cli::parse()` 并消费各字段
- **`lib.rs`**：`run_main()` 函数接收 `Cli` 结构体作为参数

### 与 lib.rs 的交互
`Cli` 结构体通过 `lib.rs` 中的 `pub use cli::Cli` 导出，使得外部 crate 可以直接使用：
```rust
use codex_file_search::Cli;
```

## 风险、边界与改进建议

### 风险点
1. **线程数硬编码默认值**：默认 2 线程基于经验值，但在不同存储介质（SSD vs HDD）或网络文件系统上可能不是最优。
2. **排除模式语法**：用户需要理解 `ignore` crate 的 glob 语法，无文档提示可能导致误用。
3. **模式为空的行为**：`pattern: Option<String>` 允许 `None`，但此行为仅在 `main.rs` 中处理，`lib.rs` 的 `run()` 函数要求非空模式。

### 边界情况
- `limit` 和 `threads` 的 `NonZero` 类型会在传入 0 时 panic，但 clap 的 `default_value` 已确保默认值合法。
- `exclude` 模式为空向量时，`build_override_matcher()` 返回 `None`，跳过 override 处理。

### 改进建议
1. **动态线程数**：可考虑基于可用并行度和文件系统类型自适应调整线程数。
2. **排除模式验证**：在 CLI 解析阶段验证排除模式语法，提前报错。
3. **帮助文本增强**：为 `exclude` 参数添加更详细的 glob 语法说明。
4. **配置文件支持**：对于频繁使用的排除模式，可考虑支持配置文件（如 `.file-search-ignore`）。
