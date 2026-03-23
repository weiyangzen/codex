# AGENTS.md 研究文档

## 场景与职责

`AGENTS.md` 是 `codex-rs/tui/src/bottom_pane/` 目录的代理指导文档，用于规范该目录下状态机（state machines）的开发和维护流程。该目录主要包含 `paste-burst` 和 `chat-composer` 两个核心状态机的实现。

## 功能点目的

本文档的核心目的是确保代码实现与文档保持同步：

1. **文档同步要求**：当修改 `paste-burst` 或 `chat-composer` 状态机时，必须同步更新相关模块文档
2. **叙事文档维护**：`docs/tui-chat-composer.md` 需要在行为/假设变更时更新
3. **实现一致性检查**：确保文档只提及实际存在的 API/行为

## 具体技术实现

### 关键文档引用

- 模块文档：`chat_composer.rs` 和 `paste_burst.rs`
- 叙事文档：`docs/tui-chat-composer.md`
- 关键行为覆盖：
  - Enter 处理
  - Retro-capture（回溯捕获）
  - Flush/clear 规则
  - `disable_paste_burst` 语义
  - 非 ASCII/IME 处理

### 实用检查清单

编辑后需要验证：
- 文档提及的 API/行为是否真实存在于代码中
- Enter/newline 路径是否正确描述
- `disable_paste_burst` 语义是否准确

## 关键代码路径与文件引用

```
codex-rs/tui/src/bottom_pane/
├── chat_composer.rs          # ChatComposer 状态机实现
├── paste_burst.rs            # Paste-burst 状态机实现
├── AGENTS.md                 # 本文档
└── docs/tui-chat-composer.md # 叙事文档（项目级）
```

## 依赖与外部交互

- 依赖上层文档：`docs/tui-chat-composer.md`
- 与 `chat_composer.rs` 和 `paste_burst.rs` 紧密耦合
- 属于 TUI 项目的 bottom pane 子系统

## 风险、边界与改进建议

### 风险点

1. **文档漂移风险**：代码变更后忘记更新文档是常见问题
2. **不一致风险**：文档描述的 API 可能与实际代码不符
3. **维护负担**：需要同时维护代码、模块文档和叙事文档三处

### 边界情况

- 文档本身不包含代码逻辑，仅提供开发指导
- 不涉及运行时行为，纯开发时参考

### 改进建议

1. **自动化检查**：可添加 CI 检查，当 `chat_composer.rs` 或 `paste_burst.rs` 变更时提醒更新文档
2. **文档测试**：考虑将文档中的代码示例转为可测试的 doctests
3. **单一来源**：考虑将部分文档内容从 narrative doc 迁移到代码注释，减少维护点
