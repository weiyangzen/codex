# RateLimitWindowSnapshot 研究文档

## 场景与职责

`RateLimitWindowSnapshot` 是 Codex 后端 OpenAPI 模型库中的基础数据结构，用于表示**速率限制时间窗口的快照**。它是配额管理系统的核心组件，主要用于：

1. **窗口使用追踪**：记录特定时间窗口内的配额使用情况
2. **重置时间计算**：提供窗口重置的时间信息
3. **使用百分比展示**：直观显示配额使用进度
4. **限流决策支持**：客户端根据窗口状态决定是否发送请求

典型使用场景：
- 显示 "您在 5 分钟窗口内已使用 42% 的配额"
- 计算距离配额重置还有多长时间
- 在 UI 中绘制配额使用进度条
- 预警即将达到限制

## 功能点目的

### 核心功能

该结构体承载以下关键信息：

| 字段 | 类型 | 用途 |
|------|------|------|
| `used_percent` | `i32` | 已使用配额的百分比（0-100） |
| `limit_window_seconds` | `i32` | 时间窗口的总长度（秒） |
| `reset_after_seconds` | `i32` | 距离窗口重置的剩余秒数 |
| `reset_at` | `i32` | 窗口重置的 Unix 时间戳 |

### 设计特点

1. **双重时间表示**：
   - `reset_after_seconds`：相对时间，便于显示倒计时
   - `reset_at`：绝对时间戳，便于精确计算

2. **整数类型**：
   - 所有字段使用 `i32`，确保跨平台兼容性
   - 百分比使用整数避免浮点精度问题

3. **自包含设计**：
   - 单个结构体包含完整的窗口状态信息
   - 无需额外上下文即可理解和使用

## 具体技术实现

### 数据结构定义

```rust
#[derive(Clone, Default, Debug, PartialEq, Serialize, Deserialize)]
pub struct RateLimitWindowSnapshot {
    #[serde(rename = "used_percent")]
    pub used_percent: i32,
    #[serde(rename = "limit_window_seconds")]
    pub limit_window_seconds: i32,
    #[serde(rename = "reset_after_seconds")]
    pub reset_after_seconds: i32,
    #[serde(rename = "reset_at")]
    pub reset_at: i32,
}
```

### 构造函数

```rust
impl RateLimitWindowSnapshot {
    pub fn new(
        used_percent: i32,
        limit_window_seconds: i32,
        reset_after_seconds: i32,
        reset_at: i32,
    ) -> RateLimitWindowSnapshot {
        RateLimitWindowSnapshot {
            used_percent,
            limit_window_seconds,
            reset_after_seconds,
            reset_at,
        }
    }
}
```

构造函数接受所有字段，适用于已知完整状态的场景。

## 关键代码路径与文件引用

### 定义位置
- **文件**: `codex-rs/codex-backend-openapi-models/src/models/rate_limit_window_snapshot.rs`
- **模块导出**: `codex-rs/codex-backend-openapi-models/src/models/mod.rs`

### 使用方

1. **RateLimitStatusDetails** (`rate_limit_status_details.rs`)
   - 作为 `primary_window` 和 `secondary_window` 字段的类型
   - 嵌套在速率限制详情中

2. **backend-client** (`codex-rs/backend-client/src/client.rs`)
   - 在 `map_rate_limit_window` 中处理
   - 转换为内部的 `RateLimitWindow`

3. **backend-client** (`codex-rs/backend-client/src/types.rs`)
   - 重新导出 `RateLimitWindowSnapshot`

### 转换流程

```rust
// backend-client/src/client.rs
fn map_rate_limit_window(
    window: Option<Option<Box<crate::types::RateLimitWindowSnapshot>>>,
) -> Option<RateLimitWindow> {
    let snapshot = window.flatten().map(|details| *details)?;

    let used_percent = f64::from(snapshot.used_percent);
    let window_minutes = Self::window_minutes_from_seconds(snapshot.limit_window_seconds);
    let resets_at = Some(i64::from(snapshot.reset_at));
    Some(RateLimitWindow {
        used_percent,
        window_minutes,
        resets_at,
    })
}

fn window_minutes_from_seconds(seconds: i32) -> Option<i64> {
    if seconds <= 0 {
        return None;
    }

    let seconds_i64 = i64::from(seconds);
    Some((seconds_i64 + 59) / 60)  // 向上取整
}
```

转换后的 `RateLimitWindow` 是 `codex_protocol::protocol::RateLimitWindow`，用于内部协议通信。

## 依赖与外部交互

### 依赖的 crate

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 |

### API 交互

典型 JSON 响应格式：

```json
{
  "used_percent": 42,
  "limit_window_seconds": 300,
  "reset_after_seconds": 180,
  "reset_at": 1704067500
}
```

### 字段关系

```
RateLimitWindowSnapshot
├── used_percent: 42% (已使用)
├── limit_window_seconds: 300s (5分钟窗口)
├── reset_after_seconds: 180s (3分钟后重置)
└── reset_at: 1704067500 (重置时间戳)

计算关系：
- 窗口开始时间 = reset_at - limit_window_seconds
- 已用时间 = limit_window_seconds - reset_after_seconds
- 使用比例 = used_percent / 100
```

## 风险、边界与改进建议

### 潜在风险

1. **时间同步**：
   - `reset_at` 是服务器时间戳
   - 客户端与服务器时间不同步可能导致显示不准确
   - 建议优先使用 `reset_after_seconds`

2. **整数溢出**：
   - `i32` 在 2038 年后可能溢出（Unix 时间戳）
   - 虽然短期内不会出问题，但应考虑使用 `i64`

3. **数据一致性**：
   - `reset_after_seconds` 和 `reset_at` 应该一致
   - 但网络延迟可能导致轻微差异

### 边界情况

1. **零使用**：`used_percent=0`，窗口刚开始
2. **满使用**：`used_percent=100`，限制已用完
3. **超用**：`used_percent>100`，可能表示突发允许
4. **零窗口**：`limit_window_seconds=0`，无效配置
5. **已重置**：`reset_after_seconds=0`，窗口即将重置
6. **负值**：任何字段为负值都是异常情况

### 改进建议

1. **使用 i64 时间戳**：
   ```rust
   pub struct RateLimitWindowSnapshot {
       pub used_percent: i32,
       pub limit_window_seconds: i64,  // 改为 i64
       pub reset_after_seconds: i64,   // 改为 i64
       pub reset_at: i64,              // 改为 i64
   }
   ```

2. **添加辅助方法**：
   ```rust
   impl RateLimitWindowSnapshot {
       /// 获取窗口开始时间
       pub fn window_start(&self) -> i32 {
           self.reset_at - self.limit_window_seconds
       }
       
       /// 获取已用时间
       pub fn elapsed_seconds(&self) -> i32 {
           self.limit_window_seconds - self.reset_after_seconds
       }
       
       /// 获取剩余配额百分比
       pub fn remaining_percent(&self) -> i32 {
           100 - self.used_percent
       }
       
       /// 检查是否即将重置
       pub fn is_about_to_reset(&self, threshold_seconds: i32) -> bool {
           self.reset_after_seconds <= threshold_seconds
       }
       
       /// 格式化剩余时间为人类可读字符串
       pub fn format_reset_time(&self) -> String {
           let minutes = self.reset_after_seconds / 60;
           let seconds = self.reset_after_seconds % 60;
           if minutes > 0 {
               format!("{}m {}s", minutes, seconds)
           } else {
               format!("{}s", seconds)
           }
       }
       
       /// 获取使用状态
       pub fn usage_status(&self) -> UsageStatus {
           match self.used_percent {
               0..=50 => UsageStatus::Normal,
               51..=80 => UsageStatus::Elevated,
               81..=95 => UsageStatus::Warning,
               96..=100 => UsageStatus::Critical,
               _ => UsageStatus::Exceeded,
           }
       }
   }
   
   #[derive(Debug, Clone, Copy, PartialEq)]
   pub enum UsageStatus {
       Normal,    // 0-50%
       Elevated,  // 51-80%
       Warning,   // 81-95%
       Critical,  // 96-100%
       Exceeded,  // >100%
   }
   ```

3. **添加验证方法**：
   ```rust
   impl RateLimitWindowSnapshot {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.used_percent < 0 {
               return Err(ValidationError::NegativeUsage);
           }
           if self.limit_window_seconds <= 0 {
               return Err(ValidationError::InvalidWindow);
           }
           if self.reset_after_seconds < 0 {
               return Err(ValidationError::NegativeResetTime);
           }
           if self.reset_at <= 0 {
               return Err(ValidationError::InvalidResetTimestamp);
           }
           // 验证一致性
           let expected_reset = self.window_start() + self.limit_window_seconds;
           if expected_reset != self.reset_at {
               return Err(ValidationError::InconsistentData);
           }
           Ok(())
       }
   }
   ```

4. **添加显示方法**：
   ```rust
   impl RateLimitWindowSnapshot {
       /// 生成进度条字符串
       pub fn progress_bar(&self, width: usize) -> String {
           let filled = (self.used_percent as usize * width / 100).min(width);
           let empty = width - filled;
           format!(
               "[{}{}] {}%",
               "█".repeat(filled),
               "░".repeat(empty),
               self.used_percent
           )
       }
       
       /// 生成状态摘要
       pub fn summary(&self) -> String {
           format!(
               "Used {}% of {}m window, resets in {}",
               self.used_percent,
               self.limit_window_seconds / 60,
               self.format_reset_time()
           )
       }
   }
   ```

5. **测试覆盖**：
   - 添加各种使用百分比的测试
   - 测试时间计算逻辑
   - 测试边界情况（零使用、满使用、超用）
   - 测试验证方法

### 相关测试

- `backend-client/src/client.rs` 中的单元测试：
  - `usage_payload_maps_primary_and_additional_rate_limits` - 包含窗口快照的测试
  - 测试用例验证了 `used_percent`、`limit_window_seconds` 等的正确映射

### 相关代码

- `rate_limit_status_details.rs` - 包含 RateLimitWindowSnapshot 的上层结构
- `backend-client/src/client.rs` - 窗口快照处理和转换
- `codex_protocol::protocol::RateLimitWindow` - 内部协议使用的窗口类型
