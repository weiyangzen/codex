# Research: codex_tui__cwd_prompt__tests__cwd_prompt_fork_modal.snap

## 场景与职责

本快照文件测试工作目录选择提示（CWD Prompt）在 Fork 会话场景下的 UI 渲染。当用户选择 Fork（分支）一个现有会话时，系统需要确认使用哪个工作目录。

## 功能点目的

验证 Fork 会话时的工作目录选择模态框：
- 清晰说明 Session 目录和 Current 目录的区别
- 提供两个明确的选项
- 显示具体的路径信息
- 提供直观的键盘操作提示

## 具体技术实现

### UI 布局结构

```

Choose working directory to fork this session

  Session = latest cwd recorded in the forked session                           
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                              
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

### 关键数据结构

```rust
// cwd_prompt.rs
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdPromptAction {
    Resume,  // 恢复会话
    Fork,    // 分支会话（本测试场景）
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdSelection {
    Current,  // 使用当前工作目录
    Session,  // 使用会话记录的工作目录
}

pub(crate) enum CwdPromptOutcome {
    Selection(CwdSelection),
    Exit,
}
```

### 动词变位

```rust
impl CwdPromptAction {
    fn verb(self) -> &'static str {
        match self {
            CwdPromptAction::Resume => "resume",
            CwdPromptAction::Fork => "fork",
        }
    }

    fn past_participle(self) -> &'static str {
        match self {
            CwdPromptAction::Resume => "resumed",
            CwdPromptAction::Fork => "forked",
        }
    }
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/cwd_prompt.rs`
- **测试函数**: `cwd_prompt_fork_modal`
- **调用方**: `app.rs` 中的会话恢复/分支逻辑

## 依赖与外部交互

- **会话管理**: `SessionTarget` 提供会话路径信息
- **文件系统**: 获取当前工作目录
- **TUI 框架**: `ratatui` 渲染模态框界面

## 风险、边界与改进建议

### 边界情况

1. **路径长度**: 长路径可能被截断，需要处理显示
2. **权限问题**: 目录可能不存在或无权限访问
3. **相对路径 vs 绝对路径**: 需要统一显示格式

### 风险点

1. **概念理解**: 用户可能不理解 Session 和 Current 的区别
2. **默认选择**: 默认选中 Session 目录是否符合大多数用户预期

### 改进建议

1. 添加路径存在性验证和错误提示
2. 考虑添加 "浏览..." 选项允许选择其他目录
3. 添加最近使用目录的历史记录
4. 在路径旁添加目录存在状态指示器
