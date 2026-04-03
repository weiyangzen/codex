# 研究文档: codex_tui__chatwidget__tests__approval_modal_patch.snap

## 场景与职责

本快照文件验证 **补丁应用审批模态框** 的渲染输出。

当 Codex 需要修改文件时，会弹出此模态框显示具体的文件变更内容，请求用户批准。

## 功能点目的

1. **变更可视化**: 清晰展示文件的增删改操作
2. **代码审查**: 让用户在应用前审查具体变更内容
3. **批量批准**: 支持对特定文件集的批量批准
4. **安全控制**: 防止未经授权的文件修改

## 具体技术实现

### 快照内容结构
```
Would you like to make the following edits?

Reason: The model wants to apply changes

README.md (+2 -0)

  1 +hello
  2 +world

› 1. Yes, proceed (y)
  2. Yes, and don't ask again for these files (a)
  3. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### UI 组件分析

| 元素 | 说明 |
|------|------|
| 标题 | "Would you like to make the following edits?" |
| 原因 | 变更说明 |
| 文件信息 | `README.md (+2 -0)` - 文件名和变更统计 |
| 差异预览 | 带行号的新增内容预览 |
| 选项 | 3个选项，含文件级批量批准 |

### 差异渲染特点
- 行号前缀: `1`, `2`
- 新增标记: `+` 前缀
- 语法: 绿色/亮色显示新增内容

## 关键代码路径与文件引用

### 测试定义
```rust
// tui/src/chatwidget/tests.rs
expression: terminal.backend().vt100().screen().contents()
```

### 相关模块
- `diff_render.rs` - 差异渲染核心逻辑
- `chatwidget.rs` - 处理 `ApplyPatchApprovalRequestEvent`
- `history_cell.rs` - 历史记录中的变更显示

### 协议事件
```rust
ApplyPatchApprovalRequestEvent {
    files: Vec<FileChange>,
    reason: Option<String>,
    // ...
}

FileChange {
    path: PathBuf,
    additions: usize,    // +2
    deletions: usize,    // -0
    preview: String,     // 变更预览
}
```

## 依赖与外部交互

### 核心依赖
- `codex_protocol::protocol::ApplyPatchApprovalRequestEvent`
- `codex_protocol::protocol::FileChange`
- `codex_protocol::protocol::PatchApplyStatus`

### 渲染依赖
- `diff_render.rs` - 统一差异渲染
- `ratatui::style::Color` - 差异颜色（绿/红）

## 风险、边界与改进建议

### 安全风险
1. **预览截断**: 大文件的预览可能被截断，隐藏恶意变更
2. **路径欺骗**: 需要验证文件路径防止目录遍历
3. **二进制文件**: 二进制文件的变更难以预览

### 边界情况
- 多文件变更的显示限制
- 冲突标记的处理
- 超大文件的性能

### 改进建议
1. **语法高亮**: 对代码文件进行语法高亮
2. **折叠展开**: 支持折叠不关注的文件变更
3. **行内差异**: 对修改行显示 word-level 差异
4. **冲突检测**: 提前检测与本地修改的冲突
5. **备份提示**: 提示用户变更前已创建备份

### 相关测试
- `apply_patch_manual_flow_history_approved.snap` - 批准后历史记录
- `exec_approval_modal_exec.snap` - 命令审批对比
