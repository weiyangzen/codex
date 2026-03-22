# standalone_executable.rs 深度研究文档

## 场景与职责

`standalone_executable.rs` 是 `codex-apply-patch` crate 的 CLI 实现模块，负责作为独立可执行文件运行时的全部逻辑。核心职责包括：

1. **进程入口**：定义 `main()` 和 `run_main()` 函数，处理进程生命周期
2. **参数处理**：解析命令行参数，支持直接传参或从 stdin 读取
3. **输入验证**：验证参数数量和编码（UTF-8）
4. **错误处理**：将应用错误转换为进程退出码
5. **输出刷新**：确保 stdout/stderr 在管道中正确排序

该模块是 `apply_patch` 二进制文件的"最后一公里"，连接库逻辑与操作系统进程接口。

## 功能点目的

### 1. 双模式输入支持
- **目的**：支持 `apply_patch 'PATCH'` 和 `echo 'PATCH' | apply_patch` 两种调用方式
- **场景**：
  - 直接传参：简单调用，参数长度受限
  - Stdin 输入：支持大 patch，适合管道操作

### 2. 参数验证
- **目的**：防止错误使用导致的未定义行为
- **检查项**：
  - 参数数量（必须恰好 1 个）
  - 参数编码（必须是有效 UTF-8）
  - Stdin 非空检查

### 3. 退出码管理
- **目的**：向调用方（shell、其他程序）报告执行结果
- **退出码定义**：
  - `0`：成功
  - `1`：应用错误（patch 解析失败、应用失败等）
  - `2`：使用错误（参数错误、stdin 为空等）

### 4. 输出刷新
- **目的**：确保在管道中输出顺序正确
- **实现**：显式调用 `stdout.flush()`

## 具体技术实现

### 核心函数

```rust
/// 永不返回的 main 函数（标准 Rust 二进制入口模式）
pub fn main() -> ! {
    let exit_code = run_main();
    std::process::exit(exit_code);
}

/// 可返回的 main 逻辑（便于测试和库调用）
pub fn run_main() -> i32 {
    // 1. 参数解析
    let mut args = std::env::args_os();
    let _argv0 = args.next();  // 跳过程序名

    // 2. 获取 patch 参数（命令行或 stdin）
    let patch_arg = match args.next() {
        Some(arg) => {
            // 命令行参数模式
            match arg.into_string() {
                Ok(s) => s,
                Err(_) => {
                    eprintln!("Error: apply_patch requires a UTF-8 PATCH argument.");
                    return 1;
                }
            }
        }
        None => {
            // Stdin 模式
            let mut buf = String::new();
            match std::io::stdin().read_to_string(&mut buf) {
                Ok(_) => {
                    if buf.is_empty() {
                        eprintln!("Usage: apply_patch 'PATCH'\n       echo 'PATCH' | apply_patch");
                        return 2;
                    }
                    buf
                }
                Err(err) => {
                    eprintln!("Error: Failed to read PATCH from stdin.\n{err}");
                    return 1;
                }
            }
        }
    };

    // 3. 拒绝多余参数
    if args.next().is_some() {
        eprintln!("Error: apply_patch accepts exactly one argument.");
        return 2;
    }

    // 4. 执行 patch 应用
    let mut stdout = std::io::stdout();
    let mut stderr = std::io::stderr();
    match crate::apply_patch(&patch_arg, &mut stdout, &mut stderr) {
        Ok(()) => {
            let _ = stdout.flush();  // 确保输出顺序
            0
        }
        Err(_) => 1,
    }
}
```

### 退出码定义

| 退出码 | 含义 | 触发场景 |
|--------|------|----------|
| `0` | 成功 | Patch 成功应用 |
| `1` | 应用错误 | Patch 解析失败、文件未找到、上下文不匹配等 |
| `2` | 使用错误 | 参数过多、stdin 为空、UTF-8 解码失败等 |

### 输入处理流程

```
run_main()
    │
    ├──► 获取 args_os()（支持非 UTF-8 程序名）
    │    └──► 跳过 argv0
    │
    ├──► 检查第一个参数
    │    │
    │    ├──► 存在且为有效 UTF-8
    │    │    └──► 使用命令行参数
    │    │
    │    ├──► 存在但非 UTF-8
    │    │    └──► 错误码 1
    │    │
    │    └──► 不存在
    │         └──► 从 stdin 读取
    │              │
    │              ├──► 读取成功且非空
    │              │    └──► 使用 stdin 内容
    │              │
    │              ├──► 读取成功但为空
    │              │    └──► 错误码 2 + 使用说明
    │              │
    │              └──► 读取失败
    │                   └──► 错误码 1 + 错误信息
    │
    ├──► 检查是否有额外参数
    │    └──► 有 → 错误码 2
    │
    └──► 调用 crate::apply_patch()
         │
         ├──► 成功 → 刷新 stdout → 返回 0
         │
         └──► 失败 → 返回 1
```

## 关键代码路径与文件引用

### 模块关系

```
main.rs::main()
    └──► lib.rs::main()  (pub use standalone_executable::main)
         └──► standalone_executable.rs::main()
              └──► standalone_executable.rs::run_main()
                   └──► lib.rs::apply_patch()
```

### 对外暴露 API

| 函数 | 可见性 | 用途 |
|------|--------|------|
| `main()` | pub | 永不返回的进程入口 |
| `run_main()` | pub | 可返回的实现（便于测试） |

### 调用方

| 文件 | 调用方式 |
|------|----------|
| `main.rs` | `codex_apply_patch::main()` |
| `arg0/src/lib.rs` | `codex_apply_patch::main()`（通过 arg0 分发）|

### 依赖

| 模块 | 用途 |
|------|------|
| `lib.rs::apply_patch()` | 执行实际的 patch 应用逻辑 |

## 依赖与外部交互

### 与 lib.rs 的交互

```rust
// 调用库的核心函数
match crate::apply_patch(&patch_arg, &mut stdout, &mut stderr) {
    Ok(()) => { ... }
    Err(_) => { ... }
}
```

### 与 arg0 机制的集成

```rust
// arg0/src/lib.rs
if exe_name == APPLY_PATCH_ARG0 || exe_name == MISSPELLED_APPLY_PATCH_ARG0 {
    codex_apply_patch::main();  // 调用 standalone_executable::main()
}
```

### 与操作系统的交互

| 接口 | 用途 |
|------|------|
| `std::env::args_os()` | 获取命令行参数（支持非 UTF-8）|
| `std::io::stdin()` | 读取 stdin 输入 |
| `std::io::stdout()` | 输出成功信息 |
| `std::io::stderr()` | 输出错误信息 |
| `std::process::exit()` | 终止进程并返回退出码 |

## 风险、边界与改进建议

### 已知风险

1. **Stdin 读取阻塞**
   - 风险：如果没有数据传入 stdin，进程会永远阻塞在 `read_to_string()`
   - 场景：用户直接运行 `apply_patch` 而不传参也不管道输入
   - 现状：无超时机制
   - 缓解：文档说明使用方式

2. **内存消耗**
   - 风险：`read_to_string()` 会将整个 stdin 读入内存
   - 场景：超大 patch 文件
   - 现状：无流式处理
   - 限制：实际 patch 通常不会太大

3. **退出码信息不足**
   - 风险：退出码 1 包含多种不同错误，调用方无法区分
   - 场景：需要程序化区分解析错误和应用错误
   - 现状：所有应用错误都返回 1

### 边界情况处理

| 场景 | 处理 |
|------|------|
| 无参数 + 无 stdin 数据 | 阻塞等待 stdin（直到 EOF 或 Ctrl+D/Ctrl+Z）|
| 空字符串参数 | 传递给 `apply_patch`，由 parser 处理 |
| 非 UTF-8 参数 | 错误码 1 + 错误信息 |
| 多个参数 | 错误码 2 + "accepts exactly one argument" |
| Stdin 读取错误 | 错误码 1 + 详细错误信息 |
| Stdin 为空 | 错误码 2 + 使用说明 |
| Patch 应用失败 | 错误码 1（错误信息已输出到 stderr）|

### 改进建议

1. **超时机制**
   - 为 stdin 读取添加超时，避免无限阻塞
   - 示例：如果 5 秒内无输入，提示用户并退出

2. **流式处理**
   - 对于超大 patch，考虑流式解析
   - 但实现复杂度高，需权衡收益

3. **更详细的退出码**
   - `1`：一般错误
   - `3`：解析错误
   - `4`：应用错误（上下文不匹配等）
   - `5`：IO 错误

4. **信号处理**
   - 添加 Ctrl+C 处理，确保临时文件清理
   - 当前依赖 OS 的进程清理

5. **帮助信息**
   - 添加 `--help` / `-h` 支持
   - 添加 `--version` 支持
   - 当前仅在使用错误时显示简要说明

6. **日志级别**
   - 添加 `-v` / `--verbose` 选项控制输出详细程度
   - 当前所有信息都直接输出

### 设计评价

**优点**：
- ✅ 简洁明了，职责单一
- ✅ 双模式输入（参数/stdin）灵活实用
- ✅ 退出码区分使用错误和应用错误
- ✅ 显式刷新确保管道正确性

**局限性**：
- ⚠️ 无帮助/版本信息
- ⚠️ 无超时机制
- ⚠️ 退出码粒度较粗
- ⚠️ 无日志级别控制

### 测试考虑

当前模块的测试主要通过集成测试覆盖：

- `tests/suite/cli.rs`：测试 CLI 参数和 stdin 模式
- `tests/suite/tool.rs`：测试各种 patch 场景
- `tests/suite/scenarios.rs`：基于 fixture 的端到端测试

单元测试建议：
- 模拟 `args_os()` 的各种输入组合
- 模拟 stdin 的各种状态
- 验证退出码正确性
