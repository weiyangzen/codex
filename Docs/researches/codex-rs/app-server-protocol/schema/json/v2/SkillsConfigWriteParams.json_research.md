# SkillsConfigWriteParams.json 研究文档

## 场景与职责

`SkillsConfigWriteParams.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述技能配置写入请求的参数结构。

该参数结构用于 `skills/config/write` 方法，支持启用或禁用特定路径的技能，使客户端能够动态管理技能的启用状态。

## 功能点目的

1. **技能状态管理**: 启用或禁用特定技能
2. **路径指定**: 通过 `path` 字段指定要配置的技能路径
3. **动态配置**: 支持运行时修改技能配置，无需重启
4. **用户控制**: 允许用户自定义哪些技能可用

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "enabled": {
      "type": "boolean"
    },
    "path": {
      "type": "string"
    }
  },
  "required": ["enabled", "path"],
  "title": "SkillsConfigWriteParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `enabled` | boolean | 是 | 要设置的启用状态，`true` 为启用，`false` 为禁用 |
| `path` | string | 是 | 技能的路径标识符 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3345
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsConfigWriteParams {
    pub enabled: bool,
    pub path: String,
}
```

### 方法映射

```rust
// common.rs 行 339-342
SkillsConfigWrite => "skills/config/write" {
    params: v2::SkillsConfigWriteParams,
    response: v2::SkillsConfigWriteResponse,
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3345-3351)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/SkillsConfigWriteParams.json`
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 339-342)

### 调用方
- **客户端**: 通过 `skills/config/write` 方法修改技能配置
- **UI 层**: 技能管理界面的启用/禁用开关

### 响应结构
- **对应响应**: `SkillsConfigWriteResponse` - 包含实际生效的启用状态

## 依赖与外部交互

### 上游依赖
1. **技能系统**: 管理技能的加载和启用状态
2. **配置持久化**: 保存技能配置到配置文件
3. **权限系统**: 验证用户是否有权限修改技能配置

### 下游使用方
1. **技能管理器**: 应用新的技能配置
2. **通知系统**: 发送技能变更通知
3. **线程系统**: 更新已加载线程的技能可用性

### 配置流程
1. 客户端调用 `skills/config/write` 并传入 `SkillsConfigWriteParams`
2. 服务器验证技能路径有效性和用户权限
3. 更新技能配置状态
4. 持久化配置到存储
5. 返回 `SkillsConfigWriteResponse`，包含实际生效的状态

## 风险、边界与改进建议

### 潜在风险
1. **权限提升**: 恶意技能被启用可能带来安全风险
2. **配置冲突**: 多个客户端同时修改配置可能导致冲突
3. **依赖破坏**: 禁用某个技能可能影响依赖它的其他功能
4. **路径注入**: 需要验证 `path` 字段不包含恶意路径

### 边界情况
1. **无效路径**: 指定的技能路径不存在
2. **无权限**: 用户没有权限修改指定技能
3. **系统技能**: 尝试禁用系统关键技能
4. **重复调用**: 重复设置相同状态

### 改进建议

#### 1. 添加作用域指定
```json
{
  "path": "/path/to/skill",
  "enabled": true,
  "scope": "user" // 或 "repo", "session"
}
```

#### 2. 添加批量操作
```json
{
  "skills": [
    { "path": "/skill1", "enabled": true },
    { "path": "/skill2", "enabled": false }
  ]
}
```

#### 3. 添加条件启用
```json
{
  "path": "/path/to/skill",
  "enabled": true,
  "conditions": {
    "cwd": "/project/path",
    "fileExists": ".skill-enabled"
  }
}
```

#### 4. 添加元数据
```json
{
  "path": "/path/to/skill",
  "enabled": true,
  "metadata": {
    "enabledBy": "user",
    "enabledAt": 1712345678,
    "reason": "Needed for project X"
  }
}
```

#### 5. 支持模式匹配
```json
{
  "pathPattern": "/skills/*",
  "enabled": false
}
```

### 最佳实践
1. **权限验证**: 始终验证用户有权限修改指定技能
2. **路径验证**: 验证 `path` 指向有效的技能
3. **变更通知**: 修改后发送 `SkillsChangedNotification` 通知
4. **原子操作**: 确保配置更新是原子性的

### 相关 API
- `SkillsConfigWriteResponse` - 配置写入响应
- `SkillsListParams` / `SkillsListResponse` - 技能列表查询
- `SkillsChangedNotification` - 技能变更通知
- `SkillMetadata` - 技能元数据

### 技能作用域

技能可以有不同的作用域，影响配置的影响范围：

1. **user**: 用户级别，影响所有项目
2. **repo**: 仓库级别，仅影响特定代码仓库
3. **system**: 系统级别，由管理员配置
4. **admin**: 管理员级别，优先级最高

当前 `SkillsConfigWriteParams` 设计为简单路径+状态模式，未来可能需要扩展以支持更复杂的配置场景。
