# analytics_client_tests.rs 深度研究文档

## 场景与职责

`analytics_client_tests.rs` 是 `analytics_client.rs` 的配套单元测试模块，负责验证遥测客户端的核心功能逻辑。测试采用纯单元测试风格，不依赖外部网络或复杂的基础设施。

### 测试覆盖范围
1. **路径标准化逻辑** - 验证技能 ID 生成的路径处理
2. **事件序列化格式** - 确保上报 JSON 结构符合预期
3. **去重机制** - 验证 AppUsed 和 PluginUsed 的去重逻辑

---

## 功能点目的

### 测试分类

| 测试函数 | 测试目标 | 技术方法 |
|---------|---------|---------|
| `normalize_path_for_skill_id_repo_scoped_uses_relative_path` | Repo-scoped 技能路径标准化 | 断言相对路径结果 |
| `normalize_path_for_skill_id_user_scoped_uses_absolute_path` | User-scoped 技能路径标准化 | 断言绝对路径结果 |
| `normalize_path_for_skill_id_admin_scoped_uses_absolute_path` | Admin-scoped 技能路径标准化 | 断言绝对路径结果 |
| `normalize_path_for_skill_id_repo_root_not_in_skill_path_uses_absolute_path` | 异常路径处理 | 回退到绝对路径 |
| `app_mentioned_event_serializes_expected_shape` | AppMentioned 事件 JSON 结构 | serde_json::to_value |
| `app_used_event_serializes_expected_shape` | AppUsed 事件 JSON 结构 | serde_json::to_value |
| `app_used_dedupe_is_keyed_by_turn_and_connector` | AppUsed 去重键逻辑 | 直接操作队列结构 |
| `plugin_used_event_serializes_expected_shape` | PluginUsed 事件 JSON 结构 | serde_json::to_value |
| `plugin_management_event_serializes_expected_shape` | Plugin 管理事件 JSON 结构 | serde_json::to_value |
| `plugin_used_dedupe_is_keyed_by_turn_and_plugin` | PluginUsed 去重键逻辑 | 直接操作队列结构 |

---

## 具体技术实现

### 路径标准化测试

```rust
#[test]
fn normalize_path_for_skill_id_repo_scoped_uses_relative_path() {
    let repo_root = PathBuf::from("/repo/root");
    let skill_path = PathBuf::from("/repo/root/.codex/skills/doc/SKILL.md");

    let path = normalize_path_for_skill_id(
        Some("https://example.com/repo.git"),
        Some(repo_root.as_path()),
        skill_path.as_path(),
    );

    assert_eq!(path, ".codex/skills/doc/SKILL.md");
}
```

**测试技巧**：使用 `expected_absolute_path()` 辅助函数处理平台差异（Windows vs Unix 路径分隔符）

### 事件序列化测试

```rust
#[test]
fn app_mentioned_event_serializes_expected_shape() {
    let tracking = TrackEventsContext {
        model_slug: "gpt-5".to_string(),
        thread_id: "thread-1".to_string(),
        turn_id: "turn-1".to_string(),
    };
    let event = TrackEventRequest::AppMentioned(CodexAppMentionedEventRequest {
        event_type: "codex_app_mentioned",
        event_params: codex_app_metadata(&tracking, app_invocation),
    });

    let payload = serde_json::to_value(&event).expect("serialize");
    
    // 使用 json! 宏进行精确匹配
    assert_eq!(payload, json!({
        "event_type": "codex_app_mentioned",
        "event_params": {
            "connector_id": "calendar",
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "app_name": "Calendar",
            "product_client_id": crate::default_client::originator().value,
            "invoke_type": "explicit",
            "model_slug": "gpt-5"
        }
    }));
}
```

### 去重逻辑测试

```rust
#[test]
fn app_used_dedupe_is_keyed_by_turn_and_connector() {
    // 构造最小化的队列结构
    let (sender, _receiver) = mpsc::channel(1);
    let queue = AnalyticsEventsQueue {
        sender,
        app_used_emitted_keys: Arc::new(Mutex::new(HashSet::new())),
        plugin_used_emitted_keys: Arc::new(Mutex::new(HashSet::new())),
    };

    let turn_1 = TrackEventsContext { turn_id: "turn-1".to_string(), ... };
    let turn_2 = TrackEventsContext { turn_id: "turn-2".to_string(), ... };

    // 验证同一 turn + connector 只通过一次
    assert_eq!(queue.should_enqueue_app_used(&turn_1, &app), true);
    assert_eq!(queue.should_enqueue_app_used(&turn_1, &app), false);  // 重复
    assert_eq!(queue.should_enqueue_app_used(&turn_2, &app), true);   // 不同 turn
}
```

### 测试辅助函数

```rust
fn expected_absolute_path(path: &PathBuf) -> String {
    std::fs::canonicalize(path)
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .replace('\\', "/")
}

fn sample_plugin_metadata() -> PluginTelemetryMetadata {
    PluginTelemetryMetadata {
        plugin_id: PluginId::parse("sample@test").expect("valid plugin id"),
        capability_summary: Some(PluginCapabilitySummary {
            config_name: "sample@test".to_string(),
            display_name: "sample".to_string(),
            description: None,
            has_skills: true,
            mcp_server_names: vec!["mcp-1".to_string(), "mcp-2".to_string()],
            app_connector_ids: vec![
                AppConnectorId("calendar".to_string()),
                AppConnectorId("drive".to_string()),
            ],
        }),
    }
}
```

---

## 关键代码路径与文件引用

### 测试模块结构
```
#[cfg(test)]
#[path = "analytics_client_tests.rs"]
mod tests;
```

### 依赖项
```rust
use super::*;  // 导入被测模块的所有内容
use crate::plugins::{AppConnectorId, PluginCapabilitySummary, PluginId, PluginTelemetryMetadata};
use pretty_assertions::assert_eq;  // 更好的 diff 输出
use serde_json::json;
```

### 被测函数
- `normalize_path_for_skill_id()` - 路径标准化
- `codex_app_metadata()` - App 元数据构建
- `codex_plugin_metadata()` - Plugin 元数据构建
- `codex_plugin_used_metadata()` - Plugin 使用元数据构建
- `AnalyticsEventsQueue::should_enqueue_app_used()` - App 去重检查
- `AnalyticsEventsQueue::should_enqueue_plugin_used()` - Plugin 去重检查

---

## 依赖与外部交互

### 测试隔离策略
- 使用 `tempfile::tempdir()` 创建临时目录（在 apply_patch 测试中）
- 使用 `mpsc::channel(1)` 创建虚拟通道，避免启动真实后台任务
- 使用 `Arc::new(Mutex::new(HashSet::new()))` 创建独立的去重集合

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `pretty_assertions` | 测试失败时提供彩色 diff |
| `serde_json::json!` | 构造期望的 JSON 结构 |
| `tokio::sync::mpsc` | 创建虚拟消息通道 |

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺失测试：队列满行为**
   - 未测试 `try_send()` 失败时的警告日志
   - 未测试队列容量边界

2. **缺失测试：网络交互**
   - 未使用 `wiremock` 测试 HTTP 上报
   - 未测试超时、重试、错误处理路径

3. **缺失测试：认证检查**
   - 未测试 `is_chatgpt_auth()` 返回 false 时的行为
   - 未测试 token 获取失败时的行为

4. **缺失测试：Git 信息获取**
   - 路径标准化测试使用了 mock 路径
   - 未测试真实的 Git 仓库场景

### 改进建议

1. **增加集成测试**
   ```rust
   #[tokio::test]
   async fn test_event_upload_to_mock_server() {
       let server = MockServer::start().await;
       // 配置 mock 响应
       // 验证请求格式
   }
   ```

2. **使用 insta 进行快照测试**
   ```rust
   #[test]
   fn app_event_snapshot() {
       let event = create_sample_event();
       insta::assert_json_snapshot!(event);
   }
   ```

3. **增加并发测试**
   ```rust
   #[tokio::test]
   async fn concurrent_dedupe_test() {
       // 验证多线程环境下的去正确性
   }
   ```

4. **测试文档化**
   - 为每个测试添加更详细的注释说明测试意图
   - 使用 Given-When-Then 格式组织测试代码
