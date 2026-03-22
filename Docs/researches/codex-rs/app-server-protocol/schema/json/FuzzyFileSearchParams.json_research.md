# FuzzyFileSearchParams.json 研究文档

## 场景与职责

`FuzzyFileSearchParams` 是 Codex App-Server 协议中用于**模糊文件搜索**的参数结构。客户端通过此结构向服务器发送文件搜索请求，支持基于模糊匹配的实时文件查找。

该类型属于 **Client → Server** 的请求流，对应 JSON-RPC 方法为 `fuzzyFileSearch`。

### 使用场景

1. **快速文件定位**：用户通过模糊名称快速查找项目中的文件
2. **实时搜索**：支持增量搜索，随着用户输入更新结果
3. **多根目录搜索**：支持在多个项目根目录中同时搜索

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `query` | string | ✅ | 搜索查询字符串 |
| `roots` | string[] | ✅ | 搜索的根目录列表 |
| `cancellationToken` | string \| null | ❌ | 取消令牌，用于取消之前的请求 |

### 字段设计意图

- **`cancellationToken`**：当提供此字段时，服务器会取消任何使用相同令牌的先前请求。这对于实现实时搜索（用户每输入一个字符就发送新请求）非常有用。

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
pub struct FuzzyFileSearchParams {
    pub query: String,
    pub roots: Vec<String>,
    // if provided, will cancel any previous request that used the same value
    pub cancellation_token: Option<String>,
}
```

### ClientRequest 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
client_request_definitions! {
    FuzzyFileSearch {
        params: FuzzyFileSearchParams,
        response: FuzzyFileSearchResponse,
    },
}
```

### 响应类型

```rust
pub struct FuzzyFileSearchResponse {
    pub files: Vec<FuzzyFileSearchResult>,
}

pub struct FuzzyFileSearchResult {
    pub root: String,
    pub path: String,
    pub match_type: FuzzyFileSearchMatchType,  // File | Directory
    pub file_name: String,
    pub score: u32,
    pub indices: Option<Vec<u32>>,  // 匹配字符的索引位置
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 主类型定义（行 795-800） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 注册（行 522-525） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 服务器处理搜索请求 |

---

## 依赖与外部交互

### 依赖类型

无外部 crate 依赖，仅使用标准库类型。

### 相关实验性 API

```rust
// 实验性会话管理 API
#[experimental("fuzzyFileSearch/sessionStart")]
FuzzyFileSearchSessionStart => "fuzzyFileSearch/sessionStart" {
    params: FuzzyFileSearchSessionStartParams,
    response: FuzzyFileSearchSessionStartResponse,
},
#[experimental("fuzzyFileSearch/sessionUpdate")]
FuzzyFileSearchSessionUpdate => "fuzzyFileSearch/sessionUpdate" {
    params: FuzzyFileSearchSessionUpdateParams,
    response: FuzzyFileSearchSessionUpdateResponse,
},
#[experimental("fuzzyFileSearch/sessionStop")]
FuzzyFileSearchSessionStop => "fuzzyFileSearch/sessionStop" {
    params: FuzzyFileSearchSessionStopParams,
    response: FuzzyFileSearchSessionStopResponse,
},
```

---

## 风险、边界与改进建议

### 已知风险

1. **性能问题**：大型项目的模糊搜索可能导致性能问题，特别是在没有会话管理的情况下

2. **取消竞争**：`cancellationToken` 机制依赖服务器实现，存在竞争条件风险（新请求到达时旧请求仍在处理）

### 边界情况

1. **空查询**：`query` 为空字符串时的行为未定义
2. **无效根目录**：`roots` 包含不存在或不可访问的目录
3. **大量结果**：搜索结果过多时的分页或截断策略

### 改进建议

1. **添加限制参数**：添加 `limit` 字段控制返回结果数量：
   ```rust
   pub struct FuzzyFileSearchParams {
       pub query: String,
       pub roots: Vec<String>,
       pub cancellation_token: Option<String>,
       pub limit: Option<u32>,  // 新增
   }
   ```

2. **添加过滤选项**：支持按文件类型过滤：
   ```rust
   pub struct FuzzyFileSearchParams {
       // ...
       pub include_patterns: Option<Vec<String>>,  // glob 模式
       pub exclude_patterns: Option<Vec<String>>,  // glob 模式
   }
   ```

3. **会话管理稳定化**：将实验性的会话管理 API（`sessionStart`/`sessionUpdate`/`sessionStop`）提升为稳定 API，以更好地支持大型项目的实时搜索

4. **搜索选项**：添加模糊匹配选项：
   ```rust
   pub struct FuzzySearchOptions {
       pub case_sensitive: bool,
       pub match_algorithm: MatchAlgorithm,  // Fuzzy, Exact, Prefix, etc.
   }
   ```
