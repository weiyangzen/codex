# TaskResponse 研究文档

## 场景与职责

`TaskResponse` 是 Codex 后端 OpenAPI 模型库中的核心数据结构，用于表示**任务的完整元数据响应**。它是任务详情 API 的基础结构，主要用于：

1. **任务元数据存储**：保存任务的基本信息和状态
2. **任务详情展示**：在任务详情视图中显示完整信息
3. **状态同步**：支持本地与云端任务状态的同步
4. **PR 关联管理**：追踪任务关联的外部 Pull Request

典型使用场景：
- 获取任务的完整元数据
- 显示任务标题、创建时间、当前回合等信息
- 检查任务是否有未读更新
- 管理任务关联的 PR

## 功能点目的

### 核心功能

该结构体承载以下关键信息：

| 字段 | 类型 | 用途 |
|------|------|------|
| `id` | `String` | 任务的唯一标识符 |
| `created_at` | `Option<f64>` | 任务创建时间（Unix 时间戳） |
| `title` | `String` | 任务标题 |
| `has_generated_title` | `Option<bool>` | 标题是否由 AI 自动生成 |
| `current_turn_id` | `Option<String>` | 当前回合的 ID |
| `has_unread_turn` | `Option<bool>` | 是否有未读的新回合 |
| `denormalized_metadata` | `Option<HashMap<String, Value>>` | 反规范化的元数据 |
| `archived` | `bool` | 是否已归档 |
| `external_pull_requests` | `Vec<ExternalPullRequestResponse>` | 关联的 PR 列表 |

### 与 TaskListItem 的区别

| 特性 | TaskResponse | TaskListItem |
|------|--------------|--------------|
| 用途 | 任务详情 | 任务列表 |
| `created_at` | 有 | 有 |
| `updated_at` | 无 | 有 |
| `current_turn_id` | 有 | 无 |
| `denormalized_metadata` | 有 | 无 |
| `task_status_display` | 无 | 有 |
| `external_pull_requests` | `Vec`（非空） | `Option<Vec>` |

### 设计特点

1. **详情专用**：相比 `TaskListItem`，包含更多详情专用字段
2. **回合追踪**：`current_turn_id` 支持多轮对话的回合管理
3. **反规范化数据**：`denormalized_metadata` 允许快速访问常用元数据
4. **非空 PR 列表**：`external_pull_requests` 使用 `Vec` 而非 `Option<Vec>`，简化处理

## 具体技术实现

### 数据结构定义

```rust
#[derive(Clone, Default, Debug, PartialEq, Serialize, Deserialize)]
pub struct TaskResponse {
    #[serde(rename = "id")]
    pub id: String,
    #[serde(rename = "created_at", skip_serializing_if = "Option::is_none")]
    pub created_at: Option<f64>,
    #[serde(rename = "title")]
    pub title: String,
    #[serde(
        rename = "has_generated_title",
        skip_serializing_if = "Option::is_none"
    )]
    pub has_generated_title: Option<bool>,
    #[serde(rename = "current_turn_id", skip_serializing_if = "Option::is_none")]
    pub current_turn_id: Option<String>,
    #[serde(rename = "has_unread_turn", skip_serializing_if = "Option::is_none")]
    pub has_unread_turn: Option<bool>,
    #[serde(
        rename = "denormalized_metadata",
        skip_serializing_if = "Option::is_none"
    )]
    pub denormalized_metadata: Option<std::collections::HashMap<String, serde_json::Value>>,
    #[serde(rename = "archived")]
    pub archived: bool,
    #[serde(rename = "external_pull_requests")]
    pub external_pull_requests: Vec<models::ExternalPullRequestResponse>,
}
```

### 构造函数

```rust
impl TaskResponse {
    pub fn new(
        id: String,
        title: String,
        archived: bool,
        external_pull_requests: Vec<models::ExternalPullRequestResponse>,
    ) -> TaskResponse {
        TaskResponse {
            id,
            created_at: None,
            title,
            has_generated_title: None,
            current_turn_id: None,
            has_unread_turn: None,
            denormalized_metadata: None,
            archived,
            external_pull_requests,
        }
    }
}
```

构造函数要求核心字段，可选字段默认为 `None` 或空向量。

## 关键代码路径与文件引用

### 定义位置
- **文件**: `codex-rs/codex-backend-openapi-models/src/models/task_response.rs`
- **模块导出**: `codex-rs/codex-backend-openapi-models/src/models/mod.rs`

### 使用方

1. **CodeTaskDetailsResponse** (`code_task_details_response.rs`)
   - 作为 `task` 字段的类型
   - 嵌套在任务详情响应中

2. **chatgpt** (`codex-rs/chatgpt/src/get_task.rs`)
   - 使用 `TaskResponse` 获取任务信息

3. **chatgpt** (`codex-rs/chatgpt/src/apply_command.rs`)
   - 在应用命令时检查任务 PR

### API 交互

典型 JSON 响应格式（作为 CodeTaskDetailsResponse 的一部分）：

```json
{
  "task": {
    "id": "task_abc123",
    "created_at": 1703980800.456,
    "title": "Implement user authentication",
    "has_generated_title": true,
    "current_turn_id": "turn_xyz789",
    "has_unread_turn": false,
    "denormalized_metadata": {
      "environment_id": "env_prod",
      "branch": "feature/auth",
      "repository": "org/repo"
    },
    "archived": false,
    "external_pull_requests": [
      {
        "id": "pr_assoc_456",
        "assistant_turn_id": "turn_xyz789",
        "pull_request": {
          "number": 42,
          "url": "https://github.com/org/repo/pull/42",
          "state": "open",
          "merged": false,
          "mergeable": true
        }
      }
    ]
  }
}
```

## 依赖与外部交互

### 依赖的 crate

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 |
| `serde_json` | Value 类型支持 |

### 内部依赖

- `crate::models::ExternalPullRequestResponse` - 关联的 PR 信息

### 字段关系

```
TaskResponse
├── 基本标识
│   ├── id: 任务 ID
│   └── created_at: 创建时间
├── 标题信息
│   ├── title: 标题文本
│   └── has_generated_title: 是否 AI 生成
├── 回合管理
│   ├── current_turn_id: 当前回合 ID
│   └── has_unread_turn: 未读标记
├── 元数据
│   └── denormalized_metadata: 反规范化数据
├── 状态
│   └── archived: 归档状态
└── PR 关联
    └── external_pull_requests: PR 列表
```

## 风险、边界与改进建议

### 潜在风险

1. **动态元数据**：
   - `denormalized_metadata` 使用 `HashMap<String, Value>`
   - 失去了编译时类型检查
   - 字段结构依赖后端约定

2. **时间戳精度**：
   - `f64` 时间戳在转换时可能有精度损失
   - 建议使用 `chrono::DateTime<Utc>`

3. **PR 列表为空**：
   - `external_pull_requests` 是 `Vec` 而非 `Option<Vec>`
   - 空列表和缺失的语义相同，但处理方式不同

### 边界情况

1. **空标题**：`title` 可能为空字符串
2. **缺失时间戳**：`created_at` 可能为 `None`
3. **无当前回合**：`current_turn_id` 为 `None`（任务刚创建）
4. **已归档任务**：`archived=true`
5. **无 PR 关联**：`external_pull_requests` 为空列表
6. **大量 PR**：一个任务可能关联多个 PR

### 改进建议

1. **强类型元数据**：
   ```rust
   #[derive(Debug, Clone, Deserialize)]
   pub struct TaskMetadata {
       #[serde(rename = "environment_id")]
       pub environment_id: Option<String>,
       pub branch: Option<String>,
       pub repository: Option<String>,
   }
   
   // 替代 denormalized_metadata
   pub metadata: Option<TaskMetadata>,
   ```

2. **添加辅助方法**：
   ```rust
   impl TaskResponse {
       /// 检查是否为代码审查任务
       pub fn is_code_review(&self) -> bool {
           !self.external_pull_requests.is_empty()
       }
       
       /// 获取主 PR（第一个）
       pub fn primary_pr(&self) -> Option<&ExternalPullRequestResponse> {
           self.external_pull_requests.first()
       }
       
       /// 获取格式化的时间戳
       pub fn created_at_datetime(&self) -> Option<DateTime<Utc>> {
           self.created_at.map(|ts| {
               let secs = ts as i64;
               let nanos = ((ts - secs as f64) * 1_000_000_000.0) as u32;
               DateTime::from_timestamp(secs, nanos)
           })
       }
       
       /// 获取标题显示文本
       pub fn display_title(&self) -> String {
           if self.title.is_empty() {
               "<untitled>".to_string()
           } else {
               self.title.clone()
           }
       }
       
       /// 从元数据获取环境 ID
       pub fn environment_id(&self) -> Option<String> {
           self.denormalized_metadata
               .as_ref()
               .and_then(|m| m.get("environment_id"))
               .and_then(|v| v.as_str())
               .map(String::from)
       }
   }
   ```

3. **添加验证方法**：
   ```rust
   impl TaskResponse {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.id.is_empty() {
               return Err(ValidationError::EmptyId);
           }
           if self.title.len() > 200 {
               return Err(ValidationError::TitleTooLong);
           }
           Ok(())
       }
   }
   ```

4. **时间戳改进**：
   ```rust
   #[serde(rename = "created_at")]
   #[serde(with = "chrono::serde::ts_seconds_option")]
   pub created_at: Option<DateTime<Utc>>,
   ```

5. **测试覆盖**：
   - 添加各种场景的序列化/反序列化测试
   - 测试时间戳解析
   - 测试边界情况（空标题、缺失字段等）

### 相关代码

- `code_task_details_response.rs` - 包含 TaskResponse 的上层结构
- `external_pull_request_response.rs` - PR 关联信息
- `task_list_item.rs` - 列表视图的任务信息（对比参考）
- `chatgpt/src/get_task.rs` - 任务获取逻辑
- `chatgpt/src/apply_command.rs` - PR 相关命令处理
