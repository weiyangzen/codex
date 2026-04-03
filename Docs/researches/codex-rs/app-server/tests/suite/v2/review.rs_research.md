# review.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**代码审查功能** (`review/start`)。该功能允许用户对特定的代码提交、分支或自定义指令进行 AI 辅助的代码审查，获取改进建议和潜在问题分析。

测试场景覆盖：
1. **内联审查流程** - 在当前线程中执行审查并展示结果
2. **分离审查模式** - 在独立线程中执行审查，不影响当前工作流
3. **审查目标类型** - 支持 Commit、BaseBranch、Custom 三种审查目标
4. **审查交付方式** - Inline 和 Detached 两种交付模式
5. **执行批准集成** - 验证审查过程中的命令执行批准流程

## 功能点目的

### 1. 代码审查工作流
- **启动审查** (`review/start`): 指定审查目标和交付方式
- **审查执行**: AI 分析代码并生成审查报告
- **结果交付**: 
  - `Inline`: 在当前线程展示审查结果
  - `Detached`: 创建独立线程展示结果

### 2. 审查目标类型
| 类型 | 说明 | 使用场景 |
|-----|------|---------|
| `Commit` | 审查特定提交 | 审查已完成的代码变更 |
| `BaseBranch` | 审查相对于基础分支的变更 | PR/MR 审查 |
| `Custom` | 执行自定义审查指令 | 特定关注点审查 |

### 3. 审查数据结构
- **Findings**: 发现的问题列表（标题、描述、置信度、优先级、代码位置）
- **Overall Assessment**: 整体评估（正确性、解释、置信度）

### 4. 特殊审查项
- `EnteredReviewMode`: 标记审查开始
- `ExitedReviewMode`: 标记审查结束，包含审查结果

## 具体技术实现

### 关键流程

```
测试用例: review_start_runs_review_turn_and_emits_code_review_item
1. 创建 mock Responses API 服务器（返回审查结果 JSON）
2. 初始化 MCP 连接
3. 启动线程
4. 发送 review/start 请求
   - target: Commit { sha, title }
   - delivery: Inline
5. 验证响应包含 turn 和 review_thread_id
6. 监听 item/started 通知，查找 EnteredReviewMode 项
7. 监听 item/completed 通知，查找 ExitedReviewMode 项
8. 验证审查结果包含预期的发现项

测试用例: review_start_with_detached_delivery_returns_new_thread_id
1-3. 同上
4. 先执行一个回合使线程 materialized
5. 发送 review/start 请求
   - delivery: Detached
6. 验证返回的 review_thread_id 与原线程不同
7. 验证收到 thread/started 通知（新线程）
```

### 核心数据结构

```rust
// 审查启动参数
ReviewStartParams {
    thread_id: String,
    delivery: Option<ReviewDelivery>,  // Inline 或 Detached
    target: ReviewTarget,
}

// 审查目标
ReviewTarget::Commit {
    sha: String,
    title: Option<String>,
}
ReviewTarget::BaseBranch {
    branch: String,
}
ReviewTarget::Custom {
    instructions: String,
}

// 审查响应
ReviewStartResponse {
    turn: Turn,
    review_thread_id: String,  // 审查执行的线程 ID
}

// 审查结果 JSON 结构（AI 返回）
{
    "findings": [{
        "title": "Prefer Stylize helpers",
        "body": "Use .dim()/.bold() chaining...",
        "confidence_score": 0.9,
        "priority": 1,
        "code_location": {
            "absolute_file_path": "/tmp/file.rs",
            "line_range": {"start": 10, "end": 20}
        }
    }],
    "overall_correctness": "good",
    "overall_explanation": "Looks solid overall...",
    "overall_confidence_score": 0.75
}

// 审查模式标记项
ThreadItem::EnteredReviewMode {
    id: String,      // turn_id
    review: String,  // 审查描述（如 "commit 1234567: Tidy UI colors"）
}
ThreadItem::ExitedReviewMode {
    id: String,
    review: String,  // 完整审查报告
}
```

### 交付模式对比

| 模式 | 线程行为 | 使用场景 |
|-----|---------|---------|
| `Inline` | 在当前线程添加审查项 | 快速查看审查结果 |
| `Detached` | 创建新线程执行审查 | 不影响当前工作流 |

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/review.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `send_review_start_request()` (行689)

- `codex-rs/app-server/tests/common/mock_model_server.rs`
  - `create_mock_responses_server_repeating_assistant()` - 重复返回相同响应

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ReviewStart => "review/start"` (行405)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ReviewStartParams` (行2642)
  - `ReviewStartResponse`
  - `ReviewDelivery` (Inline/Detached)
  - `ReviewTarget` (Commit/BaseBranch/Custom)
  - `TurnStatus` (InProgress/Completed)

### 核心实现
- `codex-rs/core/src/review_prompts.rs` - 审查提示模板
- `codex-rs/core/src/review.rs` - 审查功能核心实现
- `codex-rs/app-server/src/codex_message_processor.rs` - 审查消息处理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `app_test_support` | 测试辅助函数 |
| `serde_json::json` | 审查结果 JSON 构造 |
| `tokio::time::timeout` | 异步超时控制 |
| `tempfile::TempDir` | 隔离测试环境 |

### Mock 服务器配置
```rust
let review_payload = json!({
    "findings": [...],
    "overall_correctness": "good",
    "overall_explanation": "...",
    "overall_confidence_score": 0.75
}).to_string();

let server = create_mock_responses_server_repeating_assistant(&review_payload).await;
```

### 配置要求
```toml
approval_policy = "never"  # 或 "untrusted"

[features]
shell_snapshot = false
```

## 风险、边界与改进建议

### 当前风险

1. **Flaky 测试标记**
   - `review_start_exec_approval_item_id_matches_command_execution_item` 被标记为 `#[ignore = "TODO(owenlin0): flaky"]`
   - 执行批准与审查项 ID 匹配存在时序问题
   - 建议: 修复时序依赖或增加重试机制

2. **Windows CI 不稳定**
   - `review_start_with_detached_delivery_returns_new_thread_id` 在 Windows CI 上标记为 `#[cfg_attr(target_os = "windows", ignore = "flaky on windows CI")]`
   - 文件系统操作在 Windows 上可能不稳定
   - 建议: 使用更可靠的同步机制

3. **审查结果验证有限**
   - 仅验证审查结果包含特定字符串
   - 未验证完整的数据结构解析
   - 建议: 增强结果验证

### 边界情况

1. **空审查结果**
   - 测试了空 findings 数组（Detached 测试）
   - 但未验证空结果的处理逻辑
   - 建议: 添加空结果 UI 展示测试

2. **无效目标验证**
   - 测试了空 SHA、空分支、空指令的拒绝
   - 但未测试格式无效的情况
   - 建议: 添加格式验证测试

3. **大文件审查**
   - 未测试大型代码库的审查性能
   - 建议: 添加性能基准测试

4. **并发审查**
   - 未测试同一提交多次并发审查
   - 建议: 添加并发测试

### 改进建议

1. **修复 Flaky 测试**
   ```rust
   // 当前被忽略的测试需要修复:
   #[tokio::test]
   #[ignore = "TODO(owenlin0): flaky"]
   async fn review_start_exec_approval_item_id_matches_command_execution_item()
   ```

2. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn review_start_base_branch()  // 基础分支审查
   - async fn review_start_large_commit()  // 大提交审查
   - async fn review_start_with_shell_command()  // 含命令的审查
   - async fn review_concurrent_same_target()  // 并发审查
   ```

3. **错误场景测试**
   - 后端返回错误时的处理
   - 网络中断时的恢复

4. **性能测试**
   - 审查延迟基准
   - 大文件内存使用

### 相关测试文件
- `codex-rs/core/tests/suite/review.rs` - 核心审查测试
- `codex-rs/app-server/tests/suite/v2/thread_start.rs` - 线程管理
