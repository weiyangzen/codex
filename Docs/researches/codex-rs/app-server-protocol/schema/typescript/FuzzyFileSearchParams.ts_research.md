# FuzzyFileSearchParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`FuzzyFileSearchParams` 是 Codex 应用服务器协议中用于**模糊文件搜索请求**的参数类型。它封装了执行模糊文件搜索所需的所有参数，支持在指定根目录下搜索匹配查询字符串的文件和目录。

**典型使用场景：**
- IDE 风格的快速文件打开（Ctrl+P / Cmd+P）
- 在项目中查找文件
- 实时搜索（用户输入时即时返回结果）
- 取消正在进行的搜索（通过 cancellation token）

**职责：**
- 提供搜索查询字符串
- 指定搜索的根目录列表
- 支持取消正在进行的搜索
- 控制搜索范围和性能

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **灵活搜索**：支持在多个根目录中搜索
2. **实时交互**：支持快速响应用户输入
3. **可取消性**：允许取消长时间运行的搜索
4. **性能控制**：通过合理的参数设计控制搜索开销

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type FuzzyFileSearchParams = { 
  query: string, 
  roots: Array<string>, 
  cancellationToken: string | null, 
};
```

### Rust 定义

```rust
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

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `query` | `string` | 模糊搜索查询字符串 |
| `roots` | `string[]` | 搜索的根目录路径列表 |
| `cancellationToken` | `string \| null` | 可选的取消令牌，用于取消之前的请求 |

### 取消机制

```rust
// if provided, will cancel any previous request that used the same value
pub cancellation_token: Option<String>,
```

取消机制的工作方式：
1. 客户端为每个搜索会话生成唯一的 cancellation token
2. 当用户输入新查询时，使用相同的 token 发送新请求
3. 服务器检测到相同 token 的新请求，取消之前的搜索
4. 这确保只有最新查询的结果被返回

### 使用示例

```typescript
// 初始搜索
const params1: FuzzyFileSearchParams = {
  query: "app",
  roots: ["/home/user/project"],
  cancellationToken: "session-123"
};

// 用户继续输入，取消之前的搜索
const params2: FuzzyFileSearchParams = {
  query: "app-server",
  roots: ["/home/user/project"],
  cancellationToken: "session-123"  // 相同 token，触发取消
};
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/FuzzyFileSearchParams.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 792-800)

### 相关类型
- `FuzzyFileSearchResponse` - 搜索响应类型
- `FuzzyFileSearchResult` - 单个搜索结果
- `FuzzyFileSearchMatchType` - 匹配类型（文件/目录）

### 使用位置

1. **客户端请求**：
   ```rust
   ClientRequest::FuzzyFileSearch {
       params: FuzzyFileSearchParams,
       response: FuzzyFileSearchResponse,
   }
   ```

2. **请求定义**（`common.rs`）：
   ```rust
   client_request_definitions! {
       // ...
       FuzzyFileSearch {
           params: FuzzyFileSearchParams,
           response: FuzzyFileSearchResponse,
       },
       // ...
   }
   ```

### 搜索流程

```
ClientRequest::FuzzyFileSearch
  ↓
codex_file_search crate 执行模糊搜索
  ↓
FuzzyFileSearchResponse (同步返回)
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 app-server-protocol 类型（在 `common.rs` 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 camelCase 序列化
- 属于 **v1 API**（非 experimental）

### 与 codex_file_search 的集成

```rust
// 底层搜索由 codex_file_search crate 执行
// FuzzyFileSearchResult 是 "Superset of [`codex_file_search::FileMatch`]"
```

### 外部交互

1. **客户端 → 服务器**：发送搜索请求
2. **服务器 → 搜索库**：调用 `codex_file_search`
3. **搜索库 → 文件系统**：遍历指定根目录
4. **服务器 → 客户端**：返回 `FuzzyFileSearchResponse`

### 会话搜索（Experimental）

除了单次搜索，还有会话式搜索（experimental）：

```rust
#[experimental("fuzzyFileSearch/sessionStart")]
FuzzyFileSearchSessionStart => "fuzzyFileSearch/sessionStart" {
    params: FuzzyFileSearchSessionStartParams,
    response: FuzzyFileSearchSessionStartResponse,
},
```

会话搜索提供：
- 增量结果更新（通过 notification）
- 更好的大目录搜索体验

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **同步阻塞**：
   - `FuzzyFileSearch` 是同步请求（非 session）
   - 大目录搜索可能阻塞响应
   - 建议使用 session API 处理大目录

2. **空查询处理**：
   - 空字符串 `""` 作为查询的行为未明确
   - 可能返回所有文件或空结果

3. **根目录验证**：
   - 不存在的根目录可能导致错误
   - 需要服务器端验证

4. **性能限制**：
   - 没有内置的结果数量限制
   - 大项目可能返回大量结果

5. **取消机制限制**：
   - 取消是尽力而为（best effort）
   - 已开始的搜索可能无法立即取消

### 改进建议

1. **添加结果限制**：
   ```rust
   pub struct FuzzyFileSearchParams {
       pub query: String,
       pub roots: Vec<String>,
       pub cancellation_token: Option<String>,
       pub limit: Option<usize>,  // 最大结果数
   }
   ```

2. **添加过滤选项**：
   ```rust
   pub struct FuzzyFileSearchParams {
       // ... existing fields
       pub include_pattern: Option<String>,  // glob pattern
       pub exclude_pattern: Option<String>,  // glob pattern
       pub match_types: Option<Vec<FuzzyFileSearchMatchType>>,
   }
   ```

3. **添加排序选项**：
   ```rust
   pub enum SortOrder {
       Score,      // 按匹配分数（默认）
       Name,       // 按文件名
       Path,       // 按路径
       Modified,   // 按修改时间
   }
   ```

4. **异步搜索**：
   - 考虑将所有搜索改为异步（session 模式）
   - 提供更好的进度通知

5. **搜索选项**：
   ```rust
   pub struct SearchOptions {
       pub case_sensitive: bool,
       pub fuzzy_threshold: f32,
       pub max_depth: Option<usize>,
   }
   ```

### 测试建议
- 测试空查询的行为
- 测试大目录的搜索性能
- 验证取消机制的有效性
- 测试不存在的根目录的错误处理
- 测试特殊字符的查询字符串

### 性能考虑
- 使用 session API 处理大目录
- 考虑添加客户端缓存
- 对于频繁搜索，考虑使用文件系统监视（watch）
