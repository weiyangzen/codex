# get_task.rs 研究文档

## 场景与职责

`get_task.rs` 是 `codex-chatgpt` crate 中负责 **获取 Codex Agent 任务详情**的模块。该模块定义了 ChatGPT Wham 任务 API 的数据结构，并提供获取任务信息的接口，主要用于支持 `apply_command` 将云端生成的代码变更应用到本地。

### 核心使用场景

1. **代码变更应用**：`apply_command.rs` 调用获取任务中的 diff 输出
2. **任务状态查询**：获取任务的当前状态和输出
3. **结果提取**：从任务响应中提取 PR 类型的输出项（包含 diff）

## 功能点目的

### 1. GetTaskResponse 任务响应
定义任务 API 的响应结构：
- `current_diff_task_turn`: 当前 diff 任务回合（可选）

### 2. AssistantTurn 助手回合
表示 Agent 的一次响应回合：
- `output_items`: 输出项列表

### 3. OutputItem 输出项枚举
支持多种输出类型：
- `Pr(PrOutputItem)`: PR 类型输出（包含 diff）
- `Other`: 其他类型（被忽略）

### 4. PrOutputItem PR 输出
PR 类型输出的具体内容：
- `output_diff`: 包含 diff 字符串的结构

### 5. OutputDiff Diff 内容
实际的代码变更：
- `diff`: 统一 diff 格式的字符串

### 6. get_task API 调用
执行实际的 API 请求：
- 构造路径 `/wham/tasks/{task_id}`
- 调用 `chatgpt_get_request`
- 返回解析后的响应

## 具体技术实现

### 数据结构定义

```rust
// 任务响应根结构
#[derive(Debug, Deserialize)]
pub struct GetTaskResponse {
    pub current_diff_task_turn: Option<AssistantTurn>,
}

// 助手回合
#[derive(Debug, Deserialize)]
pub struct AssistantTurn {
    pub output_items: Vec<OutputItem>,
}

// 输出项枚举（标签联合）
#[derive(Debug, Deserialize)]
#[serde(tag = "type")]  // 使用 type 字段进行反序列化分发
pub enum OutputItem {
    #[serde(rename = "pr")]
    Pr(PrOutputItem),
    #[serde(other)]  // 捕获所有其他类型
    Other,
}

// PR 输出项
#[derive(Debug, Deserialize)]
pub struct PrOutputItem {
    pub output_diff: OutputDiff,
}

// Diff 内容
#[derive(Debug, Deserialize)]
pub struct OutputDiff {
    pub diff: String,  // 统一 diff 格式
}
```

### API 调用实现

```rust
pub(crate) async fn get_task(
    config: &Config, 
    task_id: String
) -> anyhow::Result<GetTaskResponse> {
    let path = format!("/wham/tasks/{task_id}");
    chatgpt_get_request(config, path).await
}
```

### 使用模式

在 `apply_command.rs` 中提取 diff：

```rust
pub async fn apply_diff_from_task(
    task_response: GetTaskResponse,
    cwd: Option<PathBuf>,
) -> anyhow::Result<()> {
    // 1. 获取当前 diff 回合
    let diff_turn = match task_response.current_diff_task_turn {
        Some(turn) => turn,
        None => anyhow::bail!("No diff turn found"),
    };
    
    // 2. 在输出项中查找 PR 类型
    let output_diff = diff_turn.output_items.iter().find_map(|item| match item {
        OutputItem::Pr(PrOutputItem { output_diff }) => Some(output_diff),
        _ => None,
    });
    
    // 3. 应用 diff
    match output_diff {
        Some(output_diff) => apply_diff(&output_diff.diff, cwd).await,
        None => anyhow::bail!("No PR output item found"),
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `chatgpt_client` | `chatgpt_client.rs` | HTTP GET 请求 |

### 外部依赖

| Crate | 模块 | 用途 |
|-------|------|------|
| `codex_core` | `config::Config` | 配置访问 |
| `serde` | `Deserialize` | 反序列化派生 |

### 调用链

```
apply_command::run_apply_command
└── apply_command::apply_diff_from_task
    ├── get_task::get_task
    │   └── chatgpt_client::chatgpt_get_request
    │       ├── init_chatgpt_token_from_auth
    │       └── HTTP GET /wham/tasks/{task_id}
    └── apply_diff
        └── codex_git::apply_git_patch
```

### API 端点

- **URL**: `GET /wham/tasks/{task_id}`
- **认证**: Bearer Token + chatgpt-account-id
- **基础 URL**: `config.chatgpt_base_url`（默认 https://chatgpt.com）

## 依赖与外部交互

### 1. ChatGPT Wham API

Wham（Workflow Human-Agent Model）是 ChatGPT 的任务管理系统：
- 存储 Agent 会话历史
- 跟踪任务状态和输出
- 支持多种输出类型（PR、消息、文件等）

### 2. 响应格式示例

```json
{
  "current_diff_task_turn": {
    "output_items": [
      {
        "type": "pr",
        "output_diff": {
          "diff": "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new\n"
        }
      },
      {
        "type": "message",
        "content": "I've made the changes..."
      }
    ]
  }
}
```

### 3. 认证要求

需要有效的 ChatGPT 认证：
- `id_token`：身份令牌
- `access_token`：访问令牌
- `account_id`：账户标识

## 风险、边界与改进建议

### 风险点

1. **API 稳定性**
   - Wham API 是内部 API，可能变更
   - 字段缺失或类型变更会导致反序列化失败
   - 建议：添加字段级别的 `#[serde(default)]`

2. **单一输出类型假设**
   - 当前只处理 `Pr` 类型输出
   - 其他类型（如文件下载）被忽略
   - 建议：支持更多输出类型

3. **无任务状态检查**
   - 不验证任务是否已完成
   - 可能获取到未完成的 diff
   - 建议：添加 `status` 字段检查

4. **大 diff 处理**
   - diff 字符串可能非常大
   - 全部加载到内存
   - 建议：考虑流式处理或分块

### 边界条件

1. **任务不存在**
   - API 返回 404
   - `chatgpt_get_request` 返回错误

2. **无 diff 回合**
   ```rust
   let diff_turn = match task_response.current_diff_task_turn {
       Some(turn) => turn,
       None => anyhow::bail!("No diff turn found"),
   };
   ```

3. **无 PR 输出**
   ```rust
   let output_diff = diff_turn.output_items.iter().find_map(|item| match item {
       OutputItem::Pr(PrOutputItem { output_diff }) => Some(output_diff),
       _ => None,
   });
   ```
   如果只有其他类型输出，返回错误

4. **空 diff**
   - `output_diff.diff` 可能为空字符串
   - Git 应用会成功但无实际变更

### 改进建议

1. **增强反序列化容错**
   ```rust
   #[derive(Debug, Deserialize)]
   pub struct GetTaskResponse {
       #[serde(default)]  // 允许缺失
       pub current_diff_task_turn: Option<AssistantTurn>,
       #[serde(default)]
       pub status: Option<TaskStatus>,  // 添加状态字段
   }
   
   #[derive(Debug, Deserialize)]
   pub enum TaskStatus {
       Pending,
       InProgress,
       Completed,
       Failed,
   }
   ```

2. **支持更多输出类型**
   ```rust
   #[derive(Debug, Deserialize)]
   #[serde(tag = "type")]
   pub enum OutputItem {
       #[serde(rename = "pr")]
       Pr(PrOutputItem),
       #[serde(rename = "file")]
       File(FileOutputItem),  // 文件下载
       #[serde(rename = "message")]
       Message(MessageOutputItem),  // 文本消息
       #[serde(other)]
       Other,
   }
   ```

3. **任务状态验证**
   ```rust
   pub async fn get_task_with_check(
       config: &Config,
       task_id: String,
   ) -> anyhow::Result<GetTaskResponse> {
       let response = get_task(config, task_id).await?;
       if let Some(status) = &response.status {
           if !matches!(status, TaskStatus::Completed) {
               anyhow::bail!("Task not completed yet: {:?}", status);
           }
       }
       Ok(response)
   }
   ```

4. **diff 大小限制**
   ```rust
   const MAX_DIFF_SIZE: usize = 10 * 1024 * 1024;  // 10MB
   
   if output_diff.diff.len() > MAX_DIFF_SIZE {
       anyhow::bail!("Diff too large: {} bytes", output_diff.diff.len());
   }
   ```

5. **提取所有输出**
   ```rust
   impl GetTaskResponse {
       pub fn get_all_diffs(&self) -> Vec<&str> {
           self.current_diff_task_turn
               .as_ref()
               .map(|turn| {
                   turn.output_items
                       .iter()
                       .filter_map(|item| match item {
                           OutputItem::Pr(pr) => Some(pr.output_diff.diff.as_str()),
                           _ => None,
                       })
                       .collect()
               })
               .unwrap_or_default()
       }
   }
   ```

### 测试建议

当前模块缺乏测试，建议添加：
- JSON 反序列化测试
- 边界情况测试（空响应、缺失字段等）
- Mock API 响应测试
