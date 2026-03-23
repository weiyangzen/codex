# main.rs 研究文档

## 场景与职责

`main.rs` 是 `codex-linux-sandbox` 二进制可执行文件的入口点。它作为 Linux 沙箱辅助程序的极简入口，主要职责是：

1. **程序入口委托**：将控制权立即委托给库中的 `run_main()` 函数
2. **环境保留**：确保当前工作目录、环境变量和命令行参数在执行过程中被保留
3. **无返回执行**：通过 `-> !` 返回类型表明该函数永不返回（通过 exec 或 panic 结束）

## 功能点目的

### 单一职责：入口委托

该文件 intentionally 保持极简，所有实际逻辑都在 `lib.rs` 和 `linux_run_main.rs` 中实现。这种设计：

- **分离关注点**：入口点与实现分离，便于测试和复用
- **库二进制统一**：同一套代码既可作为库使用，也可作为独立二进制运行
- **环境透明**：注释明确指出调用方负责确保 cwd、env 和 args 正确

## 具体技术实现

### 代码结构

```rust
/// Note that the cwd, env, and command args are preserved in the ultimate call
/// to `execv`, so the caller is responsible for ensuring those values are
/// correct.
fn main() -> ! {
    codex_linux_sandbox::run_main()
}
```

### 关键技术细节

1. **返回类型 `-> !`**：
   - 表示发散函数（diverging function）
   - `run_main()` 内部通过 `execvp` 或 `panic` 终止，不会正常返回
   - 符合 Unix 工具链的设计惯例

2. **crate 名称使用**：
   - 使用 `codex_linux_sandbox`（下划线）而非包名 `codex-linux-sandbox`
   - 这是 Rust 的 crate 名称规范化规则（连字符替换为下划线）

3. **环境保留保证**：
   - 注释明确说明 `execv` 调用会保留当前工作目录和环境变量
   - 调用方（通常是 Codex CLI 或 TUI）需要确保这些值在调用前已正确设置

## 关键代码路径与文件引用

### 调用链

```
main.rs (二进制入口)
    ↓
lib.rs::run_main() (库入口)
    ↓
linux_run_main.rs::run_main() (实际实现)
    ↓
    ├─→ bwrap.rs (bubblewrap 参数构建)
    ├─→ landlock.rs (seccomp/Landlock 应用)
    ├─→ launcher.rs (bwrap 执行)
    └─→ proxy_routing.rs (代理路由设置)
```

### 相关文件

| 文件 | 关系 |
|------|------|
| `lib.rs` | 定义 `run_main()` 公共接口，条件编译分发到平台特定实现 |
| `linux_run_main.rs` | Linux 特定的 `run_main()` 实现，包含 CLI 解析和沙箱编排逻辑 |
| `Cargo.toml` | 定义二进制目标和库目标的双目标配置 |

### Cargo.toml 配置

```toml
[[bin]]
name = "codex-linux-sandbox"
path = "src/main.rs"

[lib]
name = "codex_linux_sandbox"
path = "src/lib.rs"
```

## 依赖与外部交互

### 编译时依赖

- 无直接 `use` 语句，唯一依赖是通过 crate 名称调用 `codex_linux_sandbox::run_main()`
- 依赖 `lib.rs` 中定义并导出的公共接口

### 运行时环境

- 需要 Linux 操作系统（通过 `#[cfg(target_os = "linux")]` 在 lib.rs 中控制）
- 需要适当的权限执行沙箱操作（如 `CAP_SYS_ADMIN` 或使用 setuid 的 bubblewrap）

### 调用方约定

根据注释，调用方需要确保：
1. **CWD**：当前工作目录是预期的沙箱策略工作目录
2. **环境变量**：`CODEX_HOME` 等关键变量已设置
3. **命令行参数**：传递给沙箱内程序的参数已正确格式化

## 风险、边界与改进建议

### 当前风险

1. **极简设计的双刃剑**：
   - 优点：代码清晰，职责单一
   - 风险：错误处理完全依赖下游，入口点无额外保护

2. **平台限制**：
   - 非 Linux 平台编译时 `run_main()` 会直接 panic
   - 交叉编译需要特别注意目标平台设置

### 边界情况

1. **信号处理**：
   - 入口点无信号屏蔽设置，依赖下游处理
   - 在 fork/exec 前可能被信号中断

2. **文件描述符**：
   - 继承调用方的文件描述符表
   - 可能继承不必要的 FD，增加攻击面

### 改进建议

1. **添加最小错误处理**：
   ```rust
   fn main() -> ! {
       // 建议：添加最小化的启动日志或错误包装
       if cfg!(not(target_os = "linux")) {
           eprintln!("codex-linux-sandbox is only supported on Linux");
           std::process::exit(1);
       }
       codex_linux_sandbox::run_main()
   }
   ```

2. **FD 清理**：
   - 考虑在入口点关闭非标准 FD（类似 `close_range`）
   - 或设置 `O_CLOEXEC` 标志

3. **信号屏蔽**：
   - 考虑在入口点临时屏蔽信号，防止在关键初始化期间被中断

4. **文档增强**：
   - 添加关于调用约定的更多文档
   - 说明预期的调用上下文（如从 Codex CLI 调用 vs 手动调用）

5. **版本信息**：
   - 考虑添加 `--version` 支持（需要在 `run_main` 中处理或在此处预处理）
   ```rust
   fn main() -> ! {
       if std::env::args().nth(1).as_deref() == Some("--version") {
           println!(env!("CARGO_PKG_VERSION"));
           std::process::exit(0);
       }
       codex_linux_sandbox::run_main()
   }
   ```
