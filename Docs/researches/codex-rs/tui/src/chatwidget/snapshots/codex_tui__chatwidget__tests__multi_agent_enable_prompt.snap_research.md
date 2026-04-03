# 研究文档: multi_agent_enable_prompt.snap

## 场景与职责

该快照文件测试多代理（multi-agent）功能启用提示弹窗的渲染效果。

## 功能点目的

1. **功能启用**: 请求用户启用子代理功能
2. **功能说明**: 解释多代理功能的作用
3. **延迟生效**: 说明更改将在下次会话生效

## 具体技术实现

### 弹窗内容

```rust
const MULTI_AGENT_ENABLE_TITLE: &str = "Enable subagents?";
const MULTI_AGENT_ENABLE_YES: &str = "Yes, enable";
const MULTI_AGENT_ENABLE_NO: &str = "Not now";
const MULTI_AGENT_ENABLE_NOTICE: &str = "Subagents will be enabled in the next session.";
```

### 渲染输出

```
Enable subagents?

Subagents allow Codex to spawn specialized agents for complex tasks.
This feature is currently in beta.

› Yes, enable
  Not now

Subagents will be enabled in the next session.
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **功能管理**: `Feature::CollaborationModes` 或相关功能标志

## 改进建议
1. 添加多代理功能的详细说明
2. 显示启用后的行为变化
3. 提供试用模式
