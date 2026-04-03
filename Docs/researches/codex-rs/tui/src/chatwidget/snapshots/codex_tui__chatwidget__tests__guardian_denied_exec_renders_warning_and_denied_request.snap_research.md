# 研究文档: guardian_denied_exec_renders_warning_and_denied_request.snap

## 场景与职责

该快照文件测试当 Guardian（安全审查系统）拒绝执行请求时的渲染效果，包括警告信息的显示。

## 功能点目的

1. **安全阻止通知**: 告知用户请求被安全系统阻止
2. **风险提示**: 解释为什么请求被拒绝
3. **替代建议**: 可能提供安全的替代方案

## 具体技术实现

### Guardian 拒绝事件

```rust
codex_protocol::protocol::GuardianAssessmentEvent {
    call_id: String,
    status: GuardianAssessmentStatus::Denied,
    risk_level: GuardianRiskLevel::High,
    reason: Some("Potentially destructive command"),
    // ...
}
```

### 渲染输出

```
⚠️  Guardian blocked execution
  Command: rm -rf /
  Risk level: Critical
  Reason: Potentially destructive command detected
  
  This command could cause irreversible damage to your system.
  If you believe this is a mistake, you can:
  • Rephrase your request
  • Use a more specific, less destructive approach
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **风险评估**: Guardian 风险等级评估

## 依赖与外部交互

1. **Guardian 服务**: 安全审查和拒绝理由生成

## 改进建议
1. 添加申诉/覆盖机制（需要额外确认）
2. 提供安全替代命令建议
3. 记录阻止事件用于模型改进
