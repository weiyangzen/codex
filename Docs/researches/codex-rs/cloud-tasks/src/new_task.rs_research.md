# new_task.rs 研究文档

## 场景与职责

`new_task.rs` 是 Codex Cloud Tasks TUI 应用中**新建任务页面**的数据结构定义模块。它封装了创建新 Cloud Task 时所需的状态管理，包括：

- 多行文本输入（通过 `ComposerInput`）
- 提交状态追踪
- 环境 ID 选择
- Best-of-N 尝试次数配置

该模块作为 TUI 应用状态的一部分，在 `app.rs` 中被使用，负责 New Task 页面的核心数据模型。

## 功能点目的

### 1. NewTaskPage 结构体

```rust
pub struct NewTaskPage {
    pub composer: ComposerInput,    // 文本输入组件
    pub submitting: bool,           // 提交中状态（防止重复提交）
    pub env_id: Option<String>,     // 选中的环境 ID
    pub best_of_n: usize,           // 并行尝试次数 (1-4)
}
```

**设计意图**：
- **composer**: 复用 `codex_tui::ComposerInput` 组件，提供成熟的输入体验（支持 Shift+Enter 换行、粘贴检测、提示符等）
- **submitting**: 标记是否正在提交，用于禁用输入和显示加载状态
- **env_id**: 可选的环境标识，未选择时显示警告
- **best_of_n**: 控制 Codex Cloud 并行生成尝试次数，提高成功率

### 2. 快捷键提示配置

在 `new()` 方法中预设了底部提示栏：
- `⏎` send - 回车提交
- `Shift+⏎` newline - Shift+回车换行
- `Ctrl+O` env - 打开环境选择器
- `Ctrl+N` attempts - 打开尝试次数选择器
- `Ctrl+C` quit - 退出

## 具体技术实现

### 关键流程

```
用户按下 'n' → app.new_task = Some(NewTaskPage::new(...))
                    ↓
              渲染 New Task 页面 (ui.rs::draw_new_task_page)
                    ↓
              用户输入文本 → composer.input(key)
                    ↓
              按 Enter → ComposerAction::Submitted(text)
                    ↓
              检查 env_id 是否存在
                    ↓
              提交到 Cloud Backend → spawn async task
                    ↓
              等待 AppEvent::NewTaskSubmitted 响应
```

### 数据结构关系

```
App (app.rs)
├── new_task: Option<NewTaskPage>
│   ├── composer: ComposerInput (来自 codex-tui crate)
│   ├── submitting: bool
│   ├── env_id: Option<String>
│   └── best_of_n: usize
```

### 依赖的外部组件

| 组件 | 来源 | 用途 |
|------|------|------|
| `ComposerInput` | `codex_tui::ComposerInput` | 多行文本输入 |
| `AppEvent::NewTaskSubmitted` | `app.rs` | 提交结果异步通知 |
| `env_modal` | `app.rs` | 环境选择弹窗状态 |
| `best_of_modal` | `app.rs` | 尝试次数选择弹窗状态 |

## 关键代码路径与文件引用

### 创建 NewTaskPage

**文件**: `lib.rs:1727-1730`
```rust
app.new_task = Some(crate::new_task::NewTaskPage::new(
    app.env_filter.clone(), 
    app.best_of_n
));
```

### 渲染 New Task 页面

**文件**: `ui.rs:104-174`
- `draw_new_task_page()` 函数负责渲染
- 动态计算 composer 高度（最小3行，最大终端高度-6）
- 底部锚定输入框

### 处理用户输入

**文件**: `lib.rs:1479-1531`
```rust
if let Some(page) = app.new_task.as_mut() {
    match key.code {
        KeyCode::Esc => { /* 取消 */ }
        _ => {
            if let ComposerAction::Submitted(text) = page.composer.input(key) {
                // 提交任务
            }
        }
    }
}
```

### 提交任务到后端

**文件**: `lib.rs:1504-1514`
```rust
tokio::spawn(async move {
    let git_ref = resolve_git_ref(/*branch_override*/ None).await;
    let result = codex_cloud_tasks_client::CloudBackend::create_task(
        &*backend, &env, &text, &git_ref, /*qa_mode*/ false, best_of_n
    ).await;
    // 发送结果事件
});
```

## 依赖与外部交互

### 上游依赖（被调用）

1. **codex_tui::ComposerInput** (`tui/src/public_widgets/composer_input.rs`)
   - 提供成熟的文本输入体验
   - 支持粘贴检测、快捷键提示

2. **app.rs 中的状态管理**
   - `App::new_task` 持有本结构体
   - `App::env_filter` 提供默认环境
   - `App::best_of_n` 提供默认尝试次数

### 下游调用（调用方）

1. **lib.rs 主事件循环**
   - 创建/销毁 NewTaskPage
   - 处理键盘事件
   - 提交任务到后端

2. **ui.rs 渲染层**
   - `draw_new_task_page()` 渲染页面
   - 显示环境标签和尝试次数

3. **codex_cloud_tasks_client**
   - `CloudBackend::create_task()` 创建任务

## 风险、边界与改进建议

### 当前风险

1. **env_id 为空时提交**
   - 代码检查 `if let Some(env) = page.env_id.clone()` 阻止提交
   - 但 UI 提示不够明显（仅状态栏显示 "No environment selected"）

2. **重复提交风险**
   - `submitting` 标志防止重复，但依赖正确设置
   - 如果异步任务 panic，标志可能无法重置

3. **best_of_n 范围限制**
   - 仅在 CLI 解析时限制 1-4，UI 层没有二次校验

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 空文本提交 | ComposerInput 内部处理，通常不允许空提交 |
| 网络超时 | 依赖后端 client 的超时配置 |
| 环境被删除 | 提交时会返回错误 |
| 粘贴大量文本 | ComposerInput 有 paste-burst 检测和微刷新 |

### 改进建议

1. **增强空环境提示**
   ```rust
   // 可在标题栏使用更醒目的红色警告
   spans.push("Env: NONE - Press Ctrl+O".red().bold());
   ```

2. **添加输入校验**
   - 在提交前检查文本长度（避免空或过长）
   - 检查 env_id 有效性（本地缓存校验）

3. **支持草稿保存**
   - 意外退出时恢复未提交的文本
   - 可存储到临时文件或本地存储

4. **优化 best_of_n 交互**
   - 在输入框旁边显示当前设置的小徽章
   - 支持直接数字键 1-4 快速切换

5. **错误重试机制**
   - 网络错误时提供重试按钮
   - 区分可重试错误和永久错误
