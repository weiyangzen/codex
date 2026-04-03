# Resume Picker 搜索错误快照测试文档

## 场景与职责

此快照文件对应 `tui/src/resume_picker.rs` 中的 `resume_search_error_snapshot` 测试，用于验证 Resume Picker 在读取会话元数据失败时的错误提示渲染。该测试确保当用户尝试恢复一个无法读取的会话时，系统能够友好地显示错误信息而不是崩溃。

该功能的主要职责包括：
- 检测会话文件读取失败的情况
- 在搜索栏位置显示内联错误信息
- 保持界面可用性，允许用户选择其他会话
- 提供清晰的错误路径信息便于调试

## 功能点目的

### 错误提示渲染验证
此测试验证当 `inline_error` 被设置时，搜索栏能够正确显示错误信息而不是搜索提示：

1. **错误状态检测**: 当 Enter 键选中一个无法解析 thread_id 的行时设置错误
2. **错误信息渲染**: 在搜索栏位置显示红色错误文本
3. **界面一致性**: 错误显示后其他界面元素保持正常

### 快照内容解析
```
Failed to read session metadata from /tmp/missing.jsonl
```

这是一个单行错误提示，显示：
- **错误原因**: 无法读取会话元数据
- **错误路径**: `/tmp/missing.jsonl`
- **视觉样式**: 红色文本（通过 `.red()` 样式设置）

### 错误触发场景
```rust
KeyCode::Enter => {
    if let Some(row) = self.filtered_rows.get(self.selected) {
        let path = row.path.clone();
        let thread_id = match row.thread_id {
            Some(thread_id) => Some(thread_id),
            None => {
                crate::resolve_session_thread_id(
                    path.as_path(),
                    /*id_str_if_uuid*/ None,
                )
                .await
            }
        };
        if let Some(thread_id) = thread_id {
            return Ok(Some(self.action.selection(path, thread_id)));
        }
        // 错误触发点：无法解析 thread_id
        self.inline_error = Some(format!(
            "Failed to read session metadata from {}",
            path.display()
        ));
        self.request_frame();
    }
}
```

## 具体技术实现

### 错误状态管理

```rust
struct PickerState {
    // ... 其他字段
    inline_error: Option<String>,  // 内联错误信息
}

impl PickerState {
    async fn handle_key(&mut self, key: KeyEvent) -> Result<Option<SessionSelection>> {
        self.inline_error = None;  // 每次按键清除错误
        match key.code {
            // ... 其他按键处理
            KeyCode::Enter => {
                // ... 处理 Enter 键，失败时设置 inline_error
            }
            // ...
        }
        Ok(None)
    }
}
```

### 错误渲染逻辑

```rust
fn search_line(state: &PickerState) -> Line<'_> {
    // 优先显示错误信息
    if let Some(error) = state.inline_error.as_deref() {
        return Line::from(error.red());  // 红色错误文本
    }
    // 正常状态显示搜索提示
    if state.query.is_empty() {
        return Line::from("Type to search".dim());
    }
    Line::from(format!("Search: {}", state.query))
}
```

### 测试实现细节

```rust
#[test]
fn resume_search_error_snapshot() {
    use crate::custom_terminal::Terminal;
    use crate::test_backend::VT100Backend;

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
    // 手动设置错误状态
    state.inline_error = Some(String::from(
        "Failed to read session metadata from /tmp/missing.jsonl",
    ));

    // 使用 VT100Backend 渲染
    let width: u16 = 80;
    let height: u16 = 1;
    let backend = VT100Backend::new(width, height);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, width, height));

    {
        let mut frame = terminal.get_frame();
        let line = search_line(&state);
        frame.render_widget_ref(line, frame.area());
    }
    terminal.flush().expect("flush");

    let snapshot = terminal.backend().to_string();
    assert_snapshot!("resume_picker_search_error", snapshot);
}
```

## 关键代码路径与文件引用

### 主要源文件
- `codex-rs/tui/src/resume_picker.rs` - Resume Picker 实现

### 关键函数
- `search_line()` - 位于第 931-939 行，负责渲染搜索行/错误行
- `PickerState::handle_key()` - 位于第 403-494 行，处理键盘事件
- `resume_search_error_snapshot` 测试 - 位于第 1644-1678 行

### 依赖模块
- `codex-rs/tui/src/custom_terminal.rs` - 自定义 Terminal 封装
- `codex-rs/tui/src/test_backend.rs` - VT100Backend 测试后端

### 相关快照文件
- `codex_tui__resume_picker__tests__resume_picker_search_error.snap`（当前文件）
- `codex_tui__resume_picker__tests__resume_picker_screen.snap` - 正常界面
- `codex_tui__resume_picker__tests__resume_picker_table.snap` - 表格渲染

## 依赖与外部交互

### 错误解析依赖
```rust
// resolve_session_thread_id 用于从路径解析 thread_id
crate::resolve_session_thread_id(
    path.as_path(),
    /*id_str_if_uuid*/ None,
)
.await
```

### 样式依赖
- **ratatui::style::Stylize**: 提供 `.red()` 方法设置文本颜色
- **VT100Backend**: 支持 ANSI 颜色代码的测试后端

### 异步处理
- 使用 `tokio::sync::mpsc` 进行后台事件通信
- 错误处理在异步上下文中执行

## 风险、边界与改进建议

### 潜在风险

1. **错误信息泄露**:
   - 风险：完整路径可能包含敏感信息
   - 建议：生产环境可配置是否显示完整路径

2. **错误恢复**:
   - 当前：任何按键都会清除错误
   - 风险：用户可能来不及阅读错误信息
   - 建议：添加错误确认机制或自动消失倒计时

3. **国际化**:
   - 当前：错误信息为硬编码英文
   - 建议：支持多语言错误信息

### 边界情况

1. **超长路径**: 错误路径超过终端宽度时的截断处理
2. **特殊字符**: 路径中包含控制字符或不可打印字符
3. **并发错误**: 快速多次按 Enter 可能产生多个错误（当前已处理，每次按键清除）
4. **网络存储**: 网络路径（如 NFS）读取失败时的延迟和重试

### 改进建议

1. **错误分类**:
   ```rust
   enum SessionError {
       NotFound(PathBuf),
       PermissionDenied(PathBuf),
       InvalidFormat(PathBuf, String),
       IoError(PathBuf, std::io::Error),
   }
   ```

2. **重试机制**:
   - 对于临时性错误（如网络超时）提供重试按钮

3. **日志记录**:
   - 将错误详情记录到日志，界面只显示友好提示

4. **批量错误**:
   - 支持显示多个错误（如批量恢复时的多个失败）

5. **错误代码**:
   - 添加错误代码便于用户报告问题

### 测试覆盖建议

1. **不同错误类型**: 测试文件不存在、权限不足、格式错误等场景
2. **长路径**: 测试超长路径的显示和截断
3. **Unicode 路径**: 测试包含非 ASCII 字符的路径
4. **并发场景**: 测试快速按键时的错误处理
