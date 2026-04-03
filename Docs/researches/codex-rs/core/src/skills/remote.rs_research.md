# remote.rs 深入研究文档

## 场景与职责

`remote.rs` 是 Codex Core 中负责与远程 Skill API 交互的客户端模块。它提供了从远程服务器（ChatGPT 后端）获取和管理技能（Skills）的能力。该模块目前被标记为"未来预留"（future wiring），尚未被任何活跃的产品表面使用，但基础设施已经完备。

### 核心职责
1. **远程技能列表获取**：从 ChatGPT 后端 API 获取可用的远程技能列表
2. **远程技能下载**：将远程技能以 ZIP 格式下载并解压到本地缓存目录
3. **认证管理**：确保只有 ChatGPT 认证用户才能访问远程技能（API Key 认证不支持）
4. **安全解压**：提供安全的 ZIP 解压机制，防止路径遍历攻击

## 功能点目的

### 1. 远程技能范围（RemoteSkillScope）
定义了四种技能可见性范围：
- `WorkspaceShared`：工作区共享的技能
- `AllShared`：所有共享的技能
- `Personal`：个人技能
- `Example`：示例技能

### 2. 产品表面（RemoteSkillProductSurface）
定义了支持远程技能的产品：
- `Chatgpt`：ChatGPT 产品
- `Codex`：Codex CLI
- `Api`：OpenAI API
- `Atlas`：Atlas 平台

### 3. 核心 API 功能

#### `list_remote_skills`
- **目的**：获取远程技能列表
- **端点**：`GET {chatgpt_base_url}/hazelnuts`
- **查询参数**：
  - `product_surface`: 产品表面（如 "codex"）
  - `scope`: 可选的范围过滤
  - `enabled`: 可选的启用状态过滤
- **认证**：需要 ChatGPT OAuth 令牌 + 可选的 `chatgpt-account-id` 头
- **超时**：30 秒

#### `export_remote_skill`
- **目的**：下载指定技能的 ZIP 包
- **端点**：`GET {chatgpt_base_url}/hazelnuts/{skill_id}/export`
- **输出**：解压到 `{CODEX_HOME}/skills/{skill_id}/`
- **安全验证**：验证 ZIP 魔数（magic number）

## 具体技术实现

### 关键数据结构

```rust
// 远程技能摘要（用于列表展示）
pub struct RemoteSkillSummary {
    pub id: String,
    pub name: String,
    pub description: String,
}

// 下载结果
pub struct RemoteSkillDownloadResult {
    pub id: String,
    pub path: PathBuf,  // 解压后的本地路径
}

// API 响应结构（内部）
#[derive(Debug, Deserialize)]
struct RemoteSkillsResponse {
    #[serde(rename = "hazelnuts")]  // API 使用 "hazelnuts" 作为字段名
    skills: Vec<RemoteSkill>,
}
```

### 关键流程

#### 1. 认证验证流程
```rust
fn ensure_chatgpt_auth(auth: Option<&CodexAuth>) -> Result<&CodexAuth>
```
- 检查认证是否存在
- 验证是否为 ChatGPT 认证（非 API Key）
- 返回错误如果认证类型不匹配

#### 2. ZIP 安全解压流程
```rust
fn extract_zip_to_dir(bytes: Vec<u8>, output_dir: &Path, prefix_candidates: &[String]) -> Result<()>
```

安全机制：
- **路径遍历防护**：`safe_join` 函数验证路径组件，拒绝任何非 `Normal` 组件（如 `..` 或根路径）
- **ZIP 炸弹防护**：通过 `spawn_blocking` 在独立线程中执行解压，避免阻塞异步运行时
- **前缀剥离**：`normalize_zip_name` 自动剥离技能 ID 前缀，确保文件解压到正确位置

#### 3. ZIP 格式验证
```rust
fn is_zip_payload(bytes: &[u8]) -> bool {
    bytes.starts_with(b"PK\x03\x04")  // ZIP 本地文件头
        || bytes.starts_with(b"PK\x05\x06")  // ZIP 空存档
        || bytes.starts_with(b"PK\x07\x08")  // ZIP64
}
```

### 网络配置

```rust
const REMOTE_SKILLS_API_TIMEOUT: Duration = Duration::from_secs(30);
```

使用 `build_reqwest_client()` 创建 HTTP 客户端，该客户端在 `default_client.rs` 中定义，支持自定义 CA 证书和其他全局配置。

## 关键代码路径与文件引用

### 文件内关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `list_remote_skills` | 90-146 | 获取远程技能列表 |
| `export_remote_skill` | 148-202 | 下载并解压远程技能 |
| `ensure_chatgpt_auth` | 52-62 | 验证 ChatGPT 认证 |
| `extract_zip_to_dir` | 223-251 | 安全解压 ZIP |
| `safe_join` | 204-215 | 安全路径拼接 |
| `is_zip_payload` | 217-221 | ZIP 格式验证 |
| `normalize_zip_name` | 253-270 | 文件名标准化 |

### 外部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `CodexAuth` | `crate::auth::CodexAuth` | 认证管理 |
| `Config` | `crate::config::Config` | 配置获取（`chatgpt_base_url`, `codex_home`） |
| `build_reqwest_client` | `crate::default_client` | HTTP 客户端构建 |

### 调用关系

```
remote.rs
├── 使用: auth.rs (CodexAuth)
├── 使用: config/mod.rs (Config.chatgpt_base_url, Config.codex_home)
├── 使用: default_client.rs (build_reqwest_client)
└── 被调用: 目前无活跃调用方（预留功能）
```

## 依赖与外部交互

### 1. 认证系统（auth.rs）
- **依赖方法**：`is_chatgpt_auth()`, `get_token()`, `get_account_id()`
- **约束**：仅支持 ChatGPT OAuth，明确拒绝 API Key 认证
- **错误处理**：清晰的错误消息指导用户切换认证方式

### 2. 配置系统（config/mod.rs）
- **使用字段**：
  - `config.chatgpt_base_url`: ChatGPT API 基础 URL（默认 `https://chatgpt.com/backend-api/`）
  - `config.codex_home`: 本地技能缓存根目录

### 3. HTTP 客户端（default_client.rs）
- **使用**：`build_reqwest_client()` 创建配置好的 reqwest 客户端
- **特性**：支持全局 User-Agent 后缀、自定义 CA 证书等

### 4. 外部 API 端点
- **基础 URL**：`{chatgpt_base_url}/hazelnuts`
- **端点**：
  - `GET /hazelnuts` - 列表
  - `GET /hazelnuts/{id}/export` - 下载
- **请求头**：
  - `Authorization: Bearer {token}`
  - `chatgpt-account-id: {account_id}`（可选）

## 风险、边界与改进建议

### 已知风险

1. **未使用的代码**
   - 该模块目前没有被任何活跃功能调用
   - 存在代码腐烂（code rot）风险，API 可能已变更但此处未更新
   - **建议**：添加集成测试或明确的产品使用路径

2. **ZIP 安全风险**
   - 虽然实现了基础的路径遍历防护，但未实现：
     - ZIP 炸弹（压缩比攻击）检测
     - 文件大小限制
     - 文件数量限制
   - **建议**：添加 `zip::read::ZipFile::compressed_size` 和 `size` 检查

3. **错误处理边界**
   - ZIP 解压错误使用 `anyhow::Context`，可能丢失具体错误类型
   - 网络错误直接透传，未做重试逻辑
   - **建议**：添加指数退避重试机制

4. **并发限制**
   - 使用 `spawn_blocking` 解压，但未限制并发解压任务数
   - 大量同时下载可能导致资源耗尽
   - **建议**：添加信号量（Semaphore）控制并发

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| ZIP 包含符号链接 | 被 `safe_join` 拒绝 | ✅ 安全 |
| ZIP 包含绝对路径 | 被 `normalize_zip_name` 处理 | ✅ 安全 |
| 空 ZIP 文件 | 正常完成，无文件输出 | ⚠️ 无警告 |
| 磁盘空间不足 | IO 错误透传 | ⚠️ 可优化错误消息 |
| 网络超时 | 30 秒后返回错误 | ✅ 合理 |
| 认证过期 | 依赖上层刷新令牌 | ⚠️ 可能需本地处理 |

### 改进建议

1. **添加指标和日志**
   ```rust
   // 建议添加
   tracing::info!(skill_id, size_bytes, "downloaded remote skill");
   tracing::info!(skill_count, scope, "listed remote skills");
   ```

2. **缓存机制**
   - 当前每次调用都重新下载
   - 建议添加 ETag 或本地缓存验证

3. **渐进式下载**
   - 大技能包可能耗时较长
   - 考虑添加下载进度回调接口

4. **类型安全增强**
   ```rust
   // 建议：将 SkillId 包装为 Newtype
   pub struct SkillId(String);
   ```

5. **测试覆盖**
   - 当前无单元测试
   - 建议添加 mock server 测试和临时目录测试

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 安全性 | ⭐⭐⭐⭐ | 基础防护完善，可进一步加强 |
| 可读性 | ⭐⭐⭐⭐⭐ | 代码清晰，注释充分 |
| 可测试性 | ⭐⭐⭐ | 缺乏测试，依赖外部服务 |
| 性能 | ⭐⭐⭐⭐ | 使用 spawn_blocking 避免阻塞 |
| 维护性 | ⭐⭐⭐ | 预留代码，存在腐烂风险 |
