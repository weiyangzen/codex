# ChatWidget 命令执行与状态布局 VT100 快照测试

## 场景与职责

该 snapshot 测试使用 VT100 终端模拟器捕获 `ChatWidget` 在执行命令期间的完整视觉布局，包括历史记录、执行块、状态指示器和输入框的垂直排列。

### 测试目的
- 验证命令执行期间 UI 的垂直布局结构
- 确保历史记录、执行块、状态行和输入框的正确排列
- 捕获真实的终端视觉输出用于回归测试

### 业务场景
- 用户请求 Codex 搜索代码库中的特定内容
- Codex 执行 `rg` 命令并显示结果
- 用户可以看到命令执行进度和输出

## 功能点目的

### 1. 垂直布局层次
测试验证以下元素从上到下依次排列：
1. **历史记录区域** - 之前的对话内容
2. **分隔空行** - 视觉分隔
3. **执行块** - 当前正在执行的命令
4. **分隔空行** - 视觉分隔
5. **状态行** - 当前任务状态
6. **分隔空行** - 视觉分隔
7. **输入框** - 用户输入区域

### 2. 执行块内容
执行块应显示：
- 用户请求的描述
- 已执行/正在执行的命令
- 命令输出（如文件读取结果）
- 执行状态（时间、中断提示）

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn chatwidget_exec_and_status_layout_vt100_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 1. 完成一个助手消息，模拟历史记录
    complete_assistant_message(
        &mut chat,
        "msg-search",
        "I'm going to search the repo for where "Change Approved" is rendered to update that view.",
        None,
    );

    // 2. 构建命令和解析结果
    let command = vec!["bash".into(), "-lc".into(), "rg \"Change Approved\"".into()];
    let parsed_cmd = vec![
        ParsedCommand::Search {
            query: Some("Change Approved".into()),
            path: None,
            cmd: "rg \"Change Approved\"".into(),
        },
        ParsedCommand::Read {
            name: "diff_render.rs".into(),
            cmd: "cat diff_render.rs".into(),
            path: "diff_render.rs".into(),
        },
    ];
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    
    // 3. 发送命令开始事件
    chat.handle_codex_event(Event {
        id: "c1".into(),
        msg: EventMsg::ExecCommandBegin(ExecCommandBeginEvent {
            call_id: "c1".into(),
            process_id: None,
            turn_id: "turn-1".into(),
            command: command.clone(),
            cwd: cwd.clone(),
            // ... 其他字段
        }),
    });

    // 4. 添加命令输出
    chat.handle_codex_event(Event {
        id: "c1".into(),
        msg: EventMsg::ExecCommandOutputDelta(ExecCommandOutputDeltaEvent {
            call_id: "c1".into(),
            process_id: None,
            turn_id: "turn-1".into(),
            stdout: "Read diff_render.rs\n".into(),
            stderr: "".into(),
        }),
    });

    // 5. 发送命令结束事件
    chat.handle_codex_event(Event {
        id: "c1".into(),
        msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
            call_id: "c1".into(),
            // ... 其他字段
            stdout: "Read diff_render.rs\n".into(),
            stderr: "".into(),
            formatted_output: "Read diff_render.rs\n".into(),
            status: CoreExecCommandStatus::Completed,
        }),
    });

    // 6. 设置 VT100 终端并渲染
    let width: u16 = 80;
    let height: u16 = 24;
    let backend = VT100Backend::new(width, height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    
    // 设置视口区域
    let desired_height = chat.desired_height(width).min(height);
    term.set_viewport_area(Rect::new(0, height - desired_height, width, desired_height));
    
    // 渲染
    term.draw(|f| {
        chat.render(f.area(), f.buffer_mut());
    }).unwrap();
    
    // 7. 捕获 VT100 屏幕内容
    assert_snapshot!(term.backend().vt100().screen().contents());
}
```

### Snapshot 内容分析
```
（空行 x 22）
• I'm going to search the repo for where "Change Approved" is rendered to update
  that view.

• Explored
  └ Search Change Approved
    Read diff_render.rs

• Investigating rendering code (0s • esc to interrupt)


› Summarize recent commits

  tab to queue message                                       100% context left
```

**布局解析**：
- 第1-22行：空行（保留给历史记录滚动）
- 第23行：助手消息（换行后缩进对齐）
- 第24行：空行（分隔）
- 第25-27行：执行块（"Explored" 标题 + 命令树）
- 第28行：空行（分隔）
- 第29行：状态行（"Investigating..." + 计时器 + 中断提示）
- 第30行：空行（分隔）
- 第31行：输入框提示符
- 第32行：帮助行（快捷键提示 + 上下文窗口百分比）

## 关键代码路径与文件引用

### 执行块渲染
```rust
// codex-rs/tui_app_server/src/exec_cell.rs
pub struct ExecCell {
    command: Vec<String>,
    parsed_cmd: Vec<ParsedCommand>,
    output: Vec<CommandOutput>,
    status: ExecStatus,
}

impl HistoryCell for ExecCell {
    fn display_lines(&self, width: usize) -> Vec<Line> {
        // 渲染命令树结构
        // 如：└ Search Change Approved
        //     Read diff_render.rs
    }
}
```

### 命令解析
```rust
// codex-shell-command 解析器
pub enum ParsedCommand {
    Search {
        query: Option<String>,
        path: Option<String>,
        cmd: String,
    },
    Read {
        name: String,
        cmd: String,
        path: String,
    },
    // ... 其他变体
}
```

### VT100 后端
```rust
// codex-rs/tui_app_server/src/test_backend.rs
pub struct VT100Backend {
    vt100: vt100::Screen,
    width: u16,
    height: u16,
}

impl VT100Backend {
    pub fn screen(&self) -> &vt100::Screen {
        &self.vt100
    }
    
    pub fn contents(&self) -> String {
        self.vt100.contents()
    }
}
```

### 自定义终端
```rust
// codex-rs/tui_app_server/src/custom_terminal.rs
pub struct Terminal<B: Backend> {
    backend: B,
    viewport_area: Rect,
    // ...
}

impl<B: Backend> Terminal<B> {
    pub fn set_viewport_area(&mut self, area: Rect) {
        self.viewport_area = area;
    }
    
    pub fn draw<F>(&mut self, f: F) -> Result<()>
    where
        F: FnOnce(&mut Frame),
    {
        // 渲染到后端
    }
}
```

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `vt100` | VT100 终端模拟，捕获真实终端输出 |
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试 |

### 协议事件
| 事件 | 描述 |
|------|------|
| `ExecCommandBeginEvent` | 命令开始执行 |
| `ExecCommandOutputDeltaEvent` | 命令输出增量 |
| `ExecCommandEndEvent` | 命令执行结束 |

### 内部模块
```
chatwidget.rs
    ├── exec_cell.rs          # 执行块渲染
    ├── history_cell.rs       # 历史记录单元格
    ├── status_indicator_widget.rs  # 状态指示器
    └── bottom_pane/mod.rs    # 底部面板

codex-shell-command/
    └── parse_command.rs      # 命令解析
```

## 风险、边界与改进建议

### 当前限制

1. **硬编码尺寸**
   - 测试使用固定的 80x24 终端尺寸
   - 不测试响应式布局的其他尺寸

2. **时序依赖**
   - 状态行显示 "(0s)" 依赖于测试执行速度
   - 可能在慢速机器上产生不稳定结果

3. **路径依赖**
   - 使用 `std::env::current_dir()` 获取当前目录
   - 在不同环境中可能产生不同结果

### 改进建议

1. **参数化测试**
   ```rust
   #[test_case(80, 24)]
   #[test_case(120, 30)]
   #[test_case(60, 15)]
   async fn chatwidget_exec_layout_vt100_snapshot(width: u16, height: u16) {
       // 测试多种尺寸
   }
   ```

2. **冻结时间**
   ```rust
   // 使用 mock 时间避免 "(0s)" 变化
   chat.status_start_time = Instant::from_millis(0);
   ```

3. **添加更多场景**
   - 多命令顺序执行
   - 命令失败场景
   - 用户中断场景

4. **验证具体元素位置**
   ```rust
   let contents = term.backend().vt100().screen().contents();
   assert!(contents.contains("Explored"));
   assert!(contents.contains("esc to interrupt"));
   assert!(contents.contains("100% context left"));
   ```

### 相关测试
- `chatwidget_markdown_code_blocks_vt100_snapshot` - Markdown 代码块渲染
- `exploring_step*_start_*` / `exploring_step*_finish_*` - 探索模式步骤
- `user_shell_ls_output` - 用户 shell 命令输出

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chatwidget_exec_and_status_layout_vt100_snapshot.snap*
