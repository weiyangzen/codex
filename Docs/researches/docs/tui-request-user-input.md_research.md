# tui-request-user-input.md 研究文档

## 场景与职责

tui-request-user-input.md 是 Codex CLI 项目中关于 TUI 用户输入请求覆盖层（Request User Input Overlay）的设计文档。该覆盖层用于收集 `RequestUserInputEvent` 的答案。

**适用场景：**
- TUI 开发者需要理解用户输入请求的实现
- 调试用户输入相关问题
- 扩展或修改输入收集功能

## 功能点目的

### 1. 概述

覆盖层一次渲染一个问题并收集：
- 单个选定选项（当选项存在时）
- 自由形式备注（始终可用）

当选项存在时，备注按选定选项存储，第一个选项默认选中，所以每个选项问题都有答案。如果问题没有选项且没有提供备注，答案作为 `skipped` 提交。

### 2. 焦点和输入路由

覆盖层跟踪小焦点状态：

- **选项**：Up/Down 移动选择，Space 选择
- **备注**：文本输入编辑当前选定选项的备注

在选项聚焦时键入自动切换到备注以减少自由形式输入的摩擦。

### 3. 导航

| 键 | 动作 |
|---|------|
| Enter | 进入下一个问题 |
| Enter（最后一个问题） | 提交所有答案 |
| PageUp/PageDown | 在问题间导航（当存在多个时） |
| Esc | 在选项选择模式下中断运行 |
| Tab/Esc（备注打开） | 清除备注并返回选项选择 |

### 4. 布局优先级

布局优先保持问题和所有选项可见。备注和页脚提示随着空间缩小而折叠，在紧凑终端中备注回退到单行 "Notes: ..." 输入。

## 具体技术实现

### 状态管理

```
RequestUserInputOverlay
    ├── questions: Vec<Question>
    ├── current_index: usize
    ├── selected_option: Option<usize>
    ├── notes: HashMap<usize, String>
    └── focus: Focus

enum Focus {
    Options,
    Notes,
}
```

### 事件处理流程

```
接收键事件
    ↓
根据焦点状态分发
    ↓
如果是 Options 焦点：
    - Up/Down：移动选择
    - Space：选择选项
    - 字符键：切换到 Notes 焦点并输入
    ↓
如果是 Notes 焦点：
    - 文本输入处理
    - Tab/Esc：返回 Options 焦点
    ↓
Enter：
    - 如果不是最后一个：current_index += 1
    - 如果是最后一个：提交所有答案
```

### 答案提交格式

```rust
struct UserInputAnswer {
    question_id: String,
    selected_option: Option<String>,
    notes: Option<String>,
    status: AnswerStatus,
}

enum AnswerStatus {
    Answered,
    Skipped,
}
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/tui-request-user-input.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/` | TUI 实现目录 |
| `/home/sansha/Github/codex/codex-rs/protocol/src/` | 协议定义（推测） |

### 相关类型（推测）

**RequestUserInputEvent**：
```rust
struct RequestUserInputEvent {
    questions: Vec<Question>,
}

struct Question {
    id: String,
    text: String,
    options: Option<Vec<String>>,
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**
   - TUI 渲染框架
   - 布局管理

### 内部依赖

1. **事件系统**
   - `RequestUserInputEvent` 处理
   - 答案提交

2. **布局系统**
   - 响应式布局
   - 空间约束处理

## 风险、边界与改进建议

### 潜在风险

1. **输入丢失**
   - 在选项和备注间切换时可能丢失输入
   - 建议：添加未保存更改提示

2. **导航混乱**
   - 多问题导航可能令人困惑
   - 建议：添加进度指示器

3. **小屏幕体验**
   - 紧凑终端中的布局问题
   - 建议：优化小屏幕布局

### 边界情况

1. **无选项问题**
   - 纯文本输入问题
   - 空备注处理

2. **大量选项**
   - 选项列表溢出
   - 滚动处理

3. **大量问题**
   - 多页面导航
   - 进度跟踪

### 改进建议

1. **用户体验增强**
   - 添加进度指示（如 "问题 2/5"）
   - 提供问题导航预览
   - 添加确认对话框

2. **可访问性**
   - 屏幕阅读器支持
   - 键盘快捷键提示

3. **布局优化**
   - 更好的小屏幕适配
   - 选项列表滚动

4. **功能扩展**
   - 支持多选
   - 支持富文本备注
   - 添加默认值配置

5. **验证**
   - 输入验证
   - 必填字段检查
