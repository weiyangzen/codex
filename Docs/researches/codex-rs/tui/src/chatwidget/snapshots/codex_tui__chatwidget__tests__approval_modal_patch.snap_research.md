# 研究文档: approval_modal_patch.snap

## 场景与职责

该快照文件测试代码补丁（patch）审批模态框的渲染效果。当 Codex 需要应用代码修改时，显示此模态框让用户审查和批准补丁。

## 功能点目的

1. **补丁审查**: 让用户在应用代码变更前查看补丁内容
2. **代码安全**: 防止意外的代码修改
3. **变更可视化**: 清晰展示将要应用的代码变更

## 具体技术实现

### 关键数据结构

```rust
codex_protocol::protocol::ApplyPatchApprovalRequestEvent {
    call_id: String,
    approval_id: Option<String>,
    turn_id: String,
    // 补丁相关信息：文件路径、变更内容等
}
```

### 渲染特点

- 显示补丁将修改的文件列表
- 展示变更的统计信息（添加/删除行数）
- 提供 "Apply" 和 "Cancel" 选项
- 可能包含补丁预览（受限于屏幕空间）

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **补丁处理**: `codex-rs/apply-patch/` 目录下的补丁应用逻辑
- **模态框渲染**: `ChatWidget` 的渲染方法

## 依赖与外部交互

1. **apply-patch crate**: 补丁解析和应用
2. **codex-protocol**: 补丁审批事件定义

## 风险、边界与改进建议

### 风险
- 大型补丁可能难以在模态框中完整展示
- 复杂变更可能难以快速理解

### 边界情况
- 二进制文件的补丁处理
- 冲突补丁的检测和提示
- 补丁应用失败的回滚机制

### 改进建议
1. 添加补丁差异的语法高亮
2. 提供 side-by-side 对比视图
3. 支持补丁的部分应用（选择特定文件）
4. 添加补丁影响分析（哪些函数/类被修改）
