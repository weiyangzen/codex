# task_details_with_error.json 研究文档

## 场景与职责

该 JSON 文件是 `codex-backend-client` crate 的测试固件（test fixture），专门用于测试云任务（Cloud Task）详情响应中错误处理逻辑。它模拟了一个在应用代码补丁（patch）时失败的场景，用于验证 `CodeTaskDetailsResponseExt::assistant_error_message()` 方法的正确性。

**所属模块**: `codex-rs/backend-client`  
**测试目标**: `types.rs` 中的错误提取和 PR 类型 diff 回退逻辑

## 功能点目的

### 1. 测试错误信息提取
验证从 `current_assistant_turn.error` 字段中提取结构化错误信息的能力，包括错误代码（code）和错误消息（message）的组合。

### 2. 测试 PR 类型 diff 回退
当 `current_diff_task_turn` 不存在时，验证系统能否从 `current_assistant_turn.output_items` 中的 `pr` 类型项提取 diff（通过 `output_diff` 嵌套字段）。

### 3. 测试错误边界展示
确保 Codex CLI 能够向用户展示有意义的错误信息，帮助诊断代码应用失败等问题。

## 具体技术实现

### 数据结构映射

```rust
pub struct Turn {
    pub output_items: Vec<TurnItem>,
    pub error: Option<TurnError>,  // 关键字段
}

pub struct TurnError {
    pub code: Option<String>,
    pub message: Option<String>,
}

pub struct TurnItem {
    pub kind: String,
    pub output_diff: Option<DiffPayload>,  // PR 类型使用此字段
}

pub struct DiffPayload {
    pub diff: Option<String>,
}
```

### JSON 结构详解

```json
{
  "task": {
    "id": "task_456",
    "title": "Investigate failure",
    "archived": false,
    "external_pull_requests": []
  },
  "current_assistant_turn": {
    "output_items": [
      {
        "type": "pr",
        "output_diff": {
          "diff": "diff --git a/lib.rs b/lib.rs\n+pub fn hello() {}\n"
        }
      }
    ],
    "error": {
      "code": "APPLY_FAILED",
      "message": "Patch could not be applied"
    }
  }
}
```

### 关键差异对比

| 字段 | task_details_with_diff.json | task_details_with_error.json |
|------|---------------------------|-----------------------------|
| `current_user_turn` | 存在 | 缺失 |
| `current_diff_task_turn` | 存在（`output_diff` 类型） | 缺失 |
| `current_assistant_turn.output_items[0].type` | `message` | `pr` |
| `current_assistant_turn.error` | 缺失 | 存在 |
| diff 位置 | `current_diff_task_turn.output_items[].diff` | `current_assistant_turn.output_items[].output_diff.diff` |

### 关键流程

1. **错误信息组合**（`types.rs:247-258`）:
   ```rust
   impl TurnError {
       fn summary(&self) -> Option<String> {
           let code = self.code.as_deref().unwrap_or("");
           let message = self.message.as_deref().unwrap_or("");
           match (code.is_empty(), message.is_empty()) {
               (true, true) => None,
               (false, true) => Some(code.to_string()),
               (true, false) => Some(message.to_string()),
               (false, false) => Some(format!("{code}: {message}")),
           }
       }
   }
   ```
   该逻辑优先展示 `"{code}: {message}"` 格式，如 `"APPLY_FAILED: Patch could not be applied"`。

2. **PR 类型 diff 提取**（`types.rs:159-165`）:
   ```rust
   fn diff_text(&self) -> Option<String> {
       if self.kind == "output_diff" {
           // ...
       } else if self.kind == "pr"
           && let Some(payload) = &self.output_diff
           && let Some(diff) = &payload.diff
           && !diff.is_empty()
       {
           return Some(diff.clone());
       }
       None
   }
   ```
   当 `kind == "pr"` 时，从 `output_diff.diff` 嵌套路径提取 diff。

3. **错误信息访问路径**（`types.rs:300-304`）:
   ```rust
   fn assistant_error_message(&self) -> Option<String> {
       self.current_assistant_turn
           .as_ref()
           .and_then(Turn::error_summary)
   }
   ```

### 测试断言

```rust
#[test]
fn unified_diff_falls_back_to_pr_output_diff() {
    let details = fixture("error");
    let diff = details.unified_diff().expect("diff from pr output");
    assert!(diff.contains("lib.rs"));
}

#[test]
fn assistant_error_message_combines_code_and_message() {
    let details = fixture("error");
    let msg = details
        .assistant_error_message()
        .expect("error should be present");
    assert_eq!(msg, "APPLY_FAILED: Patch could not be applied");
}
```

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|------|------|
| `codex-rs/backend-client/src/types.rs` | 定义 `TurnError`、`TurnItem` 结构及错误提取逻辑 |
| `codex-rs/backend-client/src/lib.rs` | 模块导出，公开 `CodeTaskDetailsResponseExt` trait |

### 错误处理相关代码

```rust
// types.rs:219-222
impl Turn {
    fn error_summary(&self) -> Option<String> {
        self.error.as_ref().and_then(TurnError::summary)
    }
}
```

```rust
// types.rs:260-269 (trait 定义)
pub trait CodeTaskDetailsResponseExt {
    fn unified_diff(&self) -> Option<String>;
    fn assistant_text_messages(&self) -> Vec<String>;
    fn user_text_prompt(&self) -> Option<String>;
    fn assistant_error_message(&self) -> Option<String>;  // 关键方法
}
```

### Fixture 加载

```rust
// types.rs:326-333
fn fixture(name: &str) -> CodeTaskDetailsResponse {
    let json = match name {
        "diff" => include_str!("../tests/fixtures/task_details_with_diff.json"),
        "error" => include_str!("../tests/fixtures/task_details_with_error.json"),
        other => panic!("unknown fixture {other}"),
    };
    serde_json::from_str(json).expect("fixture should deserialize")
}
```

## 依赖与外部交互

### 内部依赖
- `serde` / `serde_json`: JSON 反序列化
- `pretty_assertions`: 测试断言增强

### 业务场景映射

该 fixture 模拟的实际业务场景：

1. **用户请求**: 用户通过 Codex CLI 提交一个代码修改请求
2. **AI 生成**: AI 助手生成了代码补丁（diff）
3. **应用失败**: 尝试将补丁应用到本地代码时失败（如文件已被修改、行号不匹配等）
4. **错误报告**: 后端返回 `APPLY_FAILED` 错误代码和描述性消息
5. **CLI 展示**: Codex CLI 提取并展示 `"APPLY_FAILED: Patch could not be applied"`

### 错误代码体系

从 fixture 可见，后端使用结构化错误代码：
- `code`: 机器可读的错误标识符（如 `APPLY_FAILED`）
- `message`: 人类可读的错误描述

这种设计允许：
- CLI 根据错误代码执行特定处理逻辑
- 用户获得清晰的错误信息
- 未来扩展更多错误类型（如 `MERGE_CONFLICT`、`FILE_NOT_FOUND` 等）

## 风险、边界与改进建议

### 当前风险

1. **错误代码硬编码**
   - 测试断言硬编码了 `"APPLY_FAILED"`
   - 如果后端更改错误代码，测试会失败但可能延迟发现

2. **单错误场景覆盖**
   - 当前 fixture 只覆盖一种错误类型
   - 缺少网络错误、权限错误、超时等其他场景

3. **Turn 组合复杂性**
   - 实际后端响应可能有多种 turn 组合
   - 测试只覆盖 `current_diff_task_turn` 缺失的情况

### 边界情况

| 场景 | 当前处理 | 潜在问题 |
|------|---------|---------|
| 只有 `code` 无 `message` | 返回 `code` | 用户可能不理解错误 |
| 只有 `message` 无 `code` | 返回 `message` | 无法程序化识别错误类型 |
| `code` 和 `message` 都为空 | 返回 `None` | 调用方需处理空错误 |
| `output_diff.diff` 为空字符串 | 返回 `None` | 可能误判为无 diff |

### 改进建议

1. **扩展错误测试覆盖**
   ```rust
   // 建议添加的 fixtures
   - task_details_with_network_error.json
   - task_details_with_partial_error.json  // 部分成功部分失败
   - task_details_with_nested_error.json   // 多层嵌套错误
   ```

2. **错误代码文档化**
   - 在代码中维护错误代码枚举
   - 与后端团队同步错误代码规范

3. **增强错误上下文**
   ```rust
   // 建议扩展
   pub struct TurnError {
       pub code: Option<String>,
       pub message: Option<String>,
       pub details: Option<serde_json::Value>, // 添加详细上下文
       pub recoverable: Option<bool>,          // 是否可恢复
   }
   ```

4. **测试分离**
   - 当前一个 fixture 测试两个独立功能（diff 回退 + 错误提取）
   - 建议拆分为更细粒度的 fixture

### 相关测试矩阵

| 测试函数 | Fixture | 验证功能 |
|---------|---------|---------|
| `unified_diff_falls_back_to_pr_output_diff` | error | PR 类型 diff 回退 |
| `assistant_error_message_combines_code_and_message` | error | 错误信息组合 |
| `unified_diff_prefers_current_diff_task_turn` | diff | 优先使用 diff turn |

### 与 diff fixture 的协同

两个 fixture 形成互补测试矩阵：

```
                    | diff turn | pr turn | error
--------------------|-----------|---------|-------
task_details_with_diff.json   | ✓         | ✗       | ✗
task_details_with_error.json  | ✗         | ✓       | ✓
```

建议添加第三个 fixture 覆盖 `pr turn + 无 error` 场景，完成矩阵。
