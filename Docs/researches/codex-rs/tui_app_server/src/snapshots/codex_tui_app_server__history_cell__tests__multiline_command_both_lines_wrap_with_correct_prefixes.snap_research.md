# Multiline Command Both Lines Wrap with Correct Prefixes - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__multiline_command_both_lines_wrap_with_correct_prefixes.snap`

## Snapshot Content
```
• Ran first_token_is_long_en
  │ ough_to_wrap
  │ second_token_is_also_lon
  │ … +1 lines
  └ (no output)
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **多行命令在换行时前缀符号的正确显示**。当命令文本很长需要换行时，每一行的前缀符号（如 `│`）应该正确显示。

### 1.2 业务职责
- **多行命令显示**: 支持显示包含换行符的命令
- **前缀符号一致性**: 确保换行后的每一行都有正确的前缀
- **视觉层次清晰**: 通过前缀符号区分命令的不同部分

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
- 多行命令显示
- 换行前缀处理
- 省略指示（`… +1 lines`）

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 命令显示结构
```
• Ran first_token_is_long_en
  │ ough_to_wrap
  │ second_token_is_also_lon
  │ … +1 lines
  └ (no output)
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/history_cell.rs` | 命令执行单元格 |

---

## 5. 相关文档链接

- [Multiline Command Both Lines Wrap](../codex_tui__history_cell__tests__multiline_command_both_lines_wrap_with_correct_prefixes.snap_research.md)
