# AccountRateLimitsUpdatedNotification.ts 研究文档

## 1. 场景与职责

`AccountRateLimitsUpdatedNotification` 是服务器向客户端推送的**实时通知类型**，用于在账户的速率限制状态发生变化时及时通知客户端更新。

### 使用场景
- **配额消耗**: 当用户进行 API 调用消耗配额后，服务器推送更新后的限制信息
- **配额重置**: 当速率限制窗口重置时（如每小时/每日），通知客户端配额已恢复
- **套餐变更**: 当用户升级/降级套餐导致配额变化时推送更新
- **多设备同步**: 确保用户在不同设备上看到一致的配额状态

### 职责
- 实时同步账户的速率限制状态
- 提供完整的配额快照（`RateLimitSnapshot`）
- 支持客户端 UI 实时更新配额显示

---

## 2. 功能点目的

### 2.1 实时配额同步

```typescript
export type AccountRateLimitsUpdatedNotification = { 
  rateLimits: RateLimitSnapshot,  // 完整的速率限制快照
};
```

### 2.2 设计意图

1. **推送模式**: 服务器主动推送，避免客户端频繁轮询
2. **完整快照**: 传递完整的 `RateLimitSnapshot`，而非增量更新，简化客户端逻辑
3. **实时性**: 在配额变化的关键节点立即通知，确保用户感知

### 2.3 触发时机

| 场景 | 触发时机 |
|------|----------|
| API 调用后 | 每次调用后重新计算并推送 |
| 窗口重置 | 速率限制窗口过期时 |
| 套餐变更 | 用户升级/降级套餐后 |
| 登录完成 | 用户登录成功后推送初始状态 |

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AccountRateLimitsUpdatedNotification {
  rateLimits: RateLimitSnapshot;  // 速率限制快照
}
```

### 3.2 依赖类型: RateLimitSnapshot

```typescript
// RateLimitSnapshot.ts
export type RateLimitSnapshot = { 
  limitId: string | null,        // 限制标识符
  limitName: string | null,      // 人类可读的限制名称
  primary: RateLimitWindow | null,    // 主限制窗口
  secondary: RateLimitWindow | null,  // 次要限制窗口
  credits: CreditsSnapshot | null,    // 积分信息
  planType: PlanType | null,     // 当前套餐类型
};
```

### 3.3 RateLimitWindow

```typescript
// RateLimitWindow.ts
export type RateLimitWindow = { 
  used: number,      // 已使用量
  limit: number,     // 限制总量
  remaining: number, // 剩余量
  resetsAt: number,  // 重置时间戳（Unix 秒）
};
```

### 3.4 Rust 源类型

```rust
// common.rs 中注册通知
server_notification_definitions! {
    // ...
    AccountRateLimitsUpdated => "account/rateLimits/updated" (v2::AccountRateLimitsUpdatedNotification),
}

// v2.rs 中定义结构体
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AccountRateLimitsUpdatedNotification {
    pub rate_limits: RateLimitSnapshot,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 通知注册（约第 909 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AccountRateLimitsUpdatedNotification.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/RateLimitSnapshot.ts` | 依赖类型 |

### 4.2 类型依赖图

```
AccountRateLimitsUpdatedNotification.ts
  └── RateLimitSnapshot.ts
       ├── PlanType.ts (../PlanType)
       ├── CreditsSnapshot.ts
       └── RateLimitWindow.ts
```

### 4.3 关联方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `account/rateLimits/read` | Client → Server | 主动查询当前速率限制 |
| `account/rateLimits/updated` | Server → Client | 速率限制更新通知（本类型） |

### 4.4 使用位置

- 客户端配额显示组件
- 用量预警提示
- 升级套餐的引导入口

---

## 5. 依赖与外部交互

### 5.1 类型依赖

```typescript
import type { RateLimitSnapshot } from "./RateLimitSnapshot";
```

### 5.2 外部系统交互

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Client App    │◄────│   App-Server    │◄────│  Rate Limit     │
│  (Quota Display)│     │  (Notification) │     │  Service        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         ▲                                               │
         │                                               │
         └───────────────────────────────────────────────┘
                    (API 调用触发配额更新)
```

### 5.3 序列化示例

```json
{
  "method": "account/rateLimits/updated",
  "params": {
    "rateLimits": {
      "limitId": "codex",
      "limitName": "Codex Requests",
      "primary": {
        "used": 45,
        "limit": 100,
        "remaining": 55,
        "resetsAt": 1704067200
      },
      "secondary": null,
      "credits": null,
      "planType": "plus"
    }
  }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 通知风暴 | 高频 API 调用可能导致大量通知 | 实现防抖/节流机制 |
| 状态不一致 | 网络延迟导致客户端显示过期数据 | 客户端定期主动查询作为兜底 |
| 时区问题 | `resetsAt` 是 Unix 时间戳，需正确解析 | 客户端使用标准时间库处理 |
| 多限制维度 | 复杂的套餐可能有多个限制维度 | 确保 `limitId` 唯一标识 |

### 6.2 边界情况

1. **无限制套餐**: `limit` 可能为 `null` 或极大值，表示无限制
2. **限制用尽**: `remaining` 为 0 时，客户端应阻止新请求
3. **窗口即将重置**: `resetsAt` 接近当前时间时的 UI 提示
4. **降级场景**: 用户降级套餐后配额立即减少的处理

### 6.3 改进建议

1. **增量更新**: 对于高频场景，考虑支持增量更新减少数据量
   ```typescript
   export type AccountRateLimitsUpdatedNotification = 
     | { type: "full"; rateLimits: RateLimitSnapshot }
     | { type: "delta"; usedDelta: number; remaining: number };
   ```

2. **预警阈值**: 添加预警信息
   ```typescript
   export type AccountRateLimitsUpdatedNotification = { 
     rateLimits: RateLimitSnapshot;
     warnings?: Array<{
       type: "low_quota" | "near_reset";
       message: string;
     }>;
   };
   ```

3. **批量限制**: 支持多维度限制（请求数、Token 数、并发数）
   ```typescript
   export type AccountRateLimitsUpdatedNotification = { 
     rateLimits: Record<string, RateLimitSnapshot>;  // 按 limitId 索引
   };
   ```

4. **历史趋势**: 可选包含历史使用趋势
   ```typescript
   history?: {
     hourly: number[];
     daily: number[];
   };
   ```

### 6.4 测试建议

- 通知触发的时机验证
- 速率限制窗口边界的处理
- 多限制维度的显示
- 网络延迟下的状态一致性
- 套餐变更后的即时更新
