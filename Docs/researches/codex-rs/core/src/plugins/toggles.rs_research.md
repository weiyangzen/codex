# toggles.rs 研究文档

## 场景与职责

`toggles.rs` 是 Codex 插件系统中负责 **插件启用状态切换** 的模块。它处理配置变更中的插件启用/禁用操作，从配置编辑中提取插件状态变更候选，支持 Config Service 的批量更新操作。

### 核心场景

1. **配置变更解析**：从 TOML/JSON 配置编辑中提取插件启用状态变更
2. **批量状态更新**：支持同时更新多个插件的启用状态
3. **配置同步**：与远程插件状态同步时更新本地配置

---

## 功能点目的

### `collect_plugin_enabled_candidates`

**目的**：从配置编辑操作中提取插件启用状态的变更候选。

**支持的配置路径格式**：

1. **点分路径格式**：
   - `plugins.{plugin_id}.enabled` - 直接设置 enabled 字段
   
2. **表格式**：
   - `plugins.{plugin_id}` - 值为 `{ "enabled": true/false }`
   
3. **批量格式**：
   - `plugins` - 值为整个插件表 `{ "plugin1@test": { "enabled": true }, ... }`

**返回值**：
- `BTreeMap<String, bool>` - 插件 ID 到启用状态的映射
- 使用 `BTreeMap` 保证确定性顺序

---

## 具体技术实现

### 数据结构

```rust
use serde_json::Value as JsonValue;
use std::collections::BTreeMap;

/// 从配置编辑中提取插件启用状态变更
/// 
/// # 参数
/// - `edits`: 配置编辑的键值对迭代器
/// 
/// # 返回
/// 插件 ID 到启用状态的映射，按插件 ID 排序
pub fn collect_plugin_enabled_candidates<'a>(
    edits: impl Iterator<Item = (&'a String, &'a JsonValue)>,
) -> BTreeMap<String, bool>
```

### 核心算法

```rust
pub fn collect_plugin_enabled_candidates<'a>(
    edits: impl Iterator<Item = (&'a String, &'a JsonValue)>,
) -> BTreeMap<String, bool> {
    let mut pending_changes = BTreeMap::new();
    
    for (key_path, value) in edits {
        // 将点分路径分割为段
        let segments = key_path
            .split('.')
            .map(str::to_string)
            .collect::<Vec<String>>();
        
        match segments.as_slice() {
            // 格式: plugins.{plugin_id}.enabled = true/false
            [plugins, plugin_id, enabled]
                if plugins == "plugins" && enabled == "enabled" && value.is_boolean() =>
            {
                if let Some(enabled) = value.as_bool() {
                    pending_changes.insert(plugin_id.clone(), enabled);
                }
            }
            
            // 格式: plugins.{plugin_id} = { "enabled": true/false, ... }
            [plugins, plugin_id] if plugins == "plugins" => {
                if let Some(enabled) = value.get("enabled").and_then(JsonValue::as_bool) {
                    pending_changes.insert(plugin_id.clone(), enabled);
                }
            }
            
            // 格式: plugins = { "plugin1@test": { "enabled": true }, ... }
            [plugins] if plugins == "plugins" => {
                let Some(entries) = value.as_object() else {
                    continue;
                };
                for (plugin_id, plugin_value) in entries {
                    let Some(enabled) = plugin_value.get("enabled").and_then(JsonValue::as_bool)
                    else {
                        continue;
                    };
                    pending_changes.insert(plugin_id.clone(), enabled);
                }
            }
            
            // 其他路径忽略
            _ => {}
        }
    }
    
    pending_changes
}
```

### 冲突处理策略

当同一插件有多个编辑时，**后出现的编辑覆盖之前的**：

```rust
#[test]
fn collect_plugin_enabled_candidates_uses_last_write_for_same_plugin() {
    let candidates = collect_plugin_enabled_candidates(
        [
            (&"plugins.sample@test.enabled".to_string(), &json!(true)),   // 先设置 true
            (&"plugins.sample@test".to_string(), &json!({ "enabled": false })),  // 后设置 false
        ]
        .into_iter(),
    );
    
    // 后出现的值获胜
    assert_eq!(
        candidates,
        BTreeMap::from([("sample@test".to_string(), false)])
    );
}
```

---

## 关键代码路径与文件引用

### 调用关系

```
toggles.rs
    └── 被调用:
        └── Config Service (通过 pub use)
            └── 处理配置变更时提取插件状态
```

### 模块导出

```rust
// mod.rs 中导出
pub use toggles::collect_plugin_enabled_candidates;
```

### 使用场景

```rust
// 在配置服务中的典型使用
use codex_core::plugins::collect_plugin_enabled_candidates;

fn handle_config_update(edits: &[(String, JsonValue)]) {
    let plugin_changes = collect_plugin_enabled_candidates(edits.iter().map(|(k, v)| (k, v)));
    
    for (plugin_id, enabled) in plugin_changes {
        if enabled {
            // 启用插件
            plugin_manager.enable_plugin(&plugin_id);
        } else {
            // 禁用插件
            plugin_manager.disable_plugin(&plugin_id);
        }
    }
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `serde_json::Value` | JSON/TOML 值的表示 |
| `std::collections::BTreeMap` | 有序的键值存储 |

### 无其他模块依赖

该模块是插件系统的底层工具模块，不依赖其他插件子模块，仅依赖标准库和 serde。

---

## 风险、边界与改进建议

### 当前风险

1. **路径硬编码**：
   - `"plugins"` 字符串硬编码
   - 如果配置结构变更，需要同步修改

2. **无验证**：
   - 不验证插件 ID 格式
   - 不验证启用值是否为布尔

3. **忽略其他字段**：
   - 仅提取 `enabled` 字段
   - 插件的其他配置变更被忽略

### 边界情况

| 情况 | 当前行为 | 评估 |
|------|----------|------|
| 空编辑列表 | 返回空 BTreeMap | ✅ 合理 |
| 非布尔 enabled 值 | 忽略该条目 | ⚠️ 可能应该报错 |
| 无效插件 ID | 原样插入 | ⚠️ 可能应该验证 |
| 嵌套插件表 | 仅处理第一层 | ✅ 符合设计 |
| 路径前缀匹配 | 精确匹配 "plugins" | ✅ 合理 |

### 改进建议

1. **添加常量定义**：
   ```rust
   const PLUGINS_CONFIG_KEY: &str = "plugins";
   const ENABLED_CONFIG_KEY: &str = "enabled";
   ```

2. **添加插件 ID 验证**：
   ```rust
   use super::store::PluginId;
   
   fn validate_plugin_id(id: &str) -> bool {
       PluginId::parse(id).is_ok()
   }
   ```

3. **返回更详细的信息**：
   ```rust
   pub struct PluginToggleChange {
       pub plugin_id: String,
       pub enabled: bool,
       pub source: ToggleSource,  // Direct / Table / Batch
   }
   
   pub enum ToggleSource {
       Direct,  // plugins.{id}.enabled
       Table,   // plugins.{id}
       Batch,   // plugins
   }
   ```

4. **支持其他字段**：
   ```rust
   pub struct PluginConfigChange {
       pub plugin_id: String,
       pub enabled: Option<bool>,
       pub other_fields: HashMap<String, JsonValue>,
   }
   
   pub fn collect_plugin_config_changes<'a>(
       edits: impl Iterator<Item = (&'a String, &'a JsonValue)>,
   ) -> Vec<PluginConfigChange>
   ```

5. **添加错误处理**：
   ```rust
   pub enum ToggleParseError {
       InvalidPluginId(String),
       InvalidEnabledValue(String),
       InvalidStructure(String),
   }
   
   pub fn collect_plugin_enabled_candidates<'a>(
       edits: impl Iterator<Item = (&'a String, &'a JsonValue)>,
   ) -> Result<BTreeMap<String, bool>, Vec<ToggleParseError>>
   ```

### 测试覆盖

当前测试在模块内部的 `mod tests` 中：

| 测试 | 覆盖 |
|------|------|
| `collect_plugin_enabled_candidates_tracks_direct_and_table_writes` | ✅ 多种格式 |
| `collect_plugin_enabled_candidates_uses_last_write_for_same_plugin` | ✅ 冲突处理 |

**建议添加**：

1. 空输入测试
2. 无效格式测试
3. 大量插件性能测试
4. 嵌套表测试

### 性能考虑

当前实现时间复杂度为 O(n)，其中 n 是编辑数量：

```rust
// 每个编辑只处理一次
for (key_path, value) in edits {
    // O(1) 操作
}
```

对于大量编辑（如批量同步），性能可接受。

### 与远程同步的集成

```rust
// 在 manager.rs 的 sync_plugins_from_remote 中
let config_edits = vec![
    ConfigEdit::SetPath {
        segments: vec!["plugins".to_string(), plugin_key, "enabled".to_string()],
        value: value(true),
    }
];

// 这些编辑后续会被 Config Service 处理
// Config Service 使用 collect_plugin_enabled_candidates 提取变更
```
