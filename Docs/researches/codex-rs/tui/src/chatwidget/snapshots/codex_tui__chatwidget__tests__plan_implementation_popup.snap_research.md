# 研究文档: plan_implementation_popup.snap

## 场景与职责

该快照文件测试计划实现确认弹窗的渲染效果。当AI完成计划制定后，询问用户是否开始执行计划。

## 功能点目的

1. **计划确认**: 让用户确认是否执行制定的计划
2. **模式切换**: 从计划模式切换到执行模式
3. **用户控制**: 给用户最终决定是否执行

## 具体技术实现

### 弹窗常量

```rust
const PLAN_IMPLEMENTATION_TITLE: &str = "Implement this plan?";
const PLAN_IMPLEMENTATION_YES: &str = "Yes, implement this plan";
const PLAN_IMPLEMENTATION_NO: &str = "No, stay in Plan mode";
const PLAN_IMPLEMENTATION_CODING_MESSAGE: &str = "Implement the plan.";
```

### 渲染输出

```
Implement this plan?

The plan has been created. Ready to start implementation?

› Yes, implement this plan
  No, stay in Plan mode
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 2460-2496)
- **计划模式**: `ModeKind::Plan` 协作模式

## 改进建议
1. 添加计划摘要预览
2. 显示预计执行时间
3. 提供分步执行选项
