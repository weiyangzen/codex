# 研究文档: request_user_input_footer_wrap.snap

## 场景与职责

本快照文件是 `codex-tui` 中 `RequestUserInputOverlay` 组件的 UI 快照测试结果，专门测试**底部提示文本自动换行**功能。当终端宽度不足以在一行内显示所有操作提示时，系统需要将提示文本智能地分行显示。

该快照对应的测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2679-2704 行，测试函数为 `request_user_input_footer_wrap_snapshot`。

## 功能点目的

### 核心功能
底部提示栏（Footer Tips）为用户提供当前可用的键盘操作指引。当终端宽度受限时，提示文本需要：
1. **保持提示完整性**：不截断单个提示文本，而是将整个提示移到下一行
2. **使用分隔符**：多个提示之间使用 ` | ` 作为分隔符
3. **高亮关键操作**：当前最重要的操作（如 "enter to submit answer"）使用高亮样式

### 测试场景
- **终端尺寸**: 52xN（宽度较窄）
- **问题类型**: 多问题场景（2个问题）
- **当前状态**: 第一个问题，已选择第2个选项
- **预期行为**: 底部提示需要换行显示

## 具体技术实现

### 数据结构

```rust
// FooterTip 结构体定义（mod.rs 第 100-119 行）
pub(super) struct FooterTip {
    pub(super) text: String,
    pub(super) highlight: bool,  // 是否高亮显示
}
```

### 关键流程

1. **提示生成** (`footer_tips` 方法, 第 429-462 行):
   - 根据当前状态生成提示列表
   - 多问题场景下的提示包括：
     - `"tab to add notes"` (高亮)
     - `"enter to submit answer"` (高亮)
     - `"←/→ to navigate questions"`
     - `"esc to interrupt"`

2. **换行计算** (`wrap_footer_tips` 方法, 第 481-520 行):
   ```rust
   fn wrap_footer_tips(&self, width: u16, tips: Vec<FooterTip>) -> Vec<Vec<FooterTip>> {
       // 使用 TIP_SEPARATOR (" | ") 作为分隔符
       // 逐个检查提示是否能在当前行容纳
       // 不能容纳则开启新行
   }
   ```

3. **宽度计算**:
   - 使用 `UnicodeWidthStr::width()` 计算实际显示宽度
   - 考虑分隔符宽度 `TIP_SEPARATOR`

### 渲染输出示例

```
  Question 1/2 (2 unanswered)
  Choose an option.

    1. Option 1  First choice.
  › 2. Option 2  Second choice.
    3. Option 3  Third choice.

  tab to add notes | enter to submit answer
  ←/→ to navigate questions | esc to interrupt
```

注意：由于宽度限制（52字符），提示被分成了两行显示。

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 核心状态机和提示生成逻辑 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 渲染实现 |
| `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs` | 布局计算 |

### 关键代码位置

1. **提示生成**: `mod.rs:429-462` (`footer_tips` 方法)
2. **换行算法**: `mod.rs:481-520` (`wrap_footer_tips` 方法)
3. **测试用例**: `mod.rs:2679-2704` (`request_user_input_footer_wrap_snapshot`)
4. **常量定义**: `mod.rs:45` (`TIP_SEPARATOR`)

### 依赖模块

```rust
use unicode_width::UnicodeWidthStr;  // 用于计算 Unicode 字符串宽度
```

## 依赖与外部交互

### 输入依赖
- `RequestUserInputEvent`: 包含问题的完整定义
- `ScrollState`: 选项滚动状态
- `ChatComposer`: 用于笔记输入的编辑器

### 输出产物
- 通过 `AppEvent::CodexOp(Op::UserInputAnswer)` 提交用户答案
- 通过 `AppEvent::InsertHistoryCell` 记录历史

### 与协议层的交互
```rust
// 提交答案时的协议交互
codex_protocol::request_user_input::RequestUserInputResponse
```

## 风险、边界与改进建议

### 潜在风险

1. **极端窄屏处理**: 当宽度小于单个提示的最小宽度时，当前实现可能会溢出
2. **多语言支持**: 不同语言的提示文本长度差异可能导致布局问题
3. **高亮样式冲突**: 如果高亮提示被分到不同行，视觉重点可能分散

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 宽度为 0 | 返回空行向量 |
| 单个提示超长 | 直接显示，可能溢出 |
| 恰好填满一行 | 不添加额外换行 |

### 改进建议

1. **添加最小宽度保障**: 在极端窄屏情况下可以考虑水平滚动或截断显示
2. **动态优先级**: 当空间极度受限时，可以隐藏低优先级的提示
3. **响应式布局**: 根据宽度动态调整提示的详细程度
4. **测试覆盖**: 添加更多边界情况的测试，如：
   - 宽度恰好等于提示长度
   - 包含宽字符（如中文）的提示
   - 极窄宽度（< 20 字符）

### 相关测试

```rust
// 验证换行不会分割单个提示
#[test]
fn footer_wraps_tips_without_splitting_individual_tips() {
    // 测试代码在 mod.rs:2566-2600
}
```

该测试确保每个提示作为一个整体被换行，不会被截断或分割。
