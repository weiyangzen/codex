# 研究文档: rate_limit_switch_prompt_popup.snap

## 场景与职责

该快照文件测试速率限制切换提示弹窗的渲染效果。当用户接近API速率限制时，提示切换到其他模型。

## 功能点目的

1. **速率限制警告**: 警告用户接近API调用限制
2. **模型切换建议**: 建议切换到不受限制的模型
3. **服务连续性**: 帮助用户避免服务中断

## 具体技术实现

### 速率限制检测

```rust
chat.on_rate_limit_snapshot(Some(RateLimitSnapshot {
    primary: Some(RateLimitWindow {
        used_percent: 92.0,
        window_minutes: Some(60),
        resets_at: None,
    }),
    // ...
}));
```

### 渲染输出

```
Approaching rate limits

You have used 92% of your hourly limit.
Consider switching to gpt-5 to avoid interruptions.

› Switch to gpt-5
  Dismiss
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 2446-2458)
- **速率限制**: `RateLimitWarningState` 管理

## 改进建议
1. 添加剩余时间估计
2. 显示切换后的成本差异
3. 提供自动切换选项
