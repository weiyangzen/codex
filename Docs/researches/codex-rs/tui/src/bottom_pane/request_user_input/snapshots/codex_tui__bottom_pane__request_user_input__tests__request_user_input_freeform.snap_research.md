# 研究文档: request_user_input_freeform.snap

## 场景与职责

本快照文件测试 `RequestUserInputOverlay` 组件处理**纯自由文本输入**（freeform）问题的 UI 渲染。当问题没有预定义选项时，用户可以直接输入文本作为答案。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2811-2825 行，函数 `request_user_input_freeform_snapshot`。

## 功能点目的

### 核心功能
自由文本输入模式允许用户：
1. **直接输入文本**: 没有选项限制，用户可以输入任意内容
2. **可选提交**: 空文本也可以提交（表示跳过此问题）
3. **单问题导航简化**: 只有一个问题时，底部提示简化

### 与选项模式的区别

| 特性 | 选项模式 | 自由文本模式 |
|------|---------|-------------|
| 输入区域 | 选项列表 + 可选笔记 | 纯文本编辑器 |
| 焦点管理 | Options/Notes 切换 | 始终聚焦编辑器 |
| 导航提示 | ←/→ 或 Ctrl+P/N | 简化提示 |
| 占位符 | "Select an option..." | "Type your answer (optional)" |

## 具体技术实现

### 数据结构

```rust
// 自由文本问题的数据结构
RequestUserInputQuestion {
    id: String,
    header: String,
    question: String,
    is_other: false,
    is_secret: false,
    options: None,  // 关键区别：没有选项
}
```

### 关键流程

1. **初始化检测** (`reset_for_request`, 第 545-574 行):
   ```rust
   let has_options = question
       .options
       .as_ref()
       .is_some_and(|options| !options.is_empty());
   
   AnswerState {
       options_state,
       draft: ComposerDraft::default(),
       answer_committed: false,
       notes_visible: !has_options,  // 自由文本模式默认显示输入区
   }
   ```

2. **焦点管理** (`ensure_focus_available`, 第 527-542 行):
   ```rust
   if !self.has_options() {
       self.focus = Focus::Notes;  // 强制聚焦到输入区
       if let Some(answer) = self.current_answer_mut() {
           answer.notes_visible = true;
       }
       return;
   }
   ```

3. **占位符选择** (`notes_placeholder`, 第 401-409 行):
   ```rust
   fn notes_placeholder(&self) -> &'static str {
       if self.has_options() && self.selected_option_index().is_none() {
           SELECT_OPTION_PLACEHOLDER
       } else if self.has_options() {
           NOTES_PLACEHOLDER
       } else {
           ANSWER_PLACEHOLDER  // "Type your answer (optional)"
       }
   }
   ```

### 渲染输出

```
  Question 1/1 (1 unanswered)
  Share details.

  › Type your answer (optional)




  enter to submit answer | esc to interrupt
```

注意：
- 没有选项列表区域
- 输入区域占据更多垂直空间
- 底部提示简化（没有 "tab to add notes"）

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 状态机和输入处理 |
| `render.rs` | UI 渲染 |
| `layout.rs` | 布局计算（区分有/无选项的情况）|

### 关键代码位置

1. **问题类型检测**: `mod.rs:200-204` (`has_options` 方法)
2. **布局计算**: `layout.rs:198-279` (`layout_without_options`)
3. **占位符常量**: `mod.rs:41` (`ANSWER_PLACEHOLDER`)
4. **测试用例**: `mod.rs:2811-2825`

### 布局差异

```rust
// layout.rs:198-222
fn layout_without_options(...) -> LayoutPlan {
    // 处理紧凑布局（空间受限）
    if required > available_height {
        self.layout_without_options_tight(...)
    } else {
        self.layout_without_options_normal(...)
    }
}
```

## 依赖与外部交互

### 复用组件
- `ChatComposer`: 复用主输入框的编辑器组件
- 配置使用 `ChatComposerConfig::plain_text()` 禁用弹窗和斜杠命令

### 答案提交格式

```rust
// 空答案提交
RequestUserInputAnswer {
    answers: Vec::new(),  // 空向量
}

// 有内容时
RequestUserInputAnswer {
    answers: vec!["用户输入的文本".to_string()],
}
```

### 与选项模式的答案差异

| 场景 | 选项模式 | 自由文本模式 |
|------|---------|-------------|
| 空提交 | 提交空向量 | 提交空向量 |
| 有内容 | 选项标签 + 可选笔记 | 直接提交文本 |

## 风险、边界与改进建议

### 潜在风险

1. **空答案语义**: 用户可能混淆"跳过"和"提交空答案"
2. **多行输入**: 当前实现限制输入区域高度（`MIN_COMPOSER_HEIGHT = 3`）
3. **粘贴内容**: 大段粘贴可能导致布局问题

### 边界情况

```rust
// 测试：空文本提交
#[test]
fn freeform_questions_submit_empty_when_empty() {
    // mod.rs:2177-2195
    // 验证空文本提交时返回空答案向量
}

// 测试：未按 Enter 的草稿不提交
#[test]
fn freeform_draft_is_not_submitted_without_enter() {
    // mod.rs:2198-2220
    // 验证只有显式提交才记录答案
}
```

### 改进建议

1. **视觉区分**: 自由文本模式可以有不同的视觉标识，让用户明确知道可以输入任意内容
2. **字符计数**: 对于长文本输入，显示字符计数
3. **多行支持**: 考虑支持 Shift+Enter 插入换行符
4. **历史提示**: 显示类似问题的历史输入作为参考

### 测试覆盖

当前测试验证：
- ✅ 基本渲染（本快照）
- ✅ 空答案提交
- ✅ 草稿不自动提交
- ✅ 需要 Enter 确认

建议添加：
- 长文本输入的渲染
- 粘贴大段内容的处理
- 秘密输入模式（`is_secret: true`）的掩码显示
