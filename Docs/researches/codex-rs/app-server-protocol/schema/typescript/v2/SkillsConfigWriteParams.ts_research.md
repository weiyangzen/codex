# SkillsConfigWriteParams 调研文档

## 场景与职责

`SkillsConfigWriteParams` 是 App-Server Protocol v2 中用于修改 Skill 配置状态的请求参数类型。该类型支持客户端通过 `skills/config/write` RPC 方法启用或禁用特定的 Skill。

**核心使用场景：**
1. **Skill 开关控制**：用户通过 UI 界面启用或禁用某个已安装的 Skill
2. **个性化配置**：根据用户偏好动态调整可用 Skill 集合
3. **权限管理**：管理员可通过禁用特定 Skill 来限制功能访问

**业务价值：**
- 提供细粒度的 Skill 管理能力，用户可按需启用/禁用 Skill
- 支持运行时配置变更，无需重启应用服务器
- 持久化用户偏好到配置文件

## 功能点目的

### 主要功能

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | `string` | 是 | Skill 的绝对路径，通常是 SKILL.md 文件的路径 |
| `enabled` | `boolean` | 是 | 目标启用状态，`true` 为启用，`false` 为禁用 |

### 功能特性

1. **路径定位**：通过 `path` 字段精确标识要配置的 Skill 文件
2. **状态切换**：通过 `enabled` 布尔值控制 Skill 的启用/禁用状态
3. **用户级配置**：写入用户级别的配置，影响当前用户的所有会话

### 使用示例

```json
{
  "method": "skills/config/write",
  "id": 26,
  "params": {
    "path": "/Users/me/.codex/skills/skill-creator/SKILL.md",
    "enabled": false
  }
}
```

## 具体技术实现

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsConfigWriteParams {
    pub path: PathBuf,
    pub enabled: bool,
}
```

**关键实现细节：**

1. **序列化配置**：
   - 使用 `#[serde(rename_all = "camelCase")]` 确保字段名在 JSON 中使用 camelCase 格式
   - TypeScript 生成目标目录为 `v2/`

2. **路径处理**：
   - Rust 中使用 `PathBuf` 类型表示文件路径
   - 自动生成 TypeScript 中映射为 `string` 类型

3. **类型导出**：
   - 通过 `ts_rs::TS` trait 自动生成 TypeScript 类型定义
   - 生成的文件位于 `schema/typescript/v2/SkillsConfigWriteParams.ts`

### 配置持久化机制

1. **写入位置**：用户级配置文件（通常是 `~/.codex/config.toml`）
2. **配置层级**：遵循 Config Layer 优先级体系，用户配置覆盖系统默认值
3. **热重载**：配置变更后会触发 Skill 缓存失效，下次 `skills/list` 调用时重新加载

## 关键代码路径与文件引用

### 协议定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，第 3345-3348 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteParams.ts` | 自动生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/SkillsConfigWriteParams.json` | JSON Schema 定义 |

### 服务实现文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举中注册 `SkillsConfigWrite` 方法（第 339-342 行） |
| `codex-rs/app-server/src/codex_message_processor.rs` | 消息处理器实现 Skill 配置写入逻辑 |

### 相关类型文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `SkillsConfigWriteResponse` 定义（第 3350-3355 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteResponse.ts` | 响应类型 TypeScript 定义 |

### 文档参考

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/README.md` | API 使用文档，第 170 行及第 1143-1150 行示例 |

## 依赖与外部交互

### 内部依赖

```
SkillsConfigWriteParams
├── serde (序列化/反序列化)
├── schemars (JSON Schema 生成)
├── ts_rs (TypeScript 类型生成)
└── std::path::PathBuf (路径处理)
```

### 外部交互

1. **与配置系统交互**：
   - 调用配置管理模块写入用户级配置
   - 触发配置变更通知

2. **与 Skill 管理器交互**：
   - 更新 Skill 的启用状态缓存
   - 影响后续 `skills/list` 返回结果

3. **与通知系统交互**：
   - 配置变更可能触发 `skills/changed` 通知（取决于实现）

### 调用链

```
Client Request
    ↓
JSON-RPC 解析
    ↓
ClientRequest::SkillsConfigWrite 匹配
    ↓
SkillsConfigWriteParams 反序列化
    ↓
配置管理器写入
    ↓
返回 SkillsConfigWriteResponse
```

## 风险、边界与改进建议

### 潜在风险

| 风险点 | 严重程度 | 说明 |
|--------|---------|------|
| 路径验证不足 | 中 | `path` 字段未在协议层验证是否存在或是否为合法的 Skill 路径 |
| 并发写入冲突 | 低 | 多客户端同时修改配置可能导致配置丢失 |
| 权限控制缺失 | 中 | 协议层未限制哪些 Skill 可以被禁用（如系统级 Skill） |

### 边界情况

1. **无效路径**：指向不存在的 Skill 文件时，行为取决于服务端实现（可能静默失败或返回错误）
2. **重复写入**：连续写入相同状态应保证幂等性
3. **配置层级冲突**：如果系统级配置强制启用某 Skill，用户级禁用可能不会生效

### 改进建议

1. **增强验证**：
   ```rust
   // 建议添加路径验证逻辑
   impl SkillsConfigWriteParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证路径是否存在
           // 验证是否为合法的 Skill 目录结构
       }
   }
   ```

2. **添加元数据字段**：
   - 考虑添加 `reason` 字段记录禁用原因
   - 添加 `timestamp` 字段记录配置变更时间

3. **批量操作支持**：
   - 当前仅支持单 Skill 配置，建议增加批量配置接口

4. **权限控制**：
   - 区分用户级 Skill 和系统级 Skill 的可配置性
   - 添加 `configurable` 字段到 SkillMetadata 标识是否可配置

5. **事务支持**：
   - 配置写入应支持原子操作，避免配置文件损坏
   - 添加配置版本控制支持乐观锁

---

**生成时间**: 2026-03-22  
**协议版本**: App-Server Protocol v2  
**源码版本**: 基于 codex-rs 主分支
