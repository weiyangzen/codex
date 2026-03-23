# main.rs 研究文档

## 文件信息
- **路径**: `codex-rs/exec/src/main.rs`
- **大小**: ~2,587 bytes
- **定位**: `codex-exec` 二进制入口点

---

## 一、场景与职责

### 1.1 核心定位
`main.rs` 是 `codex-exec` 二进制文件的**唯一入口点**，负责：
1. 解析顶层命令行参数
2. 处理 `arg0` 分发（支持作为 `codex-linux-sandbox` 调用）
3. 委托给 `lib.rs` 的 `run_main` 函数执行实际逻辑

### 1.2 特殊设计：Arg0 分发

该文件的关键设计是支持**单一二进制文件多用途**：

```rust
//! When this CLI is invoked normally, it parses the standard `codex-exec` CLI
//! options and launches the non-interactive Codex agent. However, if it is
//! invoked with arg0 as `codex-linux-sandbox`, we instead treat the invocation
//! as a request to run the logic for the standalone `codex-linux-sandbox`
//! executable (i.e., parse any -s args and then run a *sandboxed* command under
//! Landlock + seccomp).
```

这意味着同一个二进制文件可以通过不同名称调用来执行不同功能：
- `codex-exec`: 标准非交互式 Agent
- `codex-linux-sandbox`: 沙盒执行器（通过 `codex_arg0` crate 处理）

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    调用方式                                  │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │ $ codex-exec ...    │    │ $ codex-linux-sandbox ...   │ │
│  └──────────┬──────────┘    └─────────────┬───────────────┘ │
│             │                             │                 │
│             ▼                             ▼                 │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │   main.rs (arg0)    │    │  main.rs (arg0_dispatch)    │ │
│  │   TopCli::parse()   │    │  codex_arg0::dispatch()     │ │
│  └──────────┬──────────┘    └─────────────┬───────────────┘ │
│             │                             │                 │
│             ▼                             ▼                 │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │   lib.rs run_main() │    │  sandbox 逻辑 (其他 crate)   │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 顶层 CLI 结构

```rust
#[derive(Parser, Debug)]
struct TopCli {
    #[clap(flatten)]
    config_overrides: CliConfigOverrides,  // 全局 -c 配置覆盖

    #[clap(flatten)]
    inner: Cli,                            // 标准 codex-exec 参数
}
```

**设计目的**: 
- 将全局配置覆盖（如 `-c key=value`）提升到最顶层
- 支持在所有子命令前指定全局参数

### 2.2 参数合并逻辑

```rust
let top_cli = TopCli::parse();
let mut inner = top_cli.inner;
inner
    .config_overrides
    .raw_overrides
    .splice(0..0, top_cli.config_overrides.raw_overrides);
```

将顶层解析的 `config_overrides` 合并到 `inner` CLI 结构中，确保下游逻辑无需关心参数来源。

---

## 三、具体技术实现

### 3.1 Arg0 分发机制

```rust
fn main() -> anyhow::Result<()> {
    arg0_dispatch_or_else(|arg0_paths: Arg0DispatchPaths| async move {
        // 标准 codex-exec 逻辑
    })
}
```

- `arg0_dispatch_or_else`: 来自 `codex_arg0` crate
- 如果 `arg0` 是 `codix-linux-sandbox`，执行沙盒逻辑
- 否则执行闭包内的标准逻辑

### 3.2 异步运行时

使用 `async move` 闭包，由 `arg0_dispatch_or_else` 内部处理异步运行时（通常是 `tokio`）。

---

## 四、关键代码路径与文件引用

### 4.1 调用链

```
main.rs
    │
    ├──▶ arg0_dispatch_or_else() [codex_arg0]
    │       │
    │       ├──▶ 如果是 codex-linux-sandbox → 沙盒逻辑
    │       │
    │       └──▶ 否则执行闭包
    │               │
    │               ├──▶ TopCli::parse() [clap]
    │               │
    │               ├──▶ 合并 config_overrides
    │               │
    │               └──▶ run_main(inner, arg0_paths) [lib.rs]
    │
    └──▶ 返回 anyhow::Result<()>
```

### 4.2 关联文件

| 文件 | 关系 | 说明 |
|-----|------|------|
| `lib.rs` | 被调用 | 实现实际的 `run_main` 函数 |
| `cli.rs` | 依赖 | 定义 `Cli` 和 `CliConfigOverrides` 结构 |
| `codex_arg0` crate | 依赖 | 提供 `arg0_dispatch_or_else` 和 `Arg0DispatchPaths` |

---

## 五、依赖与外部交互

### 5.1 外部 Crate 依赖

```toml
[dependencies]
clap = { workspace = true, features = ["derive"] }
codex_arg0 = { workspace = true }
codex_exec = { path = "../" }  # 自身 lib
codex_utils_cli = { workspace = true }
anyhow = { workspace = true }
```

### 5.2 运行时依赖

- 需要 `tokio` 运行时（由 `arg0_dispatch_or_else` 初始化）
- 依赖 `clap` 进行参数解析

---

## 六、风险、边界与改进建议

### 6.1 当前风险

1. **参数顺序敏感**: 虽然支持全局参数，但复杂的参数顺序仍可能导致解析意外
2. **Arg0 依赖**: 功能依赖程序被正确命名/链接，直接复制文件可能破坏功能

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 通过符号链接调用 | 解析符号链接目标名称 |
| 直接运行 `./codex-exec` | 正常工作 |
| 重命名为其他名称 | 作为标准 codex-exec 运行 |

### 6.3 测试覆盖

当前测试：

```rust
#[test]
fn top_cli_parses_resume_prompt_after_config_flag() {
    // 验证：resume 子命令 + 全局标志 + 配置覆盖 + prompt
    // 确保复杂参数序列解析正确
}
```

**测试价值**: 验证 clap 的 `global = true` 和参数合并逻辑在实际复杂场景下的正确性。

### 6.4 改进建议

| 优先级 | 建议 | 理由 |
|-------|------|------|
| 低 | 添加 `--version` 处理 | 当前依赖 clap 默认行为 |
| 低 | 显式 Tokio 运行时创建 | 当前隐藏在 arg0 crate 中，透明度低 |

### 6.5 代码简洁性

该文件保持**极简设计**（仅 42 行有效代码），符合 Unix 哲学：
- 单一职责：仅处理入口分发
- 不重复实现：所有逻辑委托给 lib.rs
- 清晰分层：main.rs → lib.rs → 各模块
