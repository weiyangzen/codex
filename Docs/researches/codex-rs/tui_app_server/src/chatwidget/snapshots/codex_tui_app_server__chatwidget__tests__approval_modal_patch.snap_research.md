# Research: approval_modal_patch (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中补丁批准模态框的渲染效果。当 Codex 需要应用文件变更（添加、修改、删除文件）时，会显示一个模态框展示变更摘要，请求用户批准。

**测试目的**：确保补丁批准模态框正确显示文件变更摘要、变更原因以及可用的决策选项。

## 功能点目的

1. **变更摘要展示**：显示被修改的文件列表和变更统计
2. **差异预览**：展示文件内容的添加/删除行
3. **原因说明**：显示模型提供的变更原因
4. **灵活决策**：提供多种批准选项（单次批准、会话内批准、拒绝）

## 具体技术实现

### Snapshot 内容
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

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`approval_modal_patch_snapshot` (约 line 9714)

2. **补丁批准覆盖层**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 结构：`ApprovalRequest::ApplyPatch`
   - 方法：`build_header` 中的补丁处理分支 (约 line 569)

3. **差异摘要渲染**：
   - 文件：`codex-rs/tui_app_server/src/diff_render.rs`
   - 结构：`DiffSummary`
   - 渲染文件变更统计和内容预览

4. **补丁选项**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 函数：`patch_options` (约 line 821)
   ```rust
   vec![
       ApprovalOption {
           label: "Yes, proceed".to_string(),
           decision: ApprovalDecision::Review(ReviewDecision::Approved),
           // ...
       },
       ApprovalOption {
           label: "Yes, and don't ask again for these files".to_string(),
           decision: ApprovalDecision::Review(ReviewDecision::ApprovedForSession),
           // ...
       },
       ApprovalOption {
           label: "No, and tell Codex what to do differently".to_string(),
           decision: ApprovalDecision::Review(ReviewDecision::Abort),
           // ...
       },
   ]
   ```

### 数据结构

```rust
// 补丁批准请求
codex_protocol::protocol::ApplyPatchApprovalRequestEvent {
    call_id: "call-approve-patch".into(),
    turn_id: "turn-approve-patch".into(),
    changes: {
        let mut changes = HashMap::new();
        changes.insert(
            PathBuf::from("README.md"),
            FileChange::Add {
                content: "hello\nworld\n".into(),
            },
        );
        changes
    },
    reason: Some("The model wants to apply changes".into()),
    grant_root: Some(PathBuf::from("/tmp")),
}

// 批准请求内部表示
ApprovalRequest::ApplyPatch {
    thread_id: ThreadId,
    thread_label: Option<String>,
    id: String,
    reason: Option<String>,
    cwd: PathBuf,
    changes: HashMap<PathBuf, FileChange>,
}
```

### 变更类型支持

| 变更类型 | 显示格式 | 示例 |
|----------|----------|------|
| Add | `(+n -0)` | `README.md (+2 -0)` |
| Edit | `(+n -m)` | `file.rs (+5 -3)` |
| Delete | `(+0 -n)` | `old.txt (+0 -10)` |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::approval_overlay` | 批准模态框主逻辑 |
| `diff_render::DiffSummary` | 差异摘要渲染 |
| `history_cell` | 批准决策历史记录 |

### 协议依赖
| 类型 | 来源 |
|------|------|
| `ApplyPatchApprovalRequestEvent` | `codex_protocol::protocol` |
| `FileChange` | `codex_protocol::protocol` |
| `ReviewDecision` | `codex_protocol::protocol` |

### 渲染流程
1. 接收 `ApplyPatchApprovalRequestEvent`
2. 构建 `ApprovalRequest::ApplyPatch`
3. 创建 `ApprovalOverlay`
4. `build_header` 渲染变更摘要
5. `DiffSummary` 渲染文件差异
6. `patch_options` 提供决策选项

## 风险、边界与改进建议

### 当前风险
1. **大量文件变更**：文件数量过多时，模态框可能超出屏幕
2. **大文件差异**：大文件的差异预览可能过长
3. **二进制文件**：二进制文件的变更显示可能不友好

### 边界情况
1. **空变更**：没有实际内容变更的文件
2. **重命名文件**：文件重命名操作的显示
3. **权限变更**：仅权限变更的文件
4. **多目录变更**：跨多个目录的文件变更

### 改进建议
1. **文件列表折叠**：当文件数量超过阈值时，提供折叠/展开功能
2. **差异截断**：对大文件的差异进行智能截断
3. **语法高亮**：对代码文件的差异进行语法高亮
4. **变更分组**：按目录或变更类型分组显示
5. **冲突检测**：显示与本地修改的潜在冲突

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__approval_modal_patch.snap` 保持平行实现
- 差异渲染逻辑在两个版本中共享
- 补丁批准流程一致

### 测试验证点
1. ✅ 文件变更摘要正确显示（文件名、添加/删除行数）
2. ✅ 变更原因正确显示
3. ✅ 差异内容正确渲染（行号、添加标记）
4. ✅ 三个决策选项正确显示
5. ✅ 页脚提示正确显示

### 相关 Snapshots
- `apply_patch_manual_flow_history_approved`：批准后的历史记录显示
- `approval_modal_patch`：补丁批准模态框
