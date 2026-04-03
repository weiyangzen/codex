# ReviewStartParams 研究文档

## 1. 场景与职责

`ReviewStartParams` 是 Codex app-server-protocol v2 协议中的代码审查启动参数类型，用于发起 AI 代码审查请求。该类型封装了启动代码审查所需的全部参数，包括目标线程、审查目标和交付模式。

### 使用场景
- **代码审查启动**：用户通过客户端发起代码审查请求
- **CI/CD 集成**：自动化流程中触发代码审查
- **批量审查**：对多个代码变更进行系统性审查

## 2. 功能点目的

该类型的核心目的是：
1. **标准化审查请求**：统一代码审查请求的参数结构
2. **灵活的目标指定**：支持多种审查目标（未提交变更、分支对比、特定提交等）
3. **交付模式控制**：允许选择审查结果的展示方式

### 与相关类型的关系
- `ReviewStartResponse`：审查启动后的响应类型
- `ReviewTarget`：审查目标的具体定义
- `ReviewDelivery`：审查结果的交付模式

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
import type { ReviewDelivery } from "./ReviewDelivery";
import type { ReviewTarget } from "./ReviewTarget";

export type ReviewStartParams = { 
  threadId: string, 
  target: ReviewTarget, 
  /**
   * Where to run the review: inline (default) on the current thread or
   * detached on a new thread (returned in `reviewThreadId`).
   */
  delivery?: ReviewDelivery | null, 
};
```

### 字段说明
| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 是 | 发起审查的线程 ID |
| `target` | `ReviewTarget` | 是 | 审查目标（未提交变更、分支、提交等） |
| `delivery` | `ReviewDelivery \| null` | 否 | 审查结果交付模式，默认为 `inline` |

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,

    /// Where to run the review: inline (default) on the current thread or
    /// detached on a new thread (returned in `reviewThreadId`).
    #[serde(default)]
    #[ts(optional = nullable)]
    pub delivery: Option<ReviewDelivery>,
}
```

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3881-3893)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`

### RPC 方法注册
- **文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`
- 对应方法：`review/start`

### 使用位置

#### 消息处理器
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs`
  - 处理 `review/start` 请求
  - 解析 `ReviewStartParams` 并执行相应逻辑

#### 测试
- **文件**: `codex-rs/app-server/tests/suite/v2/review.rs`
  - 多个测试用例构造 `ReviewStartParams`

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/ClientRequest.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/v2/ReviewStartParams.json`

## 5. 依赖与外部交互

### 导入依赖
| 类型 | 来源 | 说明 |
|------|------|------|
| `ReviewDelivery` | `./ReviewDelivery` | 审查结果交付模式 |
| `ReviewTarget` | `./ReviewTarget` | 审查目标定义 |

### 被依赖类型
- `ClientRequest` - 作为 `review/start` 方法的参数类型

### 响应类型
- `ReviewStartResponse` - 审查启动后的响应

## 6. 风险、边界与改进建议

### 潜在风险
1. **目标验证**：`target` 的有效性需要在服务端验证
2. **权限检查**：需要确保用户对指定线程和代码有审查权限
3. **并发控制**：同一目标的多次审查可能需要去重或排队

### 边界情况
- **无效线程 ID**：需要返回清晰的错误信息
- **空目标**：`ReviewTarget` 的验证逻辑
- **仓库状态**：目标分支/提交可能不存在

### 改进建议
1. **添加超时参数**：
   ```typescript
   timeout?: number;  // 审查超时时间（秒）
   ```

2. **添加优先级**：
   ```typescript
   priority?: "low" | "normal" | "high";
   ```

3. **添加回调配置**：
   ```typescript
   callbackUrl?: string;  // 审查完成后的回调地址
   ```

4. **验证增强**：
   - 在类型层面添加更多约束
   - 服务端添加全面的参数验证

5. **文档完善**：
   - 添加更多使用示例
   - 说明不同 `ReviewTarget` 变体的使用场景

### 使用示例
```typescript
// 审查未提交变更
const params: ReviewStartParams = {
  threadId: "thread-123",
  target: { type: "uncommittedChanges" },
  delivery: "inline"
};

// 审查分支对比
const params: ReviewStartParams = {
  threadId: "thread-123",
  target: { type: "baseBranch", branch: "main" },
  delivery: "detached"
};

// 审查特定提交
const params: ReviewStartParams = {
  threadId: "thread-123",
  target: { type: "commit", sha: "abc123", title: "Fix bug" },
  delivery: "inline"
};
```

### 相关类型关系
```
review/start (ClientRequest)
├── params: ReviewStartParams  <-- 本类型
│   ├── threadId: string
│   ├── target: ReviewTarget
│   └── delivery?: ReviewDelivery | null
│
└── result: ReviewStartResponse
    ├── turn: Turn
    └── reviewThreadId: string
```
