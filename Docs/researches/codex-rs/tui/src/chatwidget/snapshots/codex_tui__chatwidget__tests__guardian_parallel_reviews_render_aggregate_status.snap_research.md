# 研究文档: guardian_parallel_reviews_render_aggregate_status.snap

## 场景与职责

该快照文件测试当多个 Guardian 审查并行执行时的聚合状态渲染效果。

## 功能点目的

1. **并行审查展示**: 显示多个并行的安全审查状态
2. **聚合状态**: 汇总多个审查的结果
3. **进度反馈**: 显示审查进行中的状态

## 具体技术实现

### 并行审查场景

```rust
// 多个并行的 Guardian 审查
vec![
    GuardianAssessmentEvent { call_id: "call-1", status: Pending, ... },
    GuardianAssessmentEvent { call_id: "call-2", status: Approved, ... },
    GuardianAssessmentEvent { call_id: "call-3", status: InProgress, ... },
]
```

### 聚合状态显示

```
Guardian Review (3 items)
├─ call-1: ⏳ Pending
├─ call-2: ✓ Approved
└─ call-3: 🔄 In Progress

Overall: Awaiting 2 of 3 reviews
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **状态聚合**: `PendingGuardianReviewStatus` 管理

## 依赖与外部交互

1. **Guardian 服务**: 并行审查API

## 改进建议
1. 添加预计完成时间
2. 允许单独查看每个审查的详情
3. 提供取消单个审查的选项
