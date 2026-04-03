# Research: codex_tui__cwd_prompt__tests__cwd_prompt_modal.snap

## 场景与职责

本快照文件测试工作目录选择提示（CWD Prompt）在恢复会话场景下的 UI 渲染。当用户选择恢复一个之前的会话时，系统需要确认使用哪个工作目录。

## 功能点目的

验证恢复会话时的工作目录选择模态框：
- 区分 Session 目录（会话记录）和 Current 目录（当前环境）
- 提供清晰的选择界面
- 显示具体的路径信息帮助决策

## 具体技术实现

### UI 布局结构

```

Choose working directory to resume this session

  Session = latest cwd recorded in the resumed session                           
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                              
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

### 与 Fork 场景的区别

| 场景 | 标题动词 | Session 含义 |
|------|----------|--------------|
| Resume | "resume this session" | 被恢复的会话 |
| Fork | "fork this session" | 被分支的会话 |

### 核心逻辑

```rust
pub(crate) async fn run_cwd_selection_prompt(
    tui: &mut Tui,
    action: CwdPromptAction,  // Resume 或 Fork
    current_cwd: &Path,
    session_cwd: &Path,
) -> Result<CwdPromptOutcome> {
    let mut screen = CwdPromptScreen::new(
        tui.frame_requester(),
        action,
        current_cwd.display().to_string(),
        session_cwd.display().to_string(),
    );
    // ... 事件循环处理
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/cwd_prompt.rs`
- **测试函数**: `cwd_prompt_modal`
- **相关枚举**: `CwdPromptAction::Resume`

## 依赖与外部交互

- **会话存储**: 从会话元数据读取记录的 CWD
- **系统调用**: `std::env::current_dir()` 获取当前目录
- **路径显示**: `display_path_for` 格式化路径显示

## 风险、边界与改进建议

### 边界情况

1. **会话目录已删除**: 原会话记录的工作目录可能已不存在
2. **当前目录已变更**: 用户可能在不同目录启动 Codex
3. **跨设备恢复**: 会话来自不同机器，路径可能无效

### 风险点

1. **用户困惑**: 不理解两个选项的区别可能导致错误选择
2. **路径失效**: 选择已不存在的目录可能导致后续错误

### 改进建议

1. 添加目录存在性检查，对不存在的目录显示警告
2. 提供默认推荐（如优先推荐存在的目录）
3. 添加更详细的帮助说明
4. 支持记住用户的选择偏好
