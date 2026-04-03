# Resume Picker 搜索错误快照研究文档

## 场景与职责

该快照测试验证 **Resume Picker** 在处理会话元数据读取失败时的错误展示行为。当用户尝试恢复一个会话但无法读取其元数据文件时，系统需要在界面上友好地展示错误信息。

### 核心职责
- 检测会话文件读取错误
- 在搜索行位置显示错误信息
- 保持界面可用，允许用户继续操作

### 错误场景
1. 用户选中一个会话并按 Enter 恢复
2. 系统尝试读取会话文件（`/tmp/missing.jsonl`）
3. 文件不存在或损坏，读取失败
4. 错误信息显示在搜索行，提示用户

## 功能点目的

### 1. 错误检测与报告
- 在 `handle_key` 中处理 Enter 键时检测错误
- 使用 `resolve_session_thread_id` 解析线程 ID
- 失败时设置 `inline_error` 状态

### 2. 错误信息展示
- 错误信息以红色显示在搜索行
- 包含具体文件路径，便于用户定位问题
- 错误信息显示后，用户可以继续浏览其他会话

### 3. 用户体验
- 错误不中断用户流程
- 按其他键后错误自动清除
- 保持界面响应性

## 具体技术实现

### 错误处理流程

```rust
async fn handle_key(&mut self, key: KeyEvent) -> Result<Option<SessionSelection>> {
    self.inline_error = None;  // 清除之前的错误
    
    match key.code {
        KeyCode::Enter => {
            if let Some(row) = self.filtered_rows.get(self.selected) {
                let path = row.path.clone();
                let thread_id = match row.thread_id {
                    Some(thread_id) => Some(thread_id),
                    None => {
                        // 尝试从文件解析线程 ID
                        crate::resolve_session_thread_id(
                            path.as_path(),
                            /*id_str_if_uuid*/ None,
                        ).await
                    }
                };
                
                if let Some(thread_id) = thread_id {
                    // 成功，返回选择
                    return Ok(Some(self.action.selection(path, thread_id)));
                }
                
                // 失败，设置错误信息
                self.inline_error = Some(format!(
                    "Failed to read session metadata from {}",
                    path.display()
                ));
                self.request_frame();  // 请求重绘
            }
        }
        // ... 其他按键处理
    }
    Ok(None)
}
```

### 搜索行渲染

```rust
fn search_line(state: &PickerState) -> Line<'_> {
    // 优先显示错误信息
    if let Some(error) = state.inline_error.as_deref() {
        return Line::from(error.red());
    }
    
    // 正常搜索提示
    if state.query.is_empty() {
        return Line::from("Type to search".dim());
    }
    
    // 显示当前搜索词
    Line::from(format!("Search: {}", state.query))
}
```

### 测试用例分析

```rust
#[test]
fn resume_picker_search_error_snapshot() {
    use crate::custom_terminal::Terminal;
    use crate::test_backend::VT100Backend;

    // 1. 创建状态并设置错误
    let loader: PageLoader = Arc::new(|_| {});
    let mut state = PickerState::new(
        PathBuf::from("/tmp"),
        FrameRequester::test_dummy(),
        loader,
        String::from("openai"),
        true,
        None,
        SessionPickerAction::Resume,
    );
    
    // 设置错误信息
    state.inline_error = Some(String::from(
        "Failed to read session metadata from /tmp/missing.jsonl"
    ));

    // 2. 创建测试终端
    let width: u16 = 80;
    let height: u16 = 1;  // 只渲染搜索行
    let backend = VT100Backend::new(width, height);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, width, height));

    // 3. 渲染搜索行
    {
        let mut frame = terminal.get_frame();
        let line = search_line(&state);
        frame.render_widget_ref(line, frame.area());
    }
    terminal.flush().expect("flush");

    // 4. 验证快照
    let snapshot = terminal.backend().to_string();
    assert_snapshot!("resume_picker_search_error", snapshot);
}
```

### 快照输出解析

```
Failed to read session metadata from /tmp/missing.jsonl
```

- 纯文本错误信息
- 红色显示（通过 `.red()` 样式）
- 包含具体文件路径 `/tmp/missing.jsonl`

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/resume_picker.rs` | Resume Picker 实现 |

### 关键函数

1. **错误处理**
   - `PickerState::handle_key()` (line 403-494)
   - Enter 键处理逻辑 (line 414-435)

2. **错误渲染**
   - `search_line()` (line 931-939)
   - 错误信息红色显示

3. **测试**
   - `resume_picker_search_error_snapshot()` (line 1645-1678)

### 错误状态管理

```rust
struct PickerState {
    // ... 其他字段
    inline_error: Option<String>,  // 行内错误信息
}

impl PickerState {
    async fn handle_key(&mut self, key: KeyEvent) -> Result<Option<SessionSelection>> {
        // 每次按键清除错误
        self.inline_error = None;
        // ...
    }
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 框架，提供 `Line`, `Span` |
| `color_eyre` | 错误处理 |

### 内部模块交互

```
resume_picker.rs
├── resolve_session_thread_id() (会话线程 ID 解析)
│   └── 可能返回 None 导致错误
└── custom_terminal.rs (VT100Backend 测试后端)
```

### 错误来源

```rust
// resolve_session_thread_id 可能的失败原因：
// 1. 文件不存在
// 2. 文件权限不足
// 3. 文件格式损坏
// 4. JSON 解析失败

pub async fn resolve_session_thread_id(
    path: &Path,
    id_str_if_uuid: Option<&str>,
) -> Option<ThreadId> {
    // 尝试读取和解析会话文件
    // 失败时返回 None
}
```

## 风险、边界与改进建议

### 潜在风险

1. **错误信息泄露**
   - 当前错误信息包含完整文件路径
   - 可能泄露敏感信息（如用户目录结构）

2. **错误恢复**
   - 错误显示后，用户可能不知道可以继续操作
   - 缺少明确的"继续"提示

3. **并发错误**
   - 多个后台请求可能产生多个错误
   - 当前只显示最后一个错误

### 边界情况

1. **空错误信息**
   - `inline_error` 为 `None` 时显示正常搜索提示
   - 空字符串错误显示为 "Search: "

2. **超长错误信息**
   - 错误信息可能超过终端宽度
   - 当前未截断，可能换行或截断显示

3. **按键清除**
   - 任何按键都会清除错误
   - 用户可能来不及阅读错误信息

### 改进建议

1. **错误信息优化**
   - 分类错误类型（文件不存在、权限不足、格式错误）
   - 提供针对性的解决建议
   - 敏感路径脱敏处理

2. **错误持久化**
   - 增加确认键清除错误（如按 Enter 或 Esc）
   - 或者增加错误显示时间

3. **日志记录**
   - 将详细错误记录到日志
   - 界面只显示友好提示

4. **重试机制**
   - 提供重试按钮/快捷键
   - 临时网络/文件系统问题可恢复

5. **批量错误**
   - 支持显示多个错误
   - 错误列表可滚动查看
