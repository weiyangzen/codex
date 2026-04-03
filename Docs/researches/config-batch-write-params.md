# ConfigBatchWriteParams 研究报告

## 1. 场景与职责

### 使用场景
`ConfigBatchWriteParams` 是 app-server-protocol v2 API 中用于**批量写入配置项**的请求参数结构。它允许客户端在一次请求中提交多个配置编辑操作，适用于以下场景：

- **批量配置更新**：用户通过 UI 同时修改多个配置项（如同时设置模型、沙盒模式、审批策略等）
- **配置导入/迁移**：从其他系统导入配置时需要一次性写入多个键值对
- **原子性配置变更**：确保多个相关配置项同时生效，避免部分成功导致的不一致状态
- **配置模板应用**：应用预设的配置模板时批量写入模板中的多个配置项

### 核心职责
- 封装多个配置编辑操作（`ConfigEdit`）
- 支持乐观锁机制（`expectedVersion`）防止并发写入冲突
- 支持指定目标配置文件路径（`filePath`），默认为用户主配置
- 支持写入后热重载配置（`reloadUserConfig`）

---

## 2. 功能点目的

### 2.1 批量编辑能力
通过 `edits` 数组字段，允许单次请求携带多个配置修改，减少网络往返次数，提升用户体验。

### 2.2 乐观并发控制
`expectedVersion` 字段实现乐观锁：
- 客户端读取配置时获取当前版本号
- 写入时携带期望版本号
- 服务端检查版本号是否匹配，不匹配则返回 `ConfigVersionConflict` 错误
- 防止"读-改-写"过程中的并发冲突

### 2.3 灵活的目标文件指定
`filePath` 字段允许指定写入的目标配置文件，默认写入用户主配置（`$CODEX_HOME/config.toml`），支持多配置文件管理场景。

### 2.4 热重载支持
`reloadUserConfig` 布尔字段控制写入后是否自动热重载配置到所有已加载的线程，避免重启应用使配置生效。

---

## 3. 具体技术实现

### 3.1 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ConfigBatchWriteParams {
    pub edits: Vec<ConfigEdit>,
    /// Path to the config file to write; defaults to the user's `config.toml` when omitted.
    #[ts(optional = nullable)]
    pub file_path: Option<String>,
    #[ts(optional = nullable)]
    pub expected_version: Option<String>,
    /// When true, hot-reload the updated user config into all loaded threads after writing.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub reload_user_config: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ConfigEdit {
    pub key_path: String,
    pub value: JsonValue,
    pub merge_strategy: MergeStrategy,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum MergeStrategy {
    Replace,
    Upsert,
}
```

### 3.2 JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ConfigEdit": {
      "properties": {
        "keyPath": { "type": "string" },
        "mergeStrategy": { "$ref": "#/definitions/MergeStrategy" },
        "value": true
      },
      "required": ["keyPath", "mergeStrategy", "value"],
      "type": "object"
    },
    "MergeStrategy": {
      "enum": ["replace", "upsert"],
      "type": "string"
    }
  },
  "properties": {
    "edits": {
      "items": { "$ref": "#/definitions/ConfigEdit" },
      "type": "array"
    },
    "expectedVersion": { "type": ["string", "null"] },
    "filePath": {
      "description": "Path to the config file to write; defaults to the user's `config.toml` when omitted.",
      "type": ["string", "null"]
    },
    "reloadUserConfig": {
      "description": "When true, hot-reload the updated user config into all loaded threads after writing.",
      "type": "boolean"
    }
  },
  "required": ["edits"],
  "title": "ConfigBatchWriteParams",
  "type": "object"
}
```

### 3.3 MergeStrategy 详解

| 策略值 | 行为描述 |
|--------|----------|
| `replace` | 完全替换目标路径的值，无论原值类型如何 |
| `upsert` | 如果目标路径存在且为 Table 类型，新值也是 Table，则合并两个 Table；否则行为同 replace |

**Upsert 合并示例**：
```toml
# 原配置
[tools]
web_search = { enabled = true }

# 写入 edits: [{keyPath: "tools", value: {view_image = true}, strategy: "upsert"}]
# 结果
[tools]
web_search = { enabled = true }
view_image = true
```

### 3.4 服务端处理流程

```rust
// codex-rs/core/src/config/service.rs
pub async fn batch_write(
    &self,
    params: ConfigBatchWriteParams,
) -> Result<ConfigWriteResponse, ConfigServiceError> {
    let edits = params
        .edits
        .into_iter()
        .map(|edit| (edit.key_path, edit.value, edit.merge_strategy))
        .collect();

    self.apply_edits(params.file_path, params.expected_version, edits).await
}
```

处理步骤：
1. 验证目标文件路径是否允许写入（仅允许用户主配置）
2. 检查版本号（乐观锁）
3. 解析每个 edit 的 keyPath（点分路径，如 `"profiles.default.model"`）
4. 根据 mergeStrategy 应用变更
5. 验证最终配置有效性
6. 原子写入文件（使用 `write_atomically`）
7. 返回写入结果，包含被覆盖的元数据信息

---

## 4. 关键代码路径与文件引用

### 4.1 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（第 941-960 行） |
| `codex-rs/app-server-protocol/schema/json/v2/ConfigBatchWriteParams.json` | JSON Schema 定义 |

### 4.2 服务实现
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/config/service.rs` | 配置服务实现，`batch_write` 方法（第 222-234 行） |
| `codex-rs/core/src/config/service.rs` | `apply_edits` 核心方法（第 251-410 行） |
| `codex-rs/core/src/config/edit.rs` | 配置编辑操作定义和持久化 |

### 4.3 API 路由注册
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `client_request_definitions!` 宏中注册 `ConfigBatchWrite => "config/batchWrite"`（第 493-496 行） |

### 4.4 类型导出
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | JSON Schema 生成工具 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖
```
ConfigBatchWriteParams
├── ConfigEdit
│   ├── MergeStrategy (enum)
│   └── JsonValue (serde_json::Value)
├── ConfigWriteResponse (返回类型)
│   ├── WriteStatus (ok / okOverridden)
│   ├── OverriddenMetadata
│   └── AbsolutePathBuf
└── ConfigServiceError (错误类型)
    └── ConfigWriteErrorCode
```

### 5.2 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| 客户端 (TUI/GUI) | JSON-RPC | 通过 `config/batchWrite` 方法调用 |
| 文件系统 | 原子写入 | 使用 `write_atomically` 确保配置写入安全 |
| ConfigLayerStack | 内存操作 | 更新配置层栈并计算有效配置 |
| toml_edit | 库依赖 | 用于 TOML 文档的精确编辑（保留格式、注释） |

### 5.3 响应类型
批量写入返回 `ConfigWriteResponse`，包含：
- `status`: `ok` 或 `okOverridden`（值被高层配置覆盖）
- `version`: 写入后的新版本号
- `file_path`: 实际写入的文件路径
- `overridden_metadata`: 如果被覆盖，包含覆盖层信息和有效值

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 并发写入冲突 | 多客户端同时修改配置可能导致版本冲突 | 使用 `expectedVersion` 乐观锁，冲突时返回错误码 `ConfigVersionConflict` |
| 部分失败 | 批量编辑中某个 edit 失败可能导致部分成功 | 所有 edit 在内存中验证通过后才执行写入，保持原子性 |
| 配置验证失败 | 写入的配置可能无法通过 schema 验证 | 在持久化前调用 `validate_config` 和 `validate_explicit_feature_settings_in_config_toml` |
| 路径遍历攻击 | 恶意 filePath 可能尝试写入非预期文件 | 严格校验路径，仅允许写入用户主配置 |

### 6.2 边界情况

1. **空 edits 数组**：服务端应返回错误或空操作（当前实现会返回错误）
2. **无效 keyPath**：如包含空字符串或非法字符，返回 `ConfigValidationError`
3. **null value**：表示删除该路径的配置项
4. **深层嵌套路径**：自动创建中间 Table 节点
5. **数组索引**：keyPath 支持数字作为数组索引（如 `"tools.0.enabled"`）

### 6.3 改进建议

1. **事务支持**：
   - 当前实现对所有 edits 是原子的，但可以考虑支持跨文件事务
   - 建议：引入两阶段提交机制，支持多配置文件的一致性更新

2. **增量更新优化**：
   - 当前实现会重写整个配置文件
   - 建议：利用 `toml_edit` 的能力实现真正的增量更新，保留更多格式信息

3. **批量大小限制**：
   - 当前无明确的 edits 数量限制
   - 建议：添加合理的上限（如 100 个 edit），防止滥用

4. **更细粒度的错误报告**：
   - 当前批量失败时只返回单个错误
   - 建议：返回每个 edit 的执行状态，方便客户端定位问题

5. **配置变更通知**：
   - 当前 `reloadUserConfig` 是布尔值
   - 建议：支持更细粒度的重载策略，如仅重载特定线程或延迟重载

6. **Schema 版本控制**：
   - 当前配置 schema 演进可能导致兼容性问题
   - 建议：引入配置 schema 版本号，支持向后兼容的迁移
