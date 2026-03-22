# SkillsListResponse 研究文档

## 场景与职责

`SkillsListResponse` 是 Codex App Server Protocol v2 API 中 `skills/list` 方法的响应类型。该类型封装了技能查询的完整结果，以数组形式返回每个工作目录对应的技能列表和错误信息。

### 使用场景

1. **技能列表展示**：客户端获取技能数据后渲染技能选择界面
2. **技能发现结果**：返回指定工作目录下发现的所有技能及其元数据
3. **错误报告**：汇总技能扫描过程中的所有错误，便于问题诊断
4. **状态同步**：客户端与服务器之间同步技能的启用/禁用状态

## 功能点目的

### 核心功能

- **批量结果返回**：以数组形式返回多个工作目录的技能查询结果
- **结构化数据**：每个条目包含目录路径、技能列表和错误信息
- **完整元数据**：包含技能的完整元数据（名称、描述、路径、作用域、启用状态等）
- **错误隔离**：单个目录的扫描失败不会影响其他目录的结果

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | `SkillsListEntry[]` | 技能列表条目数组，每个条目对应一个查询的工作目录 |

### 嵌套类型 SkillsListEntry

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | `string` | 工作目录路径 |
| `skills` | `SkillMetadata[]` | 在该目录下发现的技能列表 |
| `errors` | `SkillErrorInfo[]` | 扫描过程中发生的错误列表 |

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3088-3093
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListResponse {
    pub data: Vec<SkillsListEntry>,
}
```

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3224-3228
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

### 关键处理流程

1. **请求处理与响应构建**：`CodexMessageProcessor::skills_list()`
   ```rust
   // codex-rs/app-server/src/codex_message_processor.rs:5385-5440
   async fn skills_list(&self, request_id: ConnectionRequestId, params: SkillsListParams) {
       // ... 参数处理和验证 ...
       
       match self.thread_manager.skills_manager()
           .list_skills(cwds, force_reload, extra_roots_by_cwd)
           .await 
       {
           Ok(results) => {
               // 将技能管理器返回的结果转换为响应
               let response = SkillsListResponse {
                   data: results
                       .into_iter()
                       .map(|(cwd, skills, errors)| SkillsListEntry {
                           cwd,
                           skills,
                           errors,
                       })
                       .collect(),
               };
               self.outgoing.send_response(request_id, response).await;
           }
           Err(err) => {
               // 发送错误响应
               let error = JSONRPCErrorError {
                   code: INTERNAL_ERROR_CODE,
                   message: format!("failed to list skills: {err}"),
                   data: None,
               };
               self.outgoing.send_error(request_id, error).await;
           }
       }
   }
   ```

2. **技能发现流程**：`SkillsManager::list_skills()`
   - 扫描标准技能目录（用户级、仓库级、系统级）
   - 解析 `SKILL.md` 和 `SKILL.json` 文件
   - 应用配置中的启用/禁用设置
   - 返回三元组 `(PathBuf, Vec<SkillMetadata>, Vec<SkillErrorInfo>)` 的列表

3. **响应序列化**：
   - Rust 侧使用 `serde` 序列化为 JSON
   - TypeScript 类型通过 `ts-rs` 自动生成
   - JSON Schema 通过 `schemars` 生成

### 生成的 TypeScript 类型

```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!
import type { SkillsListEntry } from "./SkillsListEntry";

export type SkillsListResponse = { data: Array<SkillsListEntry> };
```

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "SkillDependencies": { /* ... */ },
    "SkillErrorInfo": {
      "properties": {
        "message": { "type": "string" },
        "path": { "type": "string" }
      },
      "required": ["message", "path"],
      "type": "object"
    },
    "SkillInterface": { /* ... */ },
    "SkillMetadata": {
      "properties": {
        "dependencies": { /* ... */ },
        "description": { "type": "string" },
        "enabled": { "type": "boolean" },
        "interface": { /* ... */ },
        "name": { "type": "string" },
        "path": { "type": "string" },
        "scope": { "$ref": "#/definitions/SkillScope" },
        "shortDescription": { /* ... */ }
      },
      "required": ["description", "enabled", "name", "path", "scope"],
      "type": "object"
    },
    "SkillScope": {
      "enum": ["user", "repo", "system", "admin"],
      "type": "string"
    },
    "SkillToolDependency": { /* ... */ },
    "SkillsListEntry": {
      "properties": {
        "cwd": { "type": "string" },
        "errors": {
          "items": { "$ref": "#/definitions/SkillErrorInfo" },
          "type": "array"
        },
        "skills": {
          "items": { "$ref": "#/definitions/SkillMetadata" },
          "type": "array"
        }
      },
      "required": ["cwd", "errors", "skills"],
      "type": "object"
    }
  },
  "properties": {
    "data": {
      "items": { "$ref": "#/definitions/SkillsListEntry" },
      "type": "array"
    }
  },
  "required": ["data"],
  "title": "SkillsListResponse",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3088-3093` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:295-298` | 客户端请求路由定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsListResponse.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/SkillsListResponse.json` | JSON Schema 定义 |

### 服务端实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs:5385-5440` | `skills_list` 方法实现 |
| `codex-rs/app-server/src/codex_message_processor.rs:704-707` | 请求路由分发 |

### 核心协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/protocol/src/protocol.rs:3002-3007` | 核心 `SkillsListEntry` 定义 |
| `codex-rs/protocol/src/protocol.rs:2937-2960` | `SkillMetadata` 定义 |
| `codex-rs/protocol/src/protocol.rs:2997-3000` | `SkillErrorInfo` 定义 |

### 测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/skills_list.rs` | 完整集成测试套件 |

## 依赖与外部交互

### 上游依赖

1. **SkillsListEntry**：响应数组的元素类型
2. **SkillMetadata**：技能元数据类型
3. **SkillErrorInfo**：错误信息类型
4. **技能管理器**：`thread_manager.skills_manager()` 提供原始数据

### 下游影响

1. **客户端 UI**：客户端解析响应并渲染技能列表界面
2. **技能过滤**：客户端根据 `enabled` 字段过滤可使用的技能
3. **错误展示**：`errors` 用于向用户显示技能加载问题

### 类型依赖图

```
SkillsListResponse
└── data: Vec<SkillsListEntry>
    ├── cwd: PathBuf
    ├── skills: Vec<SkillMetadata>
    │   ├── name: String
    │   ├── description: String
    │   ├── short_description: Option<String>
    │   ├── interface: Option<SkillInterface>
    │   ├── dependencies: Option<SkillDependencies>
    │   ├── path: PathBuf
    │   ├── scope: SkillScope
    │   └── enabled: bool
    └── errors: Vec<SkillErrorInfo>
        ├── path: PathBuf
        └── message: String
```

## 风险、边界与改进建议

### 潜在风险

1. **响应体过大**：如果工作目录包含大量技能，响应可能变得非常庞大
2. **序列化开销**：复杂的嵌套结构增加了序列化/反序列化开销
3. **内存占用**：服务端需要构建完整的响应结构后才能发送

### 边界情况

1. **空 data 数组**：请求的工作目录都无效或不存在时返回空数组
2. **空 skills 数组**：目录下未发现任何技能
3. **全 errors**：目录扫描完全失败，skills 为空但 errors 有内容
4. **循环引用**：技能依赖中可能出现循环引用（需依赖系统处理）

### 测试覆盖

集成测试验证了以下响应场景：

```rust
// 验证响应包含来自额外根目录的技能
async fn skills_list_includes_skills_from_per_cwd_extra_user_roots() {
    let response: JSONRPCResponse = /* ... */;
    let SkillsListResponse { data } = to_response(response)?;
    assert_eq!(data.len(), 1);
    assert!(data[0].skills.iter().any(|skill| skill.name == "extra-skill"));
}

// 验证缓存行为
async fn skills_list_uses_cached_result_until_force_reload() {
    // 验证 force_reload=false 时返回缓存结果
    // 验证 force_reload=true 时返回新扫描结果
}
```

### 改进建议

1. **添加分页支持**：对于大量技能的场景，考虑添加分页
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub next_cursor: Option<String>,  // 分页游标
       pub total_count: usize,           // 总条目数
   }
   ```

2. **添加响应元数据**：提供扫描统计信息
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub meta: SkillsListMeta,
   }
   
   pub struct SkillsListMeta {
       pub scanned_at: i64,           // 扫描时间戳
       pub cache_hit: bool,           // 是否来自缓存
       pub scan_duration_ms: u64,     // 扫描耗时
   }
   ```

3. **支持增量更新**：添加版本号支持增量同步
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub version: String,           // 响应版本/哈希
   }
   
   // 请求时携带上次版本号
   pub struct SkillsListParams {
       // ... existing fields
       pub last_version: Option<String>,
   }
   ```

4. **压缩大响应**：对于超大响应考虑启用压缩
   ```rust
   // 在协议层添加压缩支持
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub compressed: bool,          // 是否已压缩
   }
   ```

5. **选择性返回字段**：允许客户端指定需要的字段
   ```rust
   pub struct SkillsListParams {
       // ... existing fields
       pub fields: Option<Vec<String>>,  // 指定需要的字段
   }
   ```

6. **扁平化响应选项**：对于简单场景提供扁平化响应格式
   ```rust
   pub struct SkillsListResponse {
       pub data: Vec<SkillsListEntry>,
       pub flat_skills: Option<Vec<SkillMetadata>>,  // 所有技能的扁平列表
   }
   ```
