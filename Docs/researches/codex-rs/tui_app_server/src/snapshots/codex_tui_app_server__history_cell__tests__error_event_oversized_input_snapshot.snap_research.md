# Error Event Oversized Input Snapshot - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__error_event_oversized_input_snapshot.snap`

## Snapshot Content
```
■ Message exceeds the maximum length of 1048576 characters (1048577 provided).
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **输入消息超过最大长度限制时的错误显示**。当用户输入或工具输出超过系统限制时，显示友好的错误提示。

### 1.2 业务职责
- **错误提示**: 清晰提示输入过大
- **限制信息**: 显示最大允许长度
- **实际长度**: 显示实际输入长度

### 1.3 错误类型
这是输入验证错误，防止：
- 内存溢出
- 处理超时
- API 限制超出

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 错误符号 | `■` | 标识错误 |
| 错误描述 | "Message exceeds..." | 说明错误原因 |
| 限制值 | 1048576 (1MB) | 显示最大限制 |
| 实际值 | 1048577 | 显示实际值 |

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 常量定义
```rust
const MAX_MESSAGE_LENGTH: usize = 1024 * 1024; // 1MB
```

### 3.2 验证逻辑
```rust
fn validate_input(input: &str) -> Result<(), String> {
    if input.len() > MAX_MESSAGE_LENGTH {
        Err(format!(
            "■ Message exceeds the maximum length of {} characters ({} provided).",
            MAX_MESSAGE_LENGTH,
            input.len()
        ))
    } else {
        Ok(())
    }
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/history_cell.rs` | 错误事件单元格 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 配置
| 常量 | 值 | 说明 |
|------|-----|------|
| MAX_MESSAGE_LENGTH | 1,048,576 | 1MB 字符限制 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 改进建议
1. **分段处理**: 支持分段发送大消息
2. **文件上传**: 大内容建议通过文件上传
3. **进度显示**: 显示当前输入长度/限制

---

## 7. 相关文档链接

- [Error Event](../codex_tui__history_cell__tests__error_event_oversized_input_snapshot.snap_research.md)
