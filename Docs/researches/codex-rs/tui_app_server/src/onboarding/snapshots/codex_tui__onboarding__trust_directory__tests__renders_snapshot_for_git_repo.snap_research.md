# 研究文档：codex_tui__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap

## 场景与职责

此文件是 **insta snapshot 测试快照文件**，用于验证 `codex-rs/tui/src/onboarding/trust_directory.rs` 中 `TrustDirectoryWidget` 组件的 UI 渲染输出。该快照捕获了用户在初始化 Codex TUI 应用时看到的"目录信任确认"界面的完整终端渲染结果。

### 业务场景
当用户首次在某一工作目录启动 Codex TUI 时，系统需要用户明确确认是否信任该目录的内容。这是为了防止 prompt injection 攻击——如果用户在不信任的目录（如克隆的第三方仓库）中运行 Codex，恶意文件可能通过特殊构造的内容注入恶意指令。

## 功能点目的

### 1. UI 快照测试
- **目的**：确保 `TrustDirectoryWidget` 的渲染输出在代码变更时保持稳定
- **测试名称**：`renders_snapshot_for_git_repo`
- **断言位置**：`trust_directory.rs:218`
- **验证内容**：终端界面的字符级精确匹配

### 2. 界面内容验证
快照中包含的关键 UI 元素：
```
> You are in /workspace/project

  Do you trust the contents of this directory? Working with untrusted
  contents comes with higher risk of prompt injection.

› 1. Yes, continue                                                    
  2. No, quit

  Press enter to continue
```

## 具体技术实现

### 快照文件结构
```yaml
---
source: tui/src/onboarding/trust_directory.rs    # 源文件路径
assertion_line: 218                              # 断言语句行号
expression: terminal.backend()                   # 被快照的表达式
---
> You are in /workspace/project
...
```

### 测试实现细节

#### 测试后端（VT100Backend）
```rust
// test_backend.rs
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}
```
- 使用 `vt100` 解析器模拟真实终端的 VT100 转义序列处理
- 捕获完整的终端屏幕内容（包括颜色、光标位置等）
- 避免直接写入 stdout，适合单元测试环境

#### 测试代码流程
```rust
#[test]
fn renders_snapshot_for_git_repo() {
    let codex_home = TempDir::new().expect("temp home");
    let widget = TrustDirectoryWidget {
        codex_home: codex_home.path().to_path_buf(),
        cwd: PathBuf::from("/workspace/project"),  // 模拟路径
        show_windows_create_sandbox_hint: false,
        should_quit: false,
        selection: None,
        highlighted: TrustDirectorySelection::Trust,  // 默认选中"Yes"
        error: None,
    };

    // 创建 70x14 的虚拟终端
    let mut terminal = Terminal::new(VT100Backend::new(70, 14)).expect("terminal");
    terminal.draw(|f| (&widget).render_ref(f.area(), f.buffer_mut())).expect("draw");

    insta::assert_snapshot!(terminal.backend());
}
```

### TrustDirectoryWidget 渲染逻辑

#### 数据结构
```rust
pub(crate) struct TrustDirectoryWidget {
    pub codex_home: PathBuf,                    // Codex 配置目录
    pub cwd: PathBuf,                           // 当前工作目录
    pub show_windows_create_sandbox_hint: bool, // Windows 沙箱提示
    pub should_quit: bool,                      // 是否退出标志
    pub selection: Option<TrustDirectorySelection>, // 用户选择
    pub highlighted: TrustDirectorySelection,   // 当前高亮选项
    pub error: Option<String>,                  // 错误信息
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustDirectorySelection {
    Trust,  // 选项 1: Yes, continue
    Quit,   // 选项 2: No, quit
}
```

#### 渲染流程（WidgetRef::render_ref）
1. **当前目录显示**：`> You are in {cwd}`
2. **风险提示文本**：关于 prompt injection 的警告信息
3. **选项列表**：使用 `selection_option_row` 渲染两个选项
   - 选中项前缀：`› 1.`（青色高亮）
   - 未选中项前缀：`  2.`（默认样式）
4. **操作提示**：`Press Enter to continue`
5. **错误显示**（如有）：红色错误信息

#### 键盘事件处理（KeyboardHandler）
| 按键 | 动作 |
|------|------|
| ↑ / k | 高亮 "Yes, continue" |
| ↓ / j | 高亮 "No, quit" |
| 1 / y | 直接选择 Trust |
| 2 / n | 直接选择 Quit |
| Enter | 确认当前高亮选项 |

#### 信任设置流程
```rust
fn handle_trust(&mut self) {
    // 1. 解析 Git 仓库根目录（支持 worktree）
    let target = resolve_root_git_project_for_trust(&self.cwd)
        .unwrap_or_else(|| self.cwd.clone());
    
    // 2. 写入信任配置到 config.toml
    if let Err(e) = set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted) {
        self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
    }
    
    self.selection = Some(TrustDirectorySelection::Trust);
}
```

## 关键代码路径与文件引用

### 测试相关
| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/onboarding/trust_directory.rs:204-223` | 快照测试定义 |
| `codex-rs/tui/src/test_backend.rs` | VT100 模拟终端后端 |
| `codex-rs/tui/src/onboarding/snapshots/*.snap` | 期望的渲染输出快照 |

### 渲染实现
| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/onboarding/trust_directory.rs:43-106` | WidgetRef 渲染实现 |
| `codex-rs/tui/src/selection_list.rs:10-45` | 选项行渲染辅助函数 |
| `codex-rs/tui/src/render/renderable.rs` | 可渲染组件抽象 |
| `codex-rs/tui/src/render/mod.rs:7-49` | Insets 边距工具 |

### 信任配置
| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/config/mod.rs:1146-1156` | `set_project_trust_level` 公共 API |
| `codex-rs/core/src/config/mod.rs:1075-1144` | 内部 TOML 编辑实现 |
| `codex-rs/core/src/git_info.rs:606-628` | `resolve_root_git_project_for_trust` |

### 集成入口
| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/onboarding/onboarding_screen.rs:34-50` | Step 状态机定义 |
| `codex-rs/tui/src/onboarding/onboarding_screen.rs:120-131` | TrustDirectory Step 初始化 |
| `codex-rs/tui/src/onboarding/mod.rs` | onboarding 模块组织 |

## 依赖与外部交互

### 外部 Crate 依赖
```toml
# 测试依赖
insta = "1.x"           # 快照测试框架
vt100 = "0.x"           # VT100 终端模拟
tempfile = "3.x"        # 临时目录
pretty_assertions = "1.x"  # 差异对比

# TUI 依赖
ratatui = "0.x"         # 终端 UI 框架
crossterm = "0.x"       # 跨平台终端控制
```

### 内部模块依赖
```
tui/src/onboarding/trust_directory.rs
├── codex_core::config::set_project_trust_level
├── codex_core::git_info::resolve_root_git_project_for_trust
├── codex_protocol::config_types::TrustLevel
├── crate::test_backend::VT100Backend (test only)
├── crate::selection_list::selection_option_row
└── crate::onboarding::onboarding_screen::{KeyboardHandler, StepStateProvider}
```

### 配置文件交互
当用户选择 "Yes, continue" 时，会在 `~/.codex/config.toml` 中写入：
```toml
[projects]
[projects."/workspace/project"]
trust_level = "trusted"
```

## 风险、边界与改进建议

### 当前风险

1. **快照漂移风险**
   - 任何 UI 文本、颜色、布局的变更都会导致快照测试失败
   - 需要人工审核 `*.snap.new` 文件确认变更是否符合预期

2. **路径硬编码**
   - 测试使用固定路径 `/workspace/project`，可能与实际环境不符
   - 但这不影响快照内容，因为路径只是字符串渲染

3. **平台差异**
   - Windows 平台有额外的 `show_windows_create_sandbox_hint` 提示
   - 当前快照是在非 Windows 环境下生成的

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| Git 仓库根目录 | 通过 `resolve_root_git_project_for_trust` 自动解析 |
| Git worktree | 正确解析到主仓库目录进行信任设置 |
| 非 Git 目录 | 使用当前工作目录作为信任目标 |
| 配置写入失败 | 在 UI 中显示红色错误信息 |

### 改进建议

1. **多平台快照覆盖**
   - 建议为 Windows 平台添加独立的快照测试，验证沙箱提示文本

2. **动态路径测试**
   - 可考虑使用更灵活的路径生成策略，但当前固定路径对快照测试是可接受的

3. **交互测试补充**
   - 当前仅测试初始渲染状态
   - 建议补充键盘导航和选择的交互快照测试

4. **错误状态快照**
   - 当前未覆盖 `error: Some(...)` 状态的渲染
   - 建议添加配置写入失败时的 UI 快照

5. **与 tui_app_server 同步**
   - 根据 AGENTS.md 规范，`tui` 和 `tui_app_server` 有并行实现
   - 确保两个 crate 的变更保持同步（当前快照文件在两者间共享）
