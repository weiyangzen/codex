# AppListUpdatedNotification 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppListUpdatedNotification` 是 Codex App-Server Protocol v2 中的推送通知类型，用于在应用列表发生变化时实时通知客户端。主要使用场景包括：

- **实时同步**：当服务端应用列表变更时，主动推送给所有连接的客户端
- **配置变更感知**：用户修改 config.toml 中的应用配置后，UI 自动更新
- **应用安装/卸载**：新应用安装或现有应用卸载时的状态同步
- **权限变更**：用户获得或失去某个应用的访问权限时通知
- **元数据更新**：应用信息（名称、描述、Logo 等）更新时推送

### 1.2 核心职责

- 作为服务器到客户端的推送通知载体
- 传递完整的应用列表状态（而非增量更新）
- 确保所有客户端保持应用列表的一致性
- 支持实时 UI 更新，无需客户端轮询

### 1.3 实验性状态

该类型标记为 **EXPERIMENTAL**，表明：
- 通知机制可能在未来版本中优化
- 可能支持增量更新或差异推送
- 推送触发条件可能调整

---

## 2. 功能点目的

### 2.1 字段功能说明

| 字段 | 类型 | 目的 |
|------|------|------|
| `data` | `Array<AppInfo>` | 完整的应用列表数据 |

### 2.2 设计意图

1. **全量推送**：使用完整 `AppInfo` 数组而非增量，简化客户端处理逻辑
2. **状态快照**：客户端可以用 `data` 直接替换本地应用列表，无需合并逻辑
3. **一致性保证**：确保所有客户端看到的应用列表完全一致

### 2.3 推送触发条件

通知可能在以下场景触发：
- 配置文件重新加载
- 应用安装/卸载
- 应用权限变更
- 应用元数据更新
- MCP 服务器状态变更（影响应用可用性）

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppListUpdatedNotification = {
  data: Array<AppInfo>,
};
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - notification emitted when the app list changes.
pub struct AppListUpdatedNotification {
    pub data: Vec<AppInfo>,
}
```

### 3.3 通知协议

在 JSON-RPC 通知中，该类型的使用格式：

```json
{
  "jsonrpc": "2.0",
  "method": "notification/appListUpdated",
  "params": {
    "data": [
      {
        "id": "app-1",
        "name": "My App",
        "description": "...",
        // ... 其他 AppInfo 字段
      }
    ]
  }
}
```

### 3.4 生成工具

- 生成命令：`just write-app-server-schema`
- 输出路径：`codex-rs/app-server-protocol/schema/typescript/v2/AppListUpdatedNotification.ts`

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 2059-2065 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppListUpdatedNotification.ts` | 生成的 TypeScript 类型 |

### 4.2 依赖类型

```
AppListUpdatedNotification
  └── data: AppInfo[]
       ├── branding: AppBranding
       ├── appMetadata: AppMetadata
       └── ...
```

### 4.3 相关 API/通知

| 类型 | 关系 |
|------|------|
| `AppsListResponse` | 相同的数据结构，用于请求-响应模式 |
| `AppInfo` | 通知数据的元素类型 |

### 4.4 服务端实现位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 可能包含通知发送逻辑 |
| `codex-rs/mcp-server/src/outgoing_message.rs` | MCP 服务器消息发送 |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

```typescript
import type { AppInfo } from "./AppInfo";
```

### 5.2 通知机制

该通知通过以下机制发送：
- **WebSocket**：实时双向通信
- **Server-Sent Events (SSE)**：服务器推送事件
- **JSON-RPC 通知**：无响应预期的通知消息

### 5.3 客户端订阅

客户端通常通过以下方式接收通知：
1. 建立与 app-server 的连接
2. 订阅通知频道
3. 处理收到的 `AppListUpdatedNotification`

### 5.4 客户端使用示例

```typescript
import type { AppListUpdatedNotification } from "./AppListUpdatedNotification";
import type { AppInfo } from "./AppInfo";

class AppListManager {
  private apps: AppInfo[] = [];

  // 处理通知
  handleNotification(notification: AppListUpdatedNotification): void {
    // 直接替换本地状态（全量更新）
    this.apps = notification.data;
    
    // 触发 UI 更新
    this.emit('appsUpdated', this.apps);
  }

  // 获取当前应用列表
  getApps(): AppInfo[] {
    return this.apps;
  }

  // 获取可访问且启用的应用
  getAvailableApps(): AppInfo[] {
    return this.apps.filter(app => app.isAccessible && app.isEnabled);
  }
}

// 使用示例
const manager = new AppListManager();

// 从 WebSocket/SSE 接收通知
websocket.onMessage((message) => {
  if (message.method === 'notification/appListUpdated') {
    manager.handleNotification(message.params as AppListUpdatedNotification);
  }
});
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **全量传输开销** | 应用列表大时，每次通知数据量大 | 考虑分页或增量更新 |
| **频繁更新** | 配置频繁变更可能导致通知风暴 | 服务端添加防抖机制 |
| **实验性 API** | 可能变更为增量推送 | 客户端做好兼容性处理 |
| **状态同步延迟** | 网络延迟可能导致客户端状态滞后 | 客户端定期主动拉取作为兜底 |

### 6.2 边界情况

1. **空列表**：`data` 可能为空数组，表示没有可用应用
2. **大量应用**：`data` 数组可能包含数百个应用，需考虑内存和性能
3. **重复通知**：同一变更可能触发多次通知，客户端需幂等处理

### 6.3 改进建议

1. **增量更新支持**：
   ```typescript
   type AppListUpdate = 
     | { type: 'full'; apps: AppInfo[] }
     | { type: 'delta'; added: AppInfo[]; removed: string[]; updated: AppInfo[] };
   ```

2. **添加变更原因**：
   ```typescript
   interface AppListUpdatedNotification {
     data: AppInfo[];
     reason?: 'config_reload' | 'app_installed' | 'app_uninstalled' | 'permission_changed';
     timestamp: number;
   }
   ```

3. **分页支持**：
   ```typescript
   interface AppListUpdatedNotification {
     data: AppInfo[];
     pagination?: {
       total: number;
       cursor: string;
       hasMore: boolean;
     };
   }
   ```

4. **压缩传输**：
   - 对于大型应用列表，考虑使用二进制格式或压缩
   - 只传输变更字段

### 6.4 最佳实践

1. **客户端缓存**：
   - 本地缓存应用列表
   - 使用通知触发刷新，而非完全依赖推送

2. **防抖处理**：
   ```typescript
   import { debounce } from 'lodash';

   const debouncedUpdate = debounce((apps: AppInfo[]) => {
     updateUI(apps);
   }, 100);
   ```

3. **错误恢复**：
   - 通知处理失败时，主动调用 `app/list` 获取最新状态
   - 定期（如每 5 分钟）主动同步一次

### 6.5 监控指标

建议服务端监控以下指标：
- 通知发送频率
- 通知数据大小
- 客户端接收延迟
- 重复通知率
