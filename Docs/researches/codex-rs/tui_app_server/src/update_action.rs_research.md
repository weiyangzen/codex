# update_action.rs 研究文档

## 场景与职责

`update_action.rs` 是 Codex TUI 应用服务器的自动更新检测和执行模块，负责：

1. **更新方式检测**：根据当前可执行文件的安装方式（npm、bun、Homebrew）确定合适的更新命令
2. **更新命令生成**：生成特定于包管理器的更新命令行
3. **环境感知**：通过环境变量和文件路径推断安装来源

该模块仅在非调试构建（`not(debug_assertions)`）中启用实际检测逻辑，调试构建中更新检测被禁用。

## 功能点目的

### 1. 更新动作枚举（UpdateAction）

**目的**：抽象不同安装方式的更新操作。

**变体**：
- `NpmGlobalLatest`：通过 npm 全局安装最新版本
- `BunGlobalLatest`：通过 bun 全局安装最新版本
- `BrewUpgrade`：通过 Homebrew 升级

### 2. 命令生成

**目的**：将 `UpdateAction` 转换为可执行的命令行。

**方法**：
- `command_args()`：返回命令和参数元组
- `command_str()`：返回格式化的命令字符串（使用 `shlex` 处理转义）

### 3. 安装方式检测

**目的**：自动识别 Codex CLI 的安装来源。

**检测逻辑**：
1. 检查环境变量 `CODEX_MANAGED_BY_NPM` 或 `CODEX_MANAGED_BY_BUN`
2. 检查可执行文件路径是否以 `/opt/homebrew` 或 `/usr/local` 开头（macOS Homebrew）

## 具体技术实现

### 数据结构

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpdateAction {
    NpmGlobalLatest,
    BunGlobalLatest,
    BrewUpgrade,
}
```

### 命令映射

| UpdateAction | 命令 | 参数 |
|--------------|------|------|
| `NpmGlobalLatest` | `npm` | `["install", "-g", "@openai/codex"]` |
| `BunGlobalLatest` | `bun` | `["install", "-g", "@openai/codex"]` |
| `BrewUpgrade` | `brew` | `["upgrade", "--cask", "codex"]` |

### 检测算法

```rust
fn detect_update_action(
    is_macos: bool,
    current_exe: &std::path::Path,
    managed_by_npm: bool,
    managed_by_bun: bool,
) -> Option<UpdateAction> {
    if managed_by_npm {
        Some(UpdateAction::NpmGlobalLatest)
    } else if managed_by_bun {
        Some(UpdateAction::BunGlobalLatest)
    } else if is_macos
        && (current_exe.starts_with("/opt/homebrew") || current_exe.starts_with("/usr/local"))
    {
        Some(UpdateAction::BrewUpgrade)
    } else {
        None
    }
}
```

### 条件编译

```rust
#[cfg(not(debug_assertions))]
pub(crate) fn get_update_action() -> Option<UpdateAction> {
    // 实际检测逻辑
}

#[cfg(debug_assertions)]
pub(crate) fn get_update_action() -> Option<UpdateAction> {
    None // 调试构建禁用更新检测
}
```

## 关键代码路径与文件引用

### 调用方

| 文件 | 用途 |
|------|------|
| `update_prompt.rs` | 在 TUI 启动时检查更新并显示提示 |
| `updates.rs` | 获取最新版本信息时确定更新源 |

### 被调用方

无外部依赖，纯逻辑模块。

### 测试

模块包含单元测试，验证检测逻辑：

```rust
#[test]
fn detects_update_action_without_env_mutation() {
    // 测试各种组合：
    // - 无环境变量，任意路径 -> None
    // - CODEX_MANAGED_BY_NPM=1 -> NpmGlobalLatest
    // - CODEX_MANAGED_BY_BUN=1 -> BunGlobalLatest
    // - macOS + /opt/homebrew/bin/codex -> BrewUpgrade
    // - macOS + /usr/local/bin/codex -> BrewUpgrade
}
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `shlex` | 安全地拼接命令行参数，处理特殊字符转义 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `CODEX_MANAGED_BY_NPM` | 指示由 npm 管理安装 |
| `CODEX_MANAGED_BY_BUN` | 指示由 bun 管理安装 |

### 系统交互

- 读取 `/proc/self/exe` 或等效机制获取当前可执行文件路径
- 路径匹配用于推断 Homebrew 安装

## 风险、边界与改进建议

### 已知风险

1. **检测误报**：
   - 如果用户手动将可执行文件复制到 `/usr/local/bin`，会被误判为 Homebrew 安装
   - 环境变量可能被错误设置

2. **平台限制**：
   - Homebrew 检测仅在 macOS 上启用
   - Linux 和 Windows 的包管理器（如 apt、chocolatey）未支持

3. **硬编码包名**：
   - npm/bun 包名 `@openai/codex` 硬编码
   - Homebrew cask 名 `codex` 硬编码

### 边界条件

1. **路径匹配**：
   - 使用 `starts_with` 进行路径匹配，可能匹配到子目录
   - 例如 `/opt/homebrew-custom/bin/codex` 会被错误匹配

2. **符号链接**：
   - 如果可执行文件是符号链接，`current_exe()` 返回的是链接目标路径
   - 这可能导致检测与预期不符

### 改进建议

1. **更精确的 Homebrew 检测**：
   ```rust
   // 检查是否为真正的 Homebrew 安装
   fn is_homebrew_install(exe: &Path) -> bool {
       // 检查 exe 是否由 Homebrew 的 cellar 管理
       exe.starts_with("/opt/homebrew/Cellar") || 
       exe.starts_with("/usr/local/Cellar") ||
       // 或者检查是否为 Homebrew 创建的符号链接
       is_homebrew_symlink(exe)
   }
   ```

2. **支持更多包管理器**：
   - Linux：apt、dnf、pacman、nix
   - Windows：chocolatey、scoop、winget

3. **配置覆盖**：
   - 允许用户通过配置文件显式指定更新方式
   ```toml
   [update]
   method = "npm"  # 或 "bun", "brew", "manual"
   ```

4. **版本锁定**：
   - 当前总是更新到最新版本，考虑支持锁定到特定主版本

5. **错误处理增强**：
   - 在 `command_str()` 中，如果 `shlex::try_join` 失败，回退到简单拼接
   - 建议记录警告日志，帮助诊断转义问题

6. **测试扩展**：
   - 增加符号链接场景的测试
   - 增加路径边界测试（如 `/opt/homebrew` vs `/opt/homebrew/bin`）
