# SkillsConfigWriteParams 研究文档

## 场景与职责

`SkillsConfigWriteParams` 是 Codex App Server Protocol v2 中用于写入技能配置的操作参数结构体。它允许客户端启用或禁用特定的技能（Skills），并指定技能配置文件的路径。

该类型在技能管理功能中使用，支持用户自定义技能的启用状态和配置位置。

## 功能点目的

1. **技能状态控制**：启用或禁用特定技能
2. **配置路径指定**：指定技能配置文件的位置
3. **动态配置**：支持运行时修改技能配置
4. **持久化支持**：配置更改可持久化到文件

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsConfigWriteParams {
    pub path: PathBuf,
    pub enabled: bool,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/SkillsConfigWriteParams.ts)
export type SkillsConfigWriteParams = { 
    path: string, 
    enabled: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `path` | `PathBuf` / `string` | 技能配置文件的路径 |
| `enabled` | `bool` / `boolean` | 是否启用该技能配置 |

### 响应类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsConfigWriteResponse {
    pub effective_enabled: bool,
}
```

```typescript
export type SkillsConfigWriteResponse = { 
    effectiveEnabled: boolean, 
};
```

### 使用上下文

技能配置是 Codex 的扩展机制，允许用户定义自定义工具和指令。`SkillsConfigWriteParams` 用于控制这些技能配置的启用状态。

```rust
// 技能配置写入 API
// method: "skills/config/write"
// params: SkillsConfigWriteParams
// response: SkillsConfigWriteResponse
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3342-3348)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillsConfigWriteParams.ts`

### 相关类型
- `SkillsConfigWriteResponse`: 写入操作的响应
- `SkillMetadata`: 技能元数据
- `SkillSummary`: 技能摘要
- `SkillInterface`: 技能接口定义

### 使用场景
- 客户端调用 `skills/config/write` 方法时传递此参数
- 用于启用或禁用特定的技能配置

## 依赖与外部交互

### 内部依赖
- `std::path::PathBuf`: 路径类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**启用技能配置请求**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "skills/config/write",
    "params": {
        "path": "/home/user/.codex/skills/my-skill.md",
        "enabled": true
    }
}
```

**禁用技能配置请求**:
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "skills/config/write",
    "params": {
        "path": "/home/user/.codex/skills/old-skill.md",
        "enabled": false
    }
}
```

**响应示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "effectiveEnabled": true
    }
}
```

### 技能配置变更通知

当技能配置发生变化时，服务器会发送通知：

```json
{
    "jsonrpc": "2.0",
    "method": "skills/changed",
    "params": {}
}
```

客户端收到此通知后，应重新调用 `skills/list` 获取最新的技能列表。

## 风险、边界与改进建议

### 当前限制
1. **单路径操作**：一次只能操作一个技能配置路径
2. **无批量操作**：不支持批量启用/禁用多个技能
3. **无验证**：不验证路径是否存在或是否为有效的技能配置
4. **无优先级**：不支持设置技能优先级

### 边界情况
1. **不存在的路径**：指定的路径不存在时的处理
2. **无效的技能文件**：文件存在但不是有效的技能配置
3. **重复启用**：重复启用已启用的技能
4. **路径格式**：相对路径 vs 绝对路径的处理

### 改进建议

1. **添加批量操作**：
   ```rust
   pub struct SkillsConfigWriteParams {
       pub changes: Vec<SkillConfigChange>,
   }
   
   pub struct SkillConfigChange {
       pub path: PathBuf,
       pub enabled: bool,
   }
   ```

2. **添加验证**：
   ```rust
   impl SkillsConfigWriteParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证路径存在
           // 验证是有效的技能配置
           // 验证权限
       }
   }
   ```

3. **添加优先级**：
   ```rust
   pub struct SkillsConfigWriteParams {
       pub path: PathBuf,
       pub enabled: bool,
       pub priority: Option<i32>,  // 新增：优先级
   }
   ```

4. **添加元数据**：
   ```rust
   pub struct SkillsConfigWriteParams {
       pub path: PathBuf,
       pub enabled: bool,
       pub metadata: Option<SkillConfigMetadata>,  // 新增：自定义元数据
   }
   ```

5. **添加响应详情**：
   ```rust
   pub struct SkillsConfigWriteResponse {
       pub effective_enabled: bool,
       pub skill_name: Option<String>,  // 新增：技能名称
       pub skill_description: Option<String>,  // 新增：技能描述
       pub affected_tools: Vec<String>,  // 新增：影响的工具列表
   }
   ```

### 兼容性注意
- 使用 `camelCase` 命名确保与 TypeScript 惯例一致
- 路径类型在 Rust 中使用 `PathBuf`，TypeScript 中使用 `string`
- 未来添加字段时应使用 `Option<T>` 确保向后兼容

### 客户端处理建议

```typescript
async function toggleSkill(path: string, enabled: boolean): Promise<void> {
    const response = await sendRequest('skills/config/write', {
        path,
        enabled
    });
    
    if (response.result.effectiveEnabled === enabled) {
        console.log(`Skill ${enabled ? 'enabled' : 'disabled'} successfully`);
    } else {
        console.warn('Skill state mismatch');
    }
    
    // 等待技能变更通知
    await waitForNotification('skills/changed');
    
    // 刷新技能列表
    const skills = await listSkills();
    updateSkillUI(skills);
}
```

### 技能配置示例

```markdown
<!-- /home/user/.codex/skills/web-search.md -->
# Web Search Skill

## Description
Provides web search capabilities to Codex.

## Tools
- web_search: Search the web for information
- open_page: Open a specific URL

## Configuration
enabled: true
priority: 10
```

### 相关 API

| 方法 | 描述 | 参数 | 响应 |
|------|------|------|------|
| `skills/config/write` | 写入技能配置 | `SkillsConfigWriteParams` | `SkillsConfigWriteResponse` |
| `skills/list` | 列出可用技能 | `SkillsListParams` | `SkillsListResponse` |
| `skills/changed` | 技能变更通知（服务器→客户端） | - | - |

### 使用场景总结

1. **启用新技能**：用户安装新技能后启用
2. **禁用技能**：临时禁用不需要的技能
3. **故障排除**：禁用可能导致问题的技能
4. **性能优化**：禁用不常用技能以提高性能
5. **配置管理**：通过 API 管理技能配置状态
