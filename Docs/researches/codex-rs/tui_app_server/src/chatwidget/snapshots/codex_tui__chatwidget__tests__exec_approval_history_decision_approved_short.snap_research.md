# 研究文档: codex_tui__chatwidget__tests__exec_approval_history_decision_approved_short.snap

## 场景与职责

本快照文件验证 **批准短命令执行** 后的历史记录渲染。

测试用户批准命令执行后的历史记录显示。

## 功能点目的

1. **批准反馈**: 明确显示用户批准了命令执行
2. **命令展示**: 完整显示短命令
3. **历史追踪**: 记录用户的批准决策

## 具体技术实现

### 快照内容
```
✔ You approved codex to run echo hello world this time
```

### UI 元素
- `✔` - 成功/批准指示符
- "You approved codex to run" - 批准说明
- 完整命令 - `echo hello world`
- "this time" - 强调本次批准（非永久）

### 与取消的区别
| 操作 | 指示符 | 文本 |
|------|--------|------|
| 批准 | `✔` | "You approved..." |
| 取消 | `✗` | "You canceled..." |

## 关键代码路径与文件引用

### 测试定义
```rust
expression: lines_to_single_string(&decision)
```

### 批准流程
```
显示审批模态框
    ↓
用户选择 "Yes"
    ↓
发送批准事件
    ↓
记录到历史
```

## 依赖与外部交互

### 协议事件
- 发送批准到后端
- 等待执行结果

## 风险、边界与改进建议

### 改进建议
1. **执行结果**: 批准后显示执行结果
2. **时间戳**: 添加批准时间
3. **永久批准**: 区分 "this time" 和 "always"
