# tui-alternate-screen.md 研究文档

## 场景与职责

tui-alternate-screen.md 是 Codex CLI 项目中关于 TUI 备用屏幕（Alternate Screen）和终端多路复用器（如 Zellij）的设计决策文档。该文档解释了全屏 TUI 行为与终端回滚历史保留之间的根本冲突，以及 Codex 的解决方案。

**适用场景：**
- 用户在 Zellij 等终端多路复用器中使用 Codex TUI
- 开发者需要理解备用屏幕处理逻辑
- 调试终端显示问题

## 功能点目的

### 1. 问题定义

#### 全屏 TUI 优势
Codex 的 TUI 使用终端的**备用屏幕缓冲区**提供干净的全屏体验：
- 使用整个视口而不污染终端的回滚历史
- 为聊天界面提供专用环境
- 镜像其他终端应用程序的行为（vim、tmux 等）

#### Zellij 冲突
终端多路复用器如 **Zellij** 严格遵循 xterm 规范，该规范定义备用屏幕缓冲区**不应**有回滚：
- **Zellij PR**: https://github.com/zellij-org/zellij/pull/1032
- **原理**：xterm 规范明确说明备用屏幕模式禁止回滚
- **可配置性**：这在 Zellij 中不可配置——没有选项可以在备用屏幕模式下启用回滚

**问题**：在 Zellij 中使用 Codex 的 TUI 时，用户无法通过正常终端滚动查看对话历史，因为：
1. TUI 在备用屏幕模式下运行（全屏）
2. Zellij 禁用备用屏幕缓冲区的回滚（遵循 xterm 规范）
3. 整个对话通过正常终端滚动变得不可访问

### 2. 解决方案

Codex 实现了**务实的解决方法**，有三种模式，由 `config.toml` 中的 `tui.alternate_screen` 控制：

#### 1. `auto`（默认）
- **行为**：自动检测终端多路复用器
- **在 Zellij 中**：禁用备用屏幕模式（内联模式，保留回滚）
- **其他地方**：启用备用屏幕模式（全屏体验）
- **原理**：在每个环境中提供最佳用户体验

#### 2. `always`
- **行为**：始终使用备用屏幕模式（原始行为）
- **用例**：偏好全屏且不使用 Zellij 的用户，或已找到解决方法的用户

#### 3. `never`
- **行为**：从不使用备用屏幕模式（内联模式）
- **用例**：始终希望保留回滚历史的用户
- **权衡**：用 TUI 输出污染终端回滚

### 3. 运行时覆盖
`--no-alt-screen` CLI 标志可以在运行时覆盖配置设置：

```bash
codex --no-alt-screen
```

**用途**：
- 回滚至关重要的一次性会话
- 调试终端相关问题
- 测试备用屏幕行为

### 4. 实现细节

#### 自动检测
`auto` 模式通过检查 `ZELLIJ` 环境变量检测 Zellij：

```rust
let terminal_info = codex_core::terminal::terminal_info();
!matches!(terminal_info.multiplexer, Some(Multiplexer::Zellij { .. }))
```

检测发生在 `codex-rs/tui/src/lib.rs` 的辅助函数 `determine_alt_screen_mode()` 中。

#### 配置模式
`AltScreenMode` 枚举定义在 `codex-rs/protocol/src/config_types.rs` 中，序列化为小写 TOML：

```toml
[tui]
# 选项：auto, always, never
alternate_screen = "auto"
```

#### 为什么不永久禁用 Zellij 的备用屏幕？
使用 `auto` 检测而不是始终在 Zellij 中禁用的原因：
1. 许多 Zellij 用户不关心回滚，偏好全屏体验
2. 某些用户可能在 Zellij 内部使用 tmux，创建多路复用器链
3. 提供用户选择而无需手动配置

### 5. 相关问题和参考

- **原始问题**: GitHub #2558 - "No scrollback in Zellij"
- **实现 PR**: GitHub #8555
- **Zellij PR**: https://github.com/zellij-org/zellij/pull/1032（为什么禁用回滚）
- **xterm 规范**: 备用屏幕缓冲区不应有回滚

### 6. 未来考虑

#### 考虑的替代方案
1. **在 TUI 中实现自定义回滚**：需要对所有历史输出进行缓冲和渲染的重大架构更改
2. **请求 Zellij 添加配置选项**：不可行——Zellij 维护者明确选择此行为以遵循规范
3. **无条件禁用备用屏幕**：会降低非 Zellij 用户的用户体验

#### 转录分页器
Codex 的转录分页器（用 Ctrl+T 打开）提供审查对话历史的替代方式，即使在全屏模式下。然而，这不如自然回滚无缝。

### 7. 开发者注意事项

修改 TUI 代码时，请记住：
- `determine_alt_screen_mode()` 函数封装了所有逻辑
- 配置在 `config.tui_alternate_screen` 中
- CLI 标志在 `cli.no_alt_screen` 中
- 行为通过 `tui.set_alt_screen_enabled()` 应用

**终端状态恢复**：
如果运行 Codex 后遇到终端状态问题，可以用以下命令恢复：

```bash
reset
```

## 具体技术实现

### 配置流程

```
启动 TUI
    ↓
读取配置 tui.alternate_screen
    ↓
如果是 auto：检测终端多路复用器
    ↓
根据检测结果决定是否启用备用屏幕
    ↓
应用设置 tui.set_alt_screen_enabled()
```

### 检测逻辑

```rust
fn determine_alt_screen_mode(config: &Config, cli: &Cli) -> bool {
    // CLI 标志优先
    if cli.no_alt_screen {
        return false;
    }
    
    match config.tui.alternate_screen {
        AltScreenMode::Always => true,
        AltScreenMode::Never => false,
        AltScreenMode::Auto => {
            let info = codex_core::terminal::terminal_info();
            !matches!(info.multiplexer, Some(Multiplexer::Zellij { .. }))
        }
    }
}
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/tui-alternate-screen.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/lib.rs` | `determine_alt_screen_mode()` 函数 |
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | `AltScreenMode` 枚举定义 |
| `/home/sansha/Github/codex/codex-rs/core/src/terminal.rs` | 终端信息检测（推测） |

### 配置键

| 配置 | 类型 | 说明 |
|-----|------|------|
| `tui.alternate_screen` | `AltScreenMode` | 备用屏幕模式：auto, always, never |
| `cli.no_alt_screen` | `bool` | CLI 标志，覆盖配置 |

## 依赖与外部交互

### 外部依赖

1. **Zellij**
   - 终端多路复用器
   - 遵循 xterm 规范

2. **xterm 规范**
   - 备用屏幕缓冲区行为定义

3. **其他多路复用器**
   - tmux（可能也需要特殊处理）
   - screen

### 内部依赖

1. **终端检测**
   - 环境变量检查
   - 终端能力检测

2. **TUI 框架**
   - 备用屏幕切换
   - 终端状态管理

## 风险、边界与改进建议

### 潜在风险

1. **检测失败**
   - 环境变量可能不准确
   - 嵌套多路复用器场景复杂
   - 建议：添加更多检测方法

2. **用户体验不一致**
   - 不同环境下的行为差异
   - 建议：在 TUI 中显示当前模式

3. **终端状态问题**
   - 异常退出可能留下终端处于不良状态
   - 建议：增强终端恢复机制

### 边界情况

1. **嵌套多路复用器**
   - tmux 在 Zellij 内部
   - 多层次的终端环境

2. **SSH 会话**
   - 远程主机的终端检测
   - 代理和跳转主机

3. **不同终端模拟器**
   - 各种终端对备用屏幕的支持差异

### 改进建议

1. **增强检测**
   - 检测更多多路复用器（tmux、screen 等）
   - 添加手动覆盖选项

2. **用户反馈**
   - 在 TUI 中显示当前屏幕模式
   - 提供切换快捷键

3. **配置向导**
   - 首次运行时检测环境并推荐设置
   - 交互式配置

4. **文档增强**
   - 添加故障排除指南
   - 提供各种终端的已知问题

5. **备用方案**
   - 改进转录分页器体验
   - 考虑内置回滚实现

6. **测试覆盖**
   - 在各种终端环境中测试
   - 自动化终端兼容性测试
