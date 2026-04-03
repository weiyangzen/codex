# RateLimitWindow.ts 研究文档

## 场景与职责

`RateLimitWindow.ts` 定义了单个速率限制窗口的数据结构，表示在特定时间窗口内的 API 使用配额状态。这是 `RateLimitSnapshot` 的组成部分，用于细粒度地描述配额使用情况。

## 功能点目的

该类型用于：
1. **配额使用追踪**：显示当前窗口内已使用配额的百分比
2. **窗口周期管理**：定义限制窗口的持续时间
3. **重置时间提示**：告知用户配额何时重置
4. **多级限制支持**：支持主要和次要两个独立的限制窗口

## 具体技术实现

### 数据结构定义

```typescript
export type RateLimitWindow = { 
  usedPercent: number,           // 已使用配额百分比 (0-100)
  windowDurationMins: number | null,  // 窗口持续时间（分钟）
  resetsAt: number | null,       // 配额重置时间（Unix 时间戳，秒级）
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| usedPercent | number | 当前窗口内已使用配额的百分比，范围 0-100 |
| windowDurationMins | number \| null | 限制窗口的持续时间，以分钟为单位 |
| resetsAt | number \| null | 配额重置的 Unix 时间戳（秒级）|

### 服务端解析逻辑

在 `codex-rs/codex-api/src/rate_limits.rs` 中：

```rust
fn parse_rate_limit_window(
    headers: &HeaderMap,
    used_percent_header: &str,
    window_minutes_header: &str,
    resets_at_header: &str,
) -> Option<RateLimitWindow> {
    let used_percent: Option<f64> = parse_header_f64(headers, used_percent_header);
    
    used_percent.and_then(|used_percent| {
        let window_minutes = parse_header_i64(headers, window_minutes_header);
        let resets_at = parse_header_i64(headers, resets_at_header);
        
        // 只有存在有效数据时才返回窗口
        let has_data = used_percent != 0.0
            || window_minutes.is_some_and(|minutes| minutes != 0)
            || resets_at.is_some();
        
        has_data.then_some(RateLimitWindow {
            used_percent,
            window_minutes,
            resets_at,
        })
    })
}
```

### 解析的 HTTP 头部

对于默认 codex 限制：
- `x-codex-primary-used-percent`
- `x-codex-primary-window-minutes`
- `x-codex-primary-reset-at`

对于次要限制：
- `x-codex-secondary-used-percent`
- `x-codex-secondary-window-minutes`
- `x-codex-secondary-reset-at`

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/RateLimitWindow.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs` 中的 `RateLimitWindow`
- 后端模型：`codex-rs/codex-backend-openapi-models/src/models/rate_limit_window_snapshot.rs`

### 服务端实现
- 头部解析：`codex-rs/codex-api/src/rate_limits.rs`
- 类型定义：`codex-rs/codex-api/src/types.rs`

### 客户端消费
- TUI 状态显示：`codex-rs/tui/src/status/rate_limits.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/status/rate_limits.rs`
- 聊天组件：`codex-rs/tui/src/chatwidget/tests.rs`

## 依赖与外部交互

### 上游依赖
- HTTP 响应头：从 Codex 后端 API 获取
- 父类型：作为 `RateLimitSnapshot.primary` 和 `RateLimitSnapshot.secondary` 的组成部分

### 下游消费
- 状态栏 UI：显示配额使用进度条
- 预警系统：当 usedPercent 接近 100% 时触发警告

## 风险、边界与改进建议

### 边界情况
1. **空窗口**：当所有字段都为 null 时，表示该限制窗口未激活
2. **零使用**：usedPercent 为 0 但其他字段有值时，表示窗口已初始化但尚未使用
3. **过期时间**：resetsAt 可能指向过去的时间（如果客户端时钟不同步）

### 潜在风险
1. **浮点比较**：usedPercent 使用 f64，直接比较 100.0 可能有精度问题
2. **时区混淆**：resetsAt 是 Unix 时间戳，但需要确保客户端正确解析为本地时间
3. **窗口重叠**：primary 和 secondary 窗口可能重叠，导致复杂的配额计算

### 改进建议
1. **类型约束**：考虑使用 branded type 限制 usedPercent 范围为 0-100
2. **时间处理**：添加时区信息或使用 ISO 8601 格式替代 Unix 时间戳
3. **默认值**：考虑为 windowDurationMins 提供合理的默认值
4. **验证**：在 TypeScript 层添加运行时验证确保数据完整性
