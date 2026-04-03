# AGENTS.md 研究文档

## 场景与职责

此文件是 `codex-rs/tui_app_server/src/bottom_pane/` 目录的局部 AGENTS.md，专门针对 bottom pane 中的状态机（state machines）提供开发指南。Bottom pane 是 TUI 的交互式页脚区域，包含 `ChatComposer`（可编辑的提示输入框）和一系列临时的 `BottomPaneView`（弹出窗口/模态框）。

该文档的核心职责是确保状态机实现（特别是 `chat_composer.rs` 和 `paste_burst.rs`）与相关文档保持同步。

## 功能点目的

1. **状态机文档同步要求**
   - 修改 `chat_composer.rs` 和/或 `paste_burst.rs` 中的状态机时，必须同步更新模块文档
   - 确保模块文档保持可读性，提供自顶向下的当前行为解释
   - 叙事文档 `docs/tui-chat-composer.md` 需要在行为/假设变更时更新

2. **关键行为文档覆盖**
   - Enter 键处理逻辑
   - Retro-capture（追溯捕获）机制
   - Flush/clear 规则
   - `disable_paste_burst` 语义
   - 非 ASCII/IME 输入处理

3. **一致性校验**
   - 编辑后需检查文档仅提及代码中实际存在的 API/行为
   - 特别关注 Enter/newline 路径和 `disable_paste_burst` 语义

## 具体技术实现

### 涉及的关键模块

| 模块 | 功能 |
|------|------|
| `chat_composer.rs` | 聊天输入编辑器，处理用户输入、粘贴爆发检测、IME 输入等 |
| `paste_burst.rs` | 粘贴爆发状态机，管理批量粘贴行为的检测和处理 |

### 关键配置项

- `disable_paste_burst`: 控制是否禁用粘贴爆发检测的配置标志
- Enter/newline 路径: 处理用户提交输入的多条代码路径

## 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` - 聊天编辑器实现
- `codex-rs/tui_app_server/src/bottom_pane/paste_burst.rs` - 粘贴爆发状态机
- `docs/tui-chat-composer.md` - 叙事文档（跨目录引用）

### 依赖关系
```
bottom_pane/
├── chat_composer.rs      (主要状态机)
├── paste_burst.rs        (粘贴爆发状态机)
└── AGENTS.md            (本文件 - 开发指南)
```

## 依赖与外部交互

### 外部文档依赖
- `docs/tui-chat-composer.md` - 需要在行为变更时同步更新

### 代码依赖
- 依赖 `ChatComposer` 和 `paste_burst` 的具体实现细节
- 与 `BottomPaneView` trait 交互（在 `bottom_pane_view.rs` 定义）

## 风险、边界与改进建议

### 风险点
1. **文档漂移风险**: 状态机代码与文档容易不同步，导致开发者依赖过时信息
2. **隐式契约**: `disable_paste_burst` 等配置标志的行为语义需要在代码和文档中保持一致

### 边界情况
1. **IME 输入处理**: 多字节字符和 IME 组合输入的状态转换需要特别测试
2. **粘贴爆发检测**: 时间窗口内的批量粘贴行为检测可能存在边缘情况

### 改进建议
1. 考虑添加自动化检查或 lint 规则，检测状态机变更时文档是否同步更新
2. 为 `disable_paste_burst` 等行为添加更详细的代码注释，解释其语义
3. 考虑将 `docs/tui-chat-composer.md` 的部分内容内联到代码文档中，减少跨文件同步负担
