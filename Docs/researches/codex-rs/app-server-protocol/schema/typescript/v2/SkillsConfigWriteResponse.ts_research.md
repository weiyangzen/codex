# SkillsConfigWriteResponse 调研文档

## 场景与职责

`SkillsConfigWriteResponse` 是 App-Server Protocol v2 中 `skills/config/write` RPC 方法的响应类型。该类型向客户端返回 Skill 配置写入操作后的实际生效状态。

**核心使用场景：**
1. **配置确认**：确认用户的启用/禁用操作已生效
2. **状态同步**：客户端获取服务端实际生效的配置状态
3. **冲突检测**：当配置被其他层（如系统配置）覆盖时，告知客户端实际状态

**业务价值：**
- 提供配置操作的原子性反馈
- 支持配置层级的透明化，客户端可了解配置是否被覆盖
- 确保客户端 UI 状态与服务端实际状态一致

## 功能点目的

### 主要功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `effectiveEnabled` | `boolean` | 实际生效的启用状态 |

### 功能特性

1. **生效状态反馈**：返回配置写入后实际生效的状态，而非仅仅是请求的状态
2. **配置层级透明**：当用户配置被更高优先级的配置层覆盖时，`effectiveEnabled` 会反映实际状态
3. **幂等性支持**：重复调用后返回相同的 `effectiveEnabled` 值

### 使用示例

```json
// 请求
{
  "method": "skills/config/write",
  "id": 26,
  "params": {
    "path": "/Users/me/.codex/skills/skill-creator/SKILL.md",
    "enabled": false
  }
}

// 响应
{
  "id": 26,
  "result": {
    "effectiveEnabled": false
  }
}
```

### 配置覆盖场景示例

```json
// 用户请求禁用某 Skill
{
  "method": "skills/config/write",
  "id": 27,
  "params": {
    "path": "/system/skills/required-skill/SKILL.md",
    "enabled": false
  }
}

// 但系统配置强制启用，返回实际生效状态
{
  "id": 27,
  "result": {
    "effectiveEnabled": true
  }
}
```

## 具体技术实现

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsConfigWriteResponse {
    pub effective_enabled: bool,
}
```

**关键实现细节：**

1. **命名规范**：
   - Rust 字段使用 `snake_case`：`effective_enabled`
   - JSON 和 TypeScript 使用 `camelCase`：`effectiveEnabled`
   - 通过 `#[serde(rename_all = "camelCase")]` 自动转换

2. **类型导出**：
   - 使用 `ts_rs::TS` trait 自动生成 TypeScript 类型
   - 导出路径为 `v2/` 目录

3. **响应构造**：
   - 服务端根据配置写入后的实际状态构造响应
   - 考虑配置层级优先级后确定 `effective_enabled` 值

### 配置层级处理逻辑

```
配置层级优先级（从高到低）：
1. SessionFlags (30) - 会话级覆盖
2. LegacyManagedConfigTomlFromFile (40) - 遗留托管配置
3. LegacyManagedConfigTomlFromMdm (50) - MDM 托管配置
4. User (20) - 用户配置（SkillsConfigWrite 写入的层级）
5. System (10) - 系统配置
6. Mdm (0) - MDM 配置
```

当高优先级配置层设置了 Skill 状态时，`effective_enabled` 会反映高优先级层的值。

## 关键代码路径与文件引用

### 协议定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，第 3350-3355 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteResponse.ts` | 自动生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/SkillsConfigWriteResponse.json` | JSON Schema 定义 |

### 服务实现文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举中注册响应类型（第 339-342 行） |
| `codex-rs/app-server/src/codex_message_processor.rs` | 响应构造逻辑 |

### 相关类型文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `SkillsConfigWriteParams` 定义（第 3345-3348 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteParams.ts` | 请求参数 TypeScript 定义 |

### 配置相关文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `ConfigLayerSource` 枚举定义配置层级（第 444-496 行） |

## 依赖与外部交互

### 内部依赖

```
SkillsConfigWriteResponse
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
└── ConfigLayerSource (配置层级定义)
```

### 外部交互

1. **与配置管理器交互**：
   - 读取各配置层级的 Skill 启用状态
   - 计算优先级后的生效状态

2. **与响应构造器交互**：
   - 将计算后的状态封装为响应对象
   - 序列化为 JSON-RPC 响应格式

### 响应构造流程

```
配置写入操作
    ↓
读取各层级配置状态
    ↓
按优先级计算 effective_enabled
    ↓
构造 SkillsConfigWriteResponse
    ↓
序列化为 JSON 响应
    ↓
返回客户端
```

## 风险、边界与改进建议

### 潜在风险

| 风险点 | 严重程度 | 说明 |
|--------|---------|------|
| 状态不一致 | 中 | 客户端仅通过响应了解状态，后续配置变更可能导致状态不同步 |
| 缺乏覆盖原因 | 低 | 当配置被覆盖时，客户端无法得知被哪一层覆盖 |
| 竞态条件 | 低 | 并发配置修改可能导致返回的状态已过时 |

### 边界情况

1. **配置写入失败**：当前设计未明确区分成功写入和写入失败场景
2. **部分生效**：某些配置层写入成功，某些失败时的状态不明确
3. **空响应**：如果 Skill 不存在，响应行为未定义

### 改进建议

1. **增强响应信息**：
   ```rust
   pub struct SkillsConfigWriteResponse {
       pub effective_enabled: bool,
       pub write_status: WriteStatus,  // 新增：写入状态
       pub overridden_by: Option<ConfigLayerSource>,  // 新增：被哪层覆盖
       pub message: Option<String>,  // 新增：人类可读的状态说明
   }
   ```

2. **添加状态枚举**：
   ```rust
   pub enum WriteStatus {
       Ok,              // 写入成功且生效
       OkOverridden,    // 写入成功但被覆盖
       Failed,          // 写入失败
       NotFound,        // Skill 不存在
       PermissionDenied, // 无权限修改
   }
   ```

3. **版本控制支持**：
   - 添加 `config_version` 字段支持乐观锁
   - 配置冲突时返回错误而非静默覆盖

4. **批量响应支持**：
   - 如果未来支持批量配置写入，响应应支持返回多个 Skill 的状态

5. **事件通知**：
   - 配置变更后触发 `skills/changed` 通知
   - 支持订阅特定 Skill 的配置变更

---

**生成时间**: 2026-03-22  
**协议版本**: App-Server Protocol v2  
**源码版本**: 基于 codex-rs 主分支
