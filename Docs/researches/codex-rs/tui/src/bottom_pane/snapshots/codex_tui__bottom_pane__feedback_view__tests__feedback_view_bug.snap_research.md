# 快照研究文档: feedback_view_bug

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__feedback_view__tests__feedback_view_bug.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/feedback_view.rs`
- **测试函数**: `feedback_view_bug`
- **表达式**: `rendered`

---

## 场景与职责

### 功能场景
此快照捕获了**Bug反馈**类别的输入视图。当用户遇到崩溃、错误消息、界面挂起或异常行为时，使用此界面提交Bug报告。

### 业务职责
1. **Bug报告收集**: 专门用于收集技术问题报告
2. **日志关联**: 通常与日志上传功能配合使用（`include_logs: true`）
3. **GitHub Issue引导**: 提交后会提供GitHub issue链接，引导用户创建详细报告

### 用户交互流程
1. 用户选择"bug"反馈类别
2. 系统展示此输入视图
3. 用户输入Bug描述（可选）
4. 提交后获得GitHub issue链接和thread ID

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| 标题显示 | 明确Bug报告类别 | `feedback_title_and_placeholder()` 返回 "Tell us more (bug)" |
| 输入区域 | 收集Bug描述 | `TextArea` 组件 |
| 占位符 | 引导用户描述问题 | "Write a short description to help us further" |
| 后续链接 | 引导到GitHub创建issue | `issue_url_for_category()` 生成链接 |

### 与其他类别的区别
| 特性 | Bug | BadResult | GoodResult |
|------|-----|-----------|------------|
| 标题 | "Tell us more (bug)" | "Tell us more (bad result)" | "Tell us more (good result)" |
| 生成Issue链接 | ✅ 是 | ✅ 是 | ❌ 否 |
| 内部路由 | go/codex-feedback-internal | go/codex-feedback-internal | N/A |
| 外部路由 | GitHub issues | GitHub issues | 仅显示感谢 |

---

## 具体技术实现

### 分类处理逻辑
```rust
fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::Bug => (
            "Tell us more (bug)".to_string(),
            "(optional) Write a short description to help us further".to_string(),
        ),
        // ...
    }
}

fn feedback_classification(category: FeedbackCategory) -> &'static str {
    match category {
        FeedbackCategory::Bug => "bug",
        // ...
    }
}
```

### Issue URL生成
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

### 提交后处理
```rust
Ok(()) => {
    let prefix = if self.include_logs {
        "• Feedback uploaded."
    } else {
        "• Feedback recorded (no logs)."
    };
    let issue_url = issue_url_for_category(self.category, &thread_id, self.feedback_audience);
    // 根据受众显示不同的后续指引...
}
```

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `feedback_view.rs` | 360-383 | `feedback_title_and_placeholder()` 标题和占位符 |
| `feedback_view.rs` | 385-393 | `feedback_classification()` 分类映射 |
| `feedback_view.rs` | 395-415 | `issue_url_for_category()` Issue链接生成 |
| `feedback_view.rs` | 110-164 | `submit()` 提交处理逻辑 |

### 测试代码位置
- **测试函数**: `feedback_view.rs` 第 657-661 行
```rust
#[test]
fn feedback_view_bug() {
    let view = make_view(FeedbackCategory::Bug);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_bug", rendered);
}
```

### 相关常量
```rust
const BASE_CLI_BUG_ISSUE_URL: &str =
    "https://github.com/openai/codex/issues/new?template=3-cli.yml";
const CODEX_FEEDBACK_INTERNAL_URL: &str = "http://go/codex-feedback-internal";
```

---

## 依赖与外部交互

### 反馈数据流
```
用户输入 → FeedbackNoteView → FeedbackSnapshot.upload_feedback()
    ↓
分类: "bug" + 描述 + 日志 → 服务器
    ↓
返回结果 → 显示成功/失败消息 + GitHub链接
```

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `codex_feedback::FeedbackSnapshot` | 反馈数据快照和上传 |
| `codex_protocol::protocol::SessionSource::Cli` | 标记会话来源 |
| `history_cell::PlainHistoryCell` | 显示提交结果 |

### 受众区分
```rust
pub(crate) enum FeedbackAudience {
    OpenAiEmployee,  // 内部员工: 显示 Slack 链接
    External,        // 外部用户: 显示 GitHub 链接
}
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. URL硬编码风险
- **问题**: GitHub URL和内部URL都是硬编码的
- **影响**: 如果仓库迁移或内部链接变更，需要重新发布
- **建议**: 考虑从配置文件中读取

#### 2. 分类与URL映射风险
- **问题**: `issue_url_for_category()` 中 Bug 和 BadResult 共享相同的URL生成逻辑
- **潜在问题**: 如果未来需要区分Bug和BadResult的处理方式，需要重构
- **建议**: 考虑使用更灵活的配置方式

#### 3. 线程ID依赖
- **问题**: 依赖 `self.snapshot.thread_id` 生成链接
- **风险**: 如果 thread_id 为空或格式不正确，链接可能无效
- **建议**: 添加 thread_id 验证

### 改进建议

#### 1. 添加Bug严重性选择
```rust
// 建议: 在Bug反馈中添加严重性选项
pub(crate) enum BugSeverity {
    Critical,  // 崩溃/数据丢失
    Major,     // 功能无法使用
    Minor,     // 小问题/视觉瑕疵
}
```

#### 2. 自动收集环境信息
```rust
// 建议: 自动附加系统信息
fn collect_system_info() -> String {
    format!(
        "OS: {}\nVersion: {}\nTerminal: {}",
        std::env::consts::OS,
        get_codex_version(),
        detect_terminal()
    )
}
```

#### 3. 改进快照测试
当前测试仅验证渲染输出，建议添加：
- 提交后的历史消息验证
- URL生成正确性验证
- 不同受众的显示差异验证

### 测试覆盖分析
- ✅ 基础渲染测试（本快照）
- ✅ 分类到URL映射测试
- ⚠️ 建议添加: 提交后消息验证测试
- ⚠️ 建议添加: 网络错误处理测试
