# update_action.rs 研究文档

## 场景与职责

`update_action.rs` 负责检测和定义 Codex CLI 的更新机制。它根据当前安装方式（npm、bun、Homebrew）确定适当的更新命令，为 TUI 的更新提示功能提供支持。

主要使用场景：
- TUI 启动时检测是否有新版本可用
- 根据安装来源确定正确的更新命令
- 在用户选择更新时执行相应的包管理器命令

## 功能点目的

### 1. 更新动作枚举

**定义**：
```rust
pub enum UpdateAction {
    NpmGlobalLatest,    // npm install -g @openai/codex@latest
    BunGlobalLatest,    // bun install -g @openai/codex@latest
    BrewUpgrade,        // brew upgrade --cask codex
}
```

**目的**：抽象不同安装方式的更新命令，使上层代码无需关心具体的包管理器细节。

### 2. 命令生成

**方法**：
- `command_args()`：返回命令行参数元组 `(程序, 参数列表)`
- `command_str()`：返回可显示的命令字符串（使用 shlex 转义）

**示例输出**：
```rust
UpdateAction::NpmGlobalLatest.command_str()
// => "npm install -g @openai/codex"

UpdateAction::BrewUpgrade.command_str()
// => "brew upgrade --cask codex"
```

### 3. 自动检测更新方式

**函数**：
```rust
#[cfg(not(debug_assertions))]
pub(crate) fn get_update_action() -> Option<UpdateAction>
```

**检测逻辑**：
1. 检查环境变量 `CODEX_MANAGED_BY_NPM` → `NpmGlobalLatest`
2. 检查环境变量 `CODEX_MANAGED_BY_BUN` → `BunGlobalLatest`
3. 检查可执行文件路径是否在 `/opt/homebrew` 或 `/usr/local` → `BrewUpgrade`
4. 以上都不匹配 → `None`（无法自动更新）

**调试构建行为**：
- 在 `debug_assertions` 构建中，`get_update_action()` 不存在，避免开发时误触发更新

### 4. 可测试的检测逻辑

**函数**：
```rust
#[cfg(any(not(debug_assertions), test))]
fn detect_update_action(
    is_macos: bool,
    current_exe: &std::path::Path,
    managed_by_npm: bool,
    managed_by_bun: bool,
) -> Option<UpdateAction>
```

**目的**：将检测逻辑与系统调用分离，便于单元测试。

## 具体技术实现

### 环境变量检测

```rust
let managed_by_npm = std::env::var_os("CODEX_MANAGED_BY_NPM").is_some();
let managed_by_bun = std::env::var_os("CODEX_MANAGED_BY_BUN").is_some();
```

这些环境变量由安装脚本或包管理器设置，用于标识安装来源。

### Homebrew 路径检测

```rust
if is_macos && (
    current_exe.starts_with("/opt/homebrew") || 
    current_exe.starts_with("/usr/local")
) {
    Some(UpdateAction::BrewUpgrade)
}
```

- `/opt/homebrew`：Apple Silicon Mac 的 Homebrew 默认路径
- `/usr/local`：Intel Mac 的 Homebrew 默认路径

### 命令字符串生成

使用 `shlex::try_join` 确保命令字符串正确转义：
```rust
pub fn command_str(self) -> String {
    let (command, args) = self.command_args();
    shlex::try_join(std::iter::once(command).chain(args.iter().copied()))
        .unwrap_or_else(|_| format!("{command} {}", args.join(" ")))
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `update_action.rs` | 更新动作定义和检测逻辑 |

### 调用方

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `updates.rs` | `get_update_action()` | 检查更新时确定更新方式 |
| `update_prompt.rs` | `get_update_action()` | 显示更新提示时使用 |

### 依赖关系

```
update_action.rs
├── updates.rs           (调用 get_update_action)
├── update_prompt.rs     (调用 get_update_action)
└── shlex (crate)        (命令字符串转义)
```

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `shlex` | Shell 命令字符串的拼接和转义 |

### 标准库依赖

- `std::env`：读取环境变量
- `std::path::Path`：路径前缀检查

### 内部依赖

无直接内部模块依赖。

## 风险、边界与改进建议

### 已知风险

1. **路径检测局限性**
   - 仅检测 `/opt/homebrew` 和 `/usr/local`，可能漏检自定义 Homebrew 安装路径
   - 缓解：用户可通过环境变量手动指定

2. **环境变量依赖**
   - npm/bun 安装检测依赖环境变量，如果未设置则无法识别
   - 缓解：文档说明需要设置环境变量

3. **Linux Homebrew 支持**
   - 当前 Homebrew 检测仅针对 macOS 路径，Linuxbrew 用户无法自动检测
   - 缓解：可扩展路径检测支持 Linuxbrew 默认路径

### 边界条件

1. **可执行文件路径获取失败**
   - `std::env::current_exe()` 可能失败，使用 `unwrap_or_default()` 返回空路径
   - 空路径不会匹配任何 Homebrew 前缀，返回 `None`

2. **非标准安装方式**
   - 从源码编译、手动复制二进制文件等方式无法自动检测
   - 返回 `None`，不显示更新提示

### 改进建议

1. **扩展 Homebrew 检测**
   - 添加 Linuxbrew 路径支持（`~/.linuxbrew`）
   - 考虑使用 `brew --prefix` 命令动态检测

2. **配置化更新命令**
   - 允许用户在配置文件中指定自定义更新命令

3. **更多包管理器支持**
   - 添加对 `cargo install`、`pacman`、`apt` 等的支持

4. **版本兼容性检查**
   - 在执行更新前检查新版本与当前系统的兼容性

5. **改进错误处理**
   - 当 `current_exe()` 失败时，尝试其他方式确定安装来源
