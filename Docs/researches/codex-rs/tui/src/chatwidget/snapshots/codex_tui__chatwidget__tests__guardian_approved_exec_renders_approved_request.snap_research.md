# 研究文档: guardian_approved_exec_renders_approved_request.snap

## 场景与职责

该快照文件测试当 Guardian（安全审查系统）批准执行请求时的渲染效果。

## 功能点目的

1. **安全审查展示**: 显示 Guardian 系统的审查结果
2. **批准状态**: 明确标识请求已被安全系统批准
3. **透明度**: 让用户了解安全审查的发生和结果

## 具体技术实现

### Guardian 事件

```rust
codex_protocol::protocol::GuardianAssessmentEvent {
    call_id: String,
    status: GuardianAssessmentStatus::Approved,
    risk_level: GuardianRiskLevel,
    // ...
}
```

### 渲染输出

```
✓ Guardian approved execution
  Command: echo hello world
  Risk level: Low
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **Guardian 系统**: `codex-protocol` 中的安全审查事件

## 依赖与外部交互

1. **Guardian 服务**: 安全审查API

## 改进建议
1. 添加审查理由说明
2. 显示审查耗时
3. 提供审查详细报告的链接
