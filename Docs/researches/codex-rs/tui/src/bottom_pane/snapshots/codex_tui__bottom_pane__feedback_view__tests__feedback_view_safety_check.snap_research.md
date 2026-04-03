# 快照研究文档: feedback_view_safety_check

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__feedback_view__tests__feedback_view_safety_check.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/feedback_view.rs`
- **测试函数**: `feedback_view_safety_check`
- **表达式**: `rendered`

---

## 场景与职责

### 功能场景
此快照捕获了**安全检查误报反馈**类别的输入视图。当用户认为AI的安全检查过于严格，拒绝了合理的请求时使用此界面提交反馈。

### 业务职责
1. **误报收集**: 收集安全检查误报案例，帮助改进安全策略
2. **用户申诉**: 为用户提供申诉渠道，解释为什么被拒绝的内容应该是允许的
3. **策略改进**: 为安全团队提供实际案例，用于优化安全检查规则

### 适用场景
- AI错误地拒绝了合理的代码生成请求
- 安全检查过于敏感，阻止了正常的工作流程
- 用户认为某些内容被误判为不安全

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| 标题显示 | 明确安全检查反馈类别 | "Tell us more (safety check)" |
| 专用占位符 | 引导用户描述被拒绝的内容 | "Share what was refused and why it should have been allowed" |
| 输入区域 | 收集具体的误报描述 | `TextArea` 组件 |
| Issue链接 | 引导到GitHub创建issue | `issue_url_for_category()` 生成链接 |

### 专用占位符说明
与其他类别不同，SafetyCheck使用更有针对性的占位符：
```rust
FeedbackCategory::SafetyCheck => (
    "Tell us more (safety check)".to_string(),
    "(optional) Share what was refused and why it should have been allowed".to_string(),
),
```

### 在反馈选择菜单中的描述
```rust
make_feedback_item(
    app_event_tx.clone(),
    "safety check",
    "Benign usage blocked due to safety checks or refusals.",
    FeedbackCategory::SafetyCheck,
)
```

---

## 具体技术实现

### 分类定义
```rust
fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::SafetyCheck => (
            "Tell us more (safety check)".to_string(),
            "(optional) Share what was refused and why it should have been allowed".to_string(),
        ),
        // ...
    }
}

fn feedback_classification(category: FeedbackCategory) -> &'static str {
    match category {
        FeedbackCategory::SafetyCheck => "safety_check",
        // ...
    }
}
```

### Issue URL生成
SafetyCheck与Bug、BadResult、Other一样，会生成后续链接：
```rust
fn issue_url_for_category(
    category: FeedbackCategory,
    thread_id: &str,
    feedback_audience: FeedbackAudience,
) -> Option<String> {
    match category {
        FeedbackCategory::Bug
        | FeedbackCategory::BadResult
        | FeedbackCategory::SafetyCheck
        | FeedbackCategory::Other => Some(match feedback_audience {
            FeedbackAudience::OpenAiEmployee => slack_feedback_url(thread_id),
            FeedbackAudience::External => {
                format!("{BASE_CLI_BUG_ISSUE_URL}&steps=Uploaded%20thread:%20{thread_id}")
            }
        }),
        FeedbackCategory::GoodResult => None,
    }
}
```

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `feedback_view.rs` | 374-377 | SafetyCheck 标题和占位符定义 |
| `feedback_view.rs` | 390 | SafetyCheck 分类字符串映射 |
| `feedback_view.rs` | 406 | SafetyCheck 包含在issue URL生成中 |
| `feedback_view.rs` | 451-455 | 反馈选择菜单中的SafetyCheck选项 |

### 测试代码位置
- **测试函数**: `feedback_view.rs` 第 671-675 行
```rust
#[test]
fn feedback_view_safety_check() {
    let view = make_view(FeedbackCategory::SafetyCheck);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_safety_check", rendered);
}
```

### 相关测试
- **URL可用性测试**: 验证 SafetyCheck 返回有效的issue URL

---

## 依赖与外部交互

### 数据流
```
用户选择 SafetyCheck
    ↓
显示输入视图（本快照）
    ↓
用户输入误报描述
    ↓
提交反馈（分类: "safety_check"）
    ↓
显示GitHub issue链接或内部链接
```

### 受众处理
| 受众 | 处理方式 |
|------|----------|
| OpenAiEmployee | 显示 Slack 链接 (#codex-feedback) |
| External | 显示 GitHub issue 链接 |

---

## 风险边界与改进建议

### 潜在风险

#### 1. 占位符截断
- **问题**: 快照显示占位符被截断为 "Share what was refused and why it should have b"
- **影响**: 用户可能无法看到完整的引导文本
- **建议**: 缩短占位符或使用多行提示

#### 2. 敏感内容风险
- **问题**: 用户可能在描述中重复被标记为敏感的内容
- **影响**: 可能导致反馈本身被拦截
- **建议**: 添加内容过滤或提示用户避免重复敏感内容

#### 3. 缺乏上下文信息
- **问题**: 反馈中可能缺少触发安全检查的具体请求内容
- **建议**: 自动附加相关的对话上下文

### 改进建议

#### 1. 自动附加上下文
```rust
// 建议: 自动包含触发安全检查的原始请求
fn submit(&mut self) {
    let note = self.textarea.text().trim().to_string();
    let context = format!(
        "User description: {}\n\nOriginal request: [自动附加]",
        note
    );
    // ...
}
```

#### 2. 添加快捷选项
```rust
// 建议: 提供常见的误报类型选项
const SAFETY_CHECK_CATEGORIES: &[&str] = &[
    "False positive for code generation",
    "Overly broad content filter",
    "Legitimate security research blocked",
    "Educational content blocked",
];
```

#### 3. 改进占位符
```rust
// 建议: 缩短占位符以适应60列宽度
FeedbackCategory::SafetyCheck => (
    "Tell us more (safety check)".to_string(),
    "What was blocked and why should it be allowed?".to_string(),
),
```

### 测试覆盖分析
- ✅ 基础渲染测试（本快照）
- ✅ URL生成测试
- ⚠️ 建议添加: 占位符完整性测试（验证不被截断）
- ⚠️ 建议添加: 长描述提交测试
