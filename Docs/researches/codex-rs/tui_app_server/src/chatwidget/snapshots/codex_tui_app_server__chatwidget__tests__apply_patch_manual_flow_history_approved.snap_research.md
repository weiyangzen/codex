# Research: apply_patch_manual_flow_history_approved (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中补丁手动批准流程的历史记录显示功能。当用户批准一个补丁应用请求后，系统会在历史记录中显示一个简洁的批准决策记录，表明哪些文件被修改以及变更的统计信息。

**测试目的**：确保补丁批准后的历史记录行格式正确，包含文件变更摘要（添加/删除行数）。

## 功能点目的

1. **补丁批准历史记录**：在用户批准补丁应用后，向历史记录中添加一条格式化的决策记录
2. **变更摘要显示**：显示被修改的文件名以及添加/删除的行数统计
3. **视觉一致性**：使用统一的格式（• 符号前缀）与其他历史记录条目保持一致

## 具体技术实现

### Snapshot 内容
```
• Added foo.txt (+1 -0)
    1 +hello
```

### 关键代码路径

1. **补丁批准处理流程**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`apply_patch_manual_flow_history_approved` (约 line 10693)
   - 触发条件：用户按下 'y' 键批准补丁

2. **历史记录单元创建**：
   - 文件：`codex-rs/tui_app_server/src/history_cell.rs`
   - 函数：`new_approval_decision_cell`
   - 作用：创建批准决策的历史记录单元

3. **补丁变更渲染**：
   - 文件：`codex-rs/tui_app_server/src/diff_render.rs`
   - 结构：`DiffSummary`
   - 功能：渲染补丁变更摘要（文件名、添加/删除行数）

4. **批准覆盖层处理**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 方法：`handle_patch_decision`
   - 当用户批准补丁时，发送 `AppEvent::InsertHistoryCell` 事件

### 数据结构

```rust
// 补丁变更定义
codex_protocol::protocol::FileChange::Add {
    content: "hello\n".into(),
}

// 批准决策
ReviewDecision::Approved
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `history_cell` | 创建批准决策历史记录单元 |
| `diff_render::DiffSummary` | 渲染文件变更摘要 |
| `bottom_pane::approval_overlay` | 处理补丁批准决策 |

### 协议依赖
| 类型 | 来源 |
|------|------|
| `ApplyPatchApprovalRequestEvent` | `codex_protocol::protocol` |
| `FileChange` | `codex_protocol::protocol` |
| `ReviewDecision` | `codex_protocol::protocol` |

### App Server 特定
- 使用 `codex_app_server_protocol` 中的协议类型
- 与 `tui` 版本的实现保持平行（遵循 AGENTS.md 中的约定）

## 风险、边界与改进建议

### 当前风险
1. **格式一致性**：如果 `DiffSummary` 的渲染格式改变，snapshot 需要同步更新
2. **多文件补丁**：当前 snapshot 只测试单文件变更，多文件场景的格式需要额外验证

### 边界情况
1. **空内容补丁**：需要验证空内容补丁的显示格式
2. **大量文件变更**：文件数量过多时的截断和折叠行为
3. **特殊字符文件名**：包含空格或特殊字符的文件名显示

### 改进建议
1. **扩展测试覆盖**：添加多文件补丁、二进制文件补丁的 snapshot 测试
2. **国际化准备**：历史记录格式应考虑未来的本地化需求
3. **颜色编码**：考虑为添加/删除行使用不同的颜色（当前 snapshot 为纯文本）

### 与 TUI 版本的对比
- 与 `codex_tui__chatwidget__tests__apply_patch_manual_flow_history_approved.snap` 保持平行实现
- App Server 版本使用相同的底层渲染逻辑
- 两者应定期同步验证一致性
