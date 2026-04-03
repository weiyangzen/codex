# SkillDependencies 技术调研文档

## 场景与职责

`SkillDependencies` 定义了 Skill（技能）所依赖的外部资源集合，是 Skill 系统的依赖管理核心组件。它描述了运行一个 Skill 所需的外部工具和服务的声明式配置。

### 主要应用场景

1. **Skill 加载验证**：在加载 Skill 时验证所有声明的依赖是否可用
2. **MCP 工具集成**：声明 Skill 依赖的 MCP（Model Context Protocol）工具
3. **依赖冲突检测**：识别多个 Skill 之间的依赖冲突或版本不兼容
4. **运行时准备**：在 Skill 执行前确保所有依赖工具已正确配置
5. **安全审计**：审查 Skill 所需的权限和外部访问能力

### Skill 依赖类型

当前主要支持工具类依赖（`SkillToolDependency`），未来可能扩展：
- **工具依赖**: 依赖特定的 MCP 工具或外部命令
- **环境变量依赖**: 依赖特定的环境变量设置（见 `env_var_dependencies.rs`）
- **文件系统依赖**: 依赖特定的文件或目录存在
- **网络依赖**: 依赖特定的网络端点或服务

## 功能点目的

### 核心功能
- **依赖声明**：允许 Skill 作者显式声明运行所需的外部资源
- **工具链管理**：管理 Skill 所需的 MCP 工具集合
- **版本控制**：支持工具版本约束（通过 `value` 字段）

### 设计意图
- 实现 Skill 的自描述性，降低部署和运维复杂度
- 支持依赖的提前验证，避免运行时失败
- 为 Skill 市场提供依赖分析能力，显示 Skill 的"依赖图谱"

## 具体技术实现

### TypeScript 类型定义
```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!
import type { SkillToolDependency } from "./SkillToolDependency";

export type SkillDependencies = { 
  tools: Array<SkillToolDependency> 
};
```

### Rust 源码定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}
```

### Core 协议定义
```rust
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS, PartialEq, Eq)]
pub struct SkillDependencies {
    pub tools: Vec<SkillToolDependency>,
}
```

### 字段说明
| 字段名 | 类型 | 说明 |
|--------|------|------|
| `tools` | `Vec<SkillToolDependency>` | Skill 依赖的工具列表 |

### SkillToolDependency 结构
```rust
pub struct SkillToolDependency {
    #[serde(rename = "type")]
    #[ts(rename = "type")]
    pub r#type: String,      // 工具类型，如 "mcp"
    pub value: String,       // 工具标识，如工具名称
    pub description: Option<String>,  // 工具描述
    pub transport: Option<String>,    // 传输协议
    pub command: Option<String>,      // 启动命令
    pub url: Option<String>,          // 服务端点 URL
}
```

## 关键代码路径与文件引用

### 类型定义位置
- **Rust v2 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 3184-3189 行)
- **Rust Core 定义**: `codex-rs/protocol/src/protocol.rs` (第 2971-2974 行)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/SkillDependencies.ts`

### 类型转换实现
- **Core → v2 转换**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 3427-3434 行)
  ```rust
  impl From<CoreSkillDependencies> for SkillDependencies {
      fn from(value: CoreSkillDependencies) -> Self {
          Self {
              tools: value
                  .tools
                  .into_iter()
                  .map(SkillToolDependency::from)
                  .collect(),
          }
      }
  }
  ```

### 使用位置

1. **SkillMetadata**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 3148-3164 行)
   ```rust
   pub struct SkillMetadata {
       // ...
       #[serde(default, skip_serializing_if = "Option::is_none")]
       #[ts(optional)]
       pub dependencies: Option<SkillDependencies>,
       // ...
   }
   ```

2. **Skill 加载器**: `codex-rs/core/src/skills/loader.rs`
   - 解析 SKILL.json 中的 dependencies 字段
   - 验证工具依赖的可用性

3. **依赖注入**: `codex-rs/core/src/skills/injection.rs`
   - 根据 dependencies 配置注入工具到 Skill 上下文

4. **MCP 依赖管理**: `codex-rs/core/src/mcp/skill_dependencies.rs`
   - 处理 MCP 工具依赖的解析和验证

### 相关文件
| 文件路径 | 说明 |
|----------|------|
| `codex-rs/core/src/skills/manager.rs` | Skill 管理器，处理依赖生命周期 |
| `codex-rs/core/src/skills/model.rs` | Skill 数据模型定义 |
| `codex-rs/core/src/skills/env_var_dependencies.rs` | 环境变量依赖处理 |

## 依赖与外部交互

### 内部依赖
| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `SkillToolDependency` | `./SkillToolDependency` | 工具依赖详情 |
| `ts_rs::TS` | Rust crate | TypeScript 类型生成 |
| `schemars::JsonSchema` | Rust crate | JSON Schema 生成 |

### 外部交互
1. **SKILL.json 解析**: 从 Skill 配置文件中读取依赖声明
2. **MCP 服务器通信**: 验证和获取 MCP 工具信息
3. **Skill 市场**: 展示 Skill 的依赖列表

### 配置示例（SKILL.json）
```json
{
  "name": "my-skill",
  "description": "A skill with dependencies",
  "dependencies": {
    "tools": [
      {
        "type": "mcp",
        "value": "filesystem",
        "description": "File system access tool",
        "transport": "stdio",
        "command": "npx -y @modelcontextprotocol/server-filesystem"
      },
      {
        "type": "mcp",
        "value": "github",
        "description": "GitHub integration",
        "url": "https://api.github.com"
      }
    ]
  }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **循环依赖风险**
   - Skill A 依赖 Skill B，Skill B 又依赖 Skill A
   - **缓解措施**: 在 Skill 加载时进行依赖图检测，发现循环依赖时报错

2. **版本冲突**
   - 多个 Skill 依赖同一工具的不同版本
   - **当前状态**: 缺乏版本约束机制
   - **缓解措施**: 在 `value` 字段中嵌入版本信息，如 `"filesystem@1.2.3"`

3. **工具不可用**
   - 声明的依赖在运行时不可用
   - **缓解措施**: 在 Skill 启用前进行依赖健康检查

### 边界情况

1. **空依赖列表**: `tools: []` 是合法的，表示无外部依赖
2. **缺失 dependencies 字段**: SkillMetadata 中 dependencies 为 Option 类型，缺失表示无依赖
3. **重复依赖**: 同一工具被多次声明，应去重处理

### 改进建议

1. **添加版本约束支持**
   ```rust
   pub struct SkillToolDependency {
       pub r#type: String,
       pub value: String,
       pub version_constraint: Option<String>, // "^1.0.0", ">=2.0.0"
       // ...
   }
   ```

2. **支持可选依赖**
   ```rust
   pub struct SkillToolDependency {
       // ...
       pub optional: bool, // 如果为 true，工具缺失时 Skill 仍可运行
       pub fallback_behavior: Option<String>, // 缺失时的回退行为
   }
   ```

3. **添加依赖类别**
   ```rust
   pub struct SkillDependencies {
       pub tools: Vec<SkillToolDependency>,
       pub required: Vec<SkillDependency>,      // 必需依赖
       pub optional: Vec<SkillDependency>,      // 可选依赖
       pub conflicts: Vec<String>,              // 冲突的 Skill 名称
   }
   ```

4. **支持环境变量依赖（正式化）**
   ```rust
   pub struct SkillDependencies {
       pub tools: Vec<SkillToolDependency>,
       pub env_vars: Vec<EnvVarDependency>,     // 环境变量依赖
       pub files: Vec<FileDependency>,          // 文件依赖
   }
   ```

5. **依赖解析服务**
   ```rust
   pub trait DependencyResolver {
       fn resolve(&self, dep: &SkillToolDependency) -> Result<ToolHandle, ResolveError>;
       fn check_health(&self, dep: &SkillToolDependency) -> HealthStatus;
   }
   ```

6. **依赖缓存和复用**
   - 多个 Skill 依赖相同工具时，共享工具实例
   - 实现工具连接池，减少资源消耗

### 测试建议
- 单元测试：验证依赖结构的序列化/反序列化
- 集成测试：验证依赖解析和工具注入流程
- 边界测试：测试空依赖、重复依赖、缺失依赖等场景
- 性能测试：测试大量 Skill 依赖解析的性能
