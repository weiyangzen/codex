# ThreadMetadataUpdateParams.json 研究文档

## 场景与职责

`ThreadMetadataUpdateParams.json` 是 Codex App Server Protocol v2 API 的 JSON Schema 定义文件，定义了 `thread/metadata/update` 方法的请求参数结构。该参数用于更新线程的元数据，目前主要用于修改 Git 相关信息（分支、commit、origin URL）。

**主要使用场景：**
- 用户切换分支后更新线程关联的 Git 分支
- 修正或补充线程的 Git 元数据
- 清除不再相关的 Git 信息
- 从外部工具（如 VSCode）同步 Git 状态

## 功能点目的

### 1. 请求结构 (ThreadMetadataUpdateParams)

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 要更新的线程 ID |
| `gitInfo` | ThreadMetadataGitInfoUpdateParams? | 否 | Git 元数据更新参数 |

### 2. Git 信息更新参数 (ThreadMetadataGitInfoUpdateParams)

| 字段 | 类型 | 说明 |
|------|------|------|
| `sha` | string? / null? | 提交哈希，omit=不变，null=清除，string=设置 |
| `branch` | string? / null? | 分支名，omit=不变，null=清除，string=设置 |
| `originUrl` | string? / null? | 远程 URL，omit=不变，null=清除，string=设置 |

### 3. 更新语义

每个字段支持三种操作：
- **Omit（省略）**: 保持原值不变
- **Set to null**: 清除该字段
- **Set to string**: 更新为该值

这种设计使用 `Option<Option<String>>` 类型（双 Option）实现：
- `None` - 字段被省略，不修改
- `Some(None)` - 显式设置为 null，清除字段
- `Some(Some(value))` - 设置为指定值

## 具体技术实现

### 关键流程

1. **请求处理流程** (`codex_message_processor.rs:2366-2510`):
```rust
async fn thread_metadata_update(
    &self,
    request_id: ConnectionRequestId,
    params: ThreadMetadataUpdateParams,
) {
    let ThreadMetadataUpdateParams { thread_id, git_info } = params;
    
    // 1. 解析线程 ID
    let thread_uuid = match ThreadId::from_string(&thread_id) {
        Ok(id) => id,
        Err(err) => {
            self.send_invalid_request_error(request_id, format!("invalid thread id: {err}"))
                .await;
            return;
        }
    };
    
    // 2. 验证至少有一个字段需要更新
    let Some(git_info_params) = git_info else {
        self.send_invalid_request_error(
            request_id,
            "gitInfo must include at least one field".to_string(),
        )
        .await;
        return;
    };
    
    if git_info_params.sha.is_none() 
        && git_info_params.branch.is_none() 
        && git_info_params.origin_url.is_none() {
        self.send_invalid_request_error(
            request_id,
            "gitInfo must include at least one field".to_string(),
        )
        .await;
        return;
    }
    
    // 3. 获取 State DB 上下文
    let loaded_thread = self.thread_manager.get_thread(thread_uuid).await.ok();
    let mut state_db_ctx = loaded_thread.as_ref().and_then(|t| t.state_db());
    if state_db_ctx.is_none() {
        state_db_ctx = get_state_db(&self.config).await;
    }
    
    // 4. 确保线程元数据行存在（修复功能）
    if let Err(error) = self
        .ensure_thread_metadata_row_exists(thread_uuid, &state_db_ctx, loaded_thread.as_ref())
        .await
    {
        self.outgoing.send_error(request_id, error).await;
        return;
    }
    
    // 5. 验证并处理字段值
    let git_sha = match git_info_params.sha {
        Some(Some(sha)) => {
            let sha = sha.trim().to_string();
            if sha.is_empty() {
                self.send_invalid_request_error(
                    request_id,
                    "gitInfo.sha must not be empty".to_string(),
                )
                .await;
                return;
            }
            Some(Some(sha))
        }
        Some(None) => Some(None),
        None => None,
    };
    // ... 类似处理 branch 和 origin_url
    
    // 6. 更新数据库
    match state_db_ctx
        .update_thread_git_info(thread_uuid, git_sha, git_branch, git_origin_url)
        .await
    {
        Ok(_) => {
            // 7. 构造响应（返回更新后的线程）
            let thread = self.build_thread_response(thread_uuid).await;
            let response = ThreadMetadataUpdateResponse { thread };
            self.outgoing.send_response(request_id, response).await;
        }
        Err(err) => {
            self.send_internal_error(request_id, format!("failed to update metadata: {err}"))
                .await;
        }
    }
}
```

2. **修复功能** (`ensure_thread_metadata_row_exists`):
   - 如果 SQLite 中不存在该线程的记录，自动创建
   - 从 rollout 文件读取元数据
   - 支持已加载、已存储和已归档的线程

### 数据结构

**Rust 结构定义** (`app-server-protocol/src/protocol/v2.rs:2802-2848`):
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadMetadataUpdateParams {
    pub thread_id: String,
    #[ts(optional = nullable)]
    pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadMetadataGitInfoUpdateParams {
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        serialize_with = "super::serde_helpers::serialize_double_option",
        deserialize_with = "super::serde_helpers::deserialize_double_option"
    )]
    #[ts(optional = nullable, type = "string | null")]
    pub sha: Option<Option<String>>,
    
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        serialize_with = "super::serde_helpers::serialize_double_option",
        deserialize_with = "super::serde_helpers::deserialize_double_option"
    )]
    #[ts(optional = nullable, type = "string | null")]
    pub branch: Option<Option<String>>,
    
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        serialize_with = "super::serde_helpers::serialize_double_option",
        deserialize_with = "super::serde_helpers::deserialize_double_option"
    )]
    #[ts(optional = nullable, type = "string | null")]
    pub origin_url: Option<Option<String>>,
}
```

### 序列化辅助函数

双 Option 类型的序列化/反序列化 (`serde_helpers.rs`):

```rust
pub fn serialize_double_option<S>(
    value: &Option<Option<String>>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    match value {
        None => serializer.serialize_none(),      // 字段被省略
        Some(None) => serializer.serialize_none(), // 显式 null
        Some(Some(v)) => serializer.serialize_some(v), // 有值
    }
}

pub fn deserialize_double_option<'de, D>(
    deserializer: D,
) -> Result<Option<Option<String>>, D::Error>
where
    D: Deserializer<'de>,
{
    // 处理: 省略 -> None, null -> Some(None), string -> Some(Some(string))
}
```

## 关键代码路径与文件引用

### 核心实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2802-2812` | ThreadMetadataUpdateParams 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2814-2848` | ThreadMetadataGitInfoUpdateParams 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:258-261` | ClientRequest 枚举中注册 thread/metadata/update 方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:2366-2510` | thread_metadata_update 方法实现 |

### 测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs` | 完整的功能测试套件 |
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs:36-124` | 更新 Git 分支测试 |
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs:126-170` | 空更新拒绝测试 |
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs:172-223` | 修复缺失 SQLite 行测试 |
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs:225-303` | 修复已加载线程测试 |
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs:305-366` | 修复归档线程测试 |
| `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs:368-428` | 清除 Git 字段测试 |

### 生成的 Schema 和类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadMetadataUpdateParams.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadMetadataUpdateParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadMetadataGitInfoUpdateParams.ts` | GitInfo 子类型定义 |

## 依赖与外部交互

### 上游依赖

1. **State DB** (`codex_state::StateRuntime`):
   - `update_thread_git_info()` 方法执行实际更新
   - SQLite 数据库存储元数据

2. **ThreadManager** (`codex_core::ThreadManager`):
   - 获取已加载线程的 State DB 上下文
   - 检查线程是否存在

3. **Serde 辅助函数**:
   - 双 Option 类型的序列化/反序列化
   - 处理 "omit/null/value" 三种状态

### 下游消费

1. **VSCode 扩展**: 同步 Git 状态
2. **CLI 客户端**: `thread metadata update` 命令
3. **TUI 客户端**: 线程信息编辑

### 相关响应

- `ThreadMetadataUpdateResponse` - 包含更新后的 `Thread` 对象
- `thread/read` - 可验证更新结果

## 风险、边界与改进建议

### 已知风险

1. **State DB 依赖**:
   - 如果 SQLite 不可用，更新失败
   - 需要确保 State DB 初始化完成

2. **线程不存在**:
   - 如果线程既未加载也未存储，更新失败
   - 但支持自动修复（从 rollout 重建元数据）

3. **并发更新**:
   - 多个客户端同时更新可能产生竞态条件
   - 当前实现无乐观锁

### 边界情况

1. **空更新拒绝**:
   - 如果 `gitInfo` 为 null 或所有字段为 None，返回错误
   - 错误消息: "gitInfo must include at least one field"

2. **空字符串验证**:
   - 非空字符串会被 trim 处理
   - 空字符串（或仅空白字符）会被拒绝

3. **自动修复**:
   - 如果 SQLite 中缺少线程记录，自动从 rollout 文件重建
   - 支持已加载、已存储和已归档的线程

4. **字段独立性**:
   - 每个字段独立更新
   - 可以只更新 branch 而不影响 sha

### 改进建议

1. **乐观锁**:
   - 添加 `expectedVersion` 参数
   - 防止并发更新冲突

2. **更多元数据字段**:
   - 支持更新线程名称（目前通过 `thread/name/set`）
   - 支持自定义标签/标记

3. **批量更新**:
   - 支持一次更新多个线程
   - 减少多次往返

4. **审计日志**:
   - 记录元数据变更历史
   - 支持回滚

5. **验证增强**:
   - 验证 Git SHA 格式
   - 验证分支名合法性
   - 验证 origin URL 格式

6. **通知机制**:
   - 元数据更新后发送通知
   - 其他客户端可实时同步

7. **Schema 扩展**:
   - 预留扩展字段（如 `customMetadata`）
   - 支持应用特定的元数据
