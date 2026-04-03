# AppReview 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppReview` 是 Codex App-Server Protocol v2 中用于描述应用程序审核状态的简单类型。它主要用于：

- **Marketplace 审核流程**：跟踪应用在应用商店中的审核状态
- **合规性检查**：确保应用符合平台政策和安全标准
- **应用发现控制**：根据审核状态控制应用在商店中的可见性
- **开发者反馈**：向开发者展示审核结果和状态

### 1.2 核心职责

- 提供应用的审核状态标识
- 支持应用发布流程的状态跟踪
- 作为 `AppMetadata` 的子组件，构成完整的应用元数据

### 1.3 设计简洁性

该类型设计极为简洁，仅包含一个 `status` 字段，表明：
- 当前审核流程较为简单，可能仅关注"是否通过"
- 详细的审核反馈（如拒绝原因）可能通过其他渠道传递
- 未来可能扩展以支持更复杂的审核工作流

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `status` | `string` | 审核状态标识 |

### 2.2 可能的 Status 值

虽然类型定义为 `string`，但基于常见应用商店模式，可能的值包括：

| 值 | 含义 |
|----|------|
| `"pending"` | 审核中，等待审核结果 |
| `"approved"` | 审核通过，可以发布 |
| `"rejected"` | 审核未通过 |
| `"under_review"` | 正在审核中 |
| `"draft"` | 草稿状态，未提交审核 |

### 2.3 设计意图

1. **简单优先**：单一字段满足当前需求，避免过度设计
2. **扩展性**：使用 `string` 而非枚举，允许未来添加新状态而不破坏兼容性
3. **集成友好**：易于与现有的审核系统集成

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppReview = {
  status: string,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AppReview {
    pub status: String,
}
```

### 3.3 序列化规则

- 使用 `#[serde(rename_all = "camelCase")]` 保持与 TypeScript 的一致性
- `status` 为必填字段，类型为 `String`（非 `Option<String>`）

### 3.4 生成工具

- 生成命令：`just write-app-server-schema`
- 输出路径：`codex-rs/app-server-protocol/schema/typescript/v2/AppReview.ts`

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 1961-1966 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppReview.ts` | 生成的 TypeScript 类型 |

### 4.2 引用关系

```
AppMetadata
  └── review: AppReview | null
```

- `AppReview` 被 `AppMetadata` 类型引用，作为其 `review` 字段的类型

### 4.3 相关类型

| 类型 | 关系 |
|------|------|
| `AppMetadata` | 包含 `review: AppReview \| null` |
| `AppInfo` | 通过 `appMetadata` 间接引用 |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

`AppReview.ts` 无直接导入，是独立的简单类型。

### 5.2 外部协议依赖

- **serde**：序列化/反序列化
- **schemars**：JSON Schema 生成
- **ts-rs**：TypeScript 类型生成

### 5.3 客户端使用示例

```typescript
import type { AppReview } from "./AppReview";
import type { AppMetadata } from "./AppMetadata";
import type { AppInfo } from "./AppInfo";

// 审核状态常量
const ReviewStatus = {
  PENDING: 'pending',
  APPROVED: 'approved',
  REJECTED: 'rejected',
  UNDER_REVIEW: 'under_review',
  DRAFT: 'draft',
} as const;

type ReviewStatusValue = typeof ReviewStatus[keyof typeof ReviewStatus];

// 获取审核状态
function getReviewStatus(app: AppInfo): string | null {
  return app.appMetadata?.review?.status ?? null;
}

// 检查是否已审核通过
function isApproved(app: AppInfo): boolean {
  return getReviewStatus(app) === ReviewStatus.APPROVED;
}

// 检查是否在审核中
function isUnderReview(app: AppInfo): boolean {
  const status = getReviewStatus(app);
  return status === ReviewStatus.PENDING || status === ReviewStatus.UNDER_REVIEW;
}

// 获取审核状态显示文本
function getReviewStatusText(app: AppInfo): string {
  const status = getReviewStatus(app);
  if (!status) return 'Unknown';
  
  const statusMap: Record<string, string> = {
    [ReviewStatus.PENDING]: 'Pending Review',
    [ReviewStatus.APPROVED]: 'Approved',
    [ReviewStatus.REJECTED]: 'Rejected',
    [ReviewStatus.UNDER_REVIEW]: 'Under Review',
    [ReviewStatus.DRAFT]: 'Draft',
  };
  
  return statusMap[status] ?? status;
}

// 根据审核状态决定是否显示应用
function shouldShowInStore(app: AppInfo): boolean {
  // 只显示已审核通过的应用
  return isApproved(app);
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **类型过于宽松** | `status` 为任意字符串，无类型安全 | 客户端定义常量枚举 |
| **信息不足** | 无拒绝原因、审核时间等信息 | 通过其他渠道获取详细信息 |
| **无历史记录** | 单条记录无法追踪审核历史 | 服务端维护审核日志 |

### 6.2 边界情况

1. **未知状态值**：服务端可能返回客户端未定义的状态值
2. **空字符串**：`status` 理论上不应为空，但客户端应做好防护
3. **大小写敏感**：状态值区分大小写，"Approved" 和 "approved" 不同

### 6.3 改进建议

1. **扩展字段**：
   ```typescript
   interface AppReview {
     status: ReviewStatus;
     submittedAt?: number;      // 提交审核时间
     reviewedAt?: number;       // 审核完成时间
     reviewer?: string;         // 审核员
     rejectionReason?: string;  // 拒绝原因
     notes?: string;            // 审核备注
   }
   ```

2. **状态枚举化**：
   ```typescript
   type ReviewStatus = 
     | 'draft'
     | 'submitted'
     | 'pending'
     | 'under_review'
     | 'approved'
     | 'rejected'
     | 'appealed';
   ```

3. **添加审核历史**：
   ```typescript
   interface AppReview {
     current: ReviewEntry;
     history: ReviewEntry[];
   }
   
   interface ReviewEntry {
     status: ReviewStatus;
     timestamp: number;
     actor: string;
     notes?: string;
   }
   ```

4. **支持多区域审核**：
   ```typescript
   interface AppReview {
     global: ReviewEntry;
     byRegion?: {
       [regionCode: string]: ReviewEntry;
     };
   }
   ```

### 6.4 最佳实践

1. **防御性编程**：
   ```typescript
   function normalizeStatus(status: string): string {
     return status.toLowerCase().trim();
   }
   ```

2. **状态机设计**：
   ```typescript
   const validTransitions: Record<string, string[]> = {
     'draft': ['submitted'],
     'submitted': ['pending', 'rejected'],
     'pending': ['under_review', 'approved', 'rejected'],
     'under_review': ['approved', 'rejected'],
     'rejected': ['appealed', 'draft'],
     'appealed': ['under_review', 'rejected'],
   };
   ```

3. **UI 状态映射**：
   ```typescript
   const statusConfig: Record<string, { color: string; icon: string }> = {
     'approved': { color: 'green', icon: 'check-circle' },
     'rejected': { color: 'red', icon: 'x-circle' },
     'pending': { color: 'yellow', icon: 'clock' },
     'under_review': { color: 'blue', icon: 'eye' },
   };
   ```
