# SandboxWorkspaceWrite 研究文档

## 1. 场景与职责

`SandboxWorkspaceWrite` 是 Codex app-server-protocol v2 协议中的工作区写入沙箱配置类型，用于配置工作区写入模式下的详细沙箱参数。该类型定义了可写根目录、网络访问权限以及临时文件排除选项。

### 使用场景
- **工作区写入模式配置**：为代码生成、文件修改等任务配置沙箱
- **多目录写入**：需要在多个特定目录进行写入操作
- **临时文件控制**：控制临时文件的创建位置和范围
- **网络访问控制**：在工作区写入模式下控制网络访问

## 2. 功能点目的

该类型的核心目的是：
1. **结构化配置**：将 `SandboxPolicy::WorkspaceWrite` 的配置参数独立为可复用类型
2. **灵活控制**：支持多目录写入和细粒度的临时文件控制
3. **配置复用**：可在多个上下文中使用相同的写入配置

### 与 SandboxPolicy 的关系
`SandboxWorkspaceWrite` 是 `SandboxPolicy::WorkspaceWrite` 变体的配置子集，专注于工作区写入的核心参数。

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
export type SandboxWorkspaceWrite = { 
  writable_roots: Array<string>, 
  network_access: boolean, 
  exclude_tmpdir_env_var: boolean, 
  exclude_slash_tmp: boolean, 
};
```

### 字段说明
| 字段 | 类型 | 说明 |
|------|------|------|
| `writable_roots` | `Array<string>` | 可写入的根目录路径列表 |
| `network_access` | `boolean` | 是否允许网络访问 |
| `exclude_tmpdir_env_var` | `boolean` | 是否排除 TMPDIR 环境变量指定的目录 |
| `exclude_slash_tmp` | `boolean` | 是否排除 `/tmp` 目录 |

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct SandboxWorkspaceWrite {
    #[serde(default)]
    pub writable_roots: Vec<PathBuf>,
    #[serde(default)]
    pub network_access: bool,
    #[serde(default)]
    pub exclude_tmpdir_env_var: bool,
    #[serde(default)]
    pub exclude_slash_tmp: bool,
}
```

### 序列化特性
- 使用 `snake_case` 命名风格（与 TypeScript 中的字段名一致）
- 所有字段都有 `#[serde(default)]`，支持部分配置
- 实现了 `Default` trait，提供合理的默认值

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 522-534)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/SandboxWorkspaceWrite.ts`

### 使用位置

#### 配置加载
- 可能用于从配置文件加载沙箱设置
- 作为 `SandboxPolicy::WorkspaceWrite` 的构建块

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

## 5. 依赖与外部交互

### 导入依赖
- 无直接导入的类型

### 被依赖类型
- `SandboxPolicy` - `WorkspaceWrite` 变体包含类似字段
- 可能用于配置文件的序列化/反序列化

### 字段类型映射
| Rust 类型 | TypeScript 类型 | 说明 |
|-----------|-----------------|------|
| `Vec<PathBuf>` | `Array<string>` | 路径列表 |
| `bool` | `boolean` | 布尔标志 |

## 6. 风险、边界与改进建议

### 潜在风险
1. **路径验证缺失**：`writable_roots` 中的路径需要验证
2. **默认空列表**：`writable_roots` 默认为空，可能导致无目录可写
3. **路径格式**：需要确保路径格式正确（绝对路径 vs 相对路径）

### 边界情况
- **空 writable_roots**：可能导致沙箱无法写入任何文件
- **无效路径**：路径不存在或不可访问
- **权限冲突**：可写目录与系统限制冲突

### 改进建议
1. **添加验证**：
   ```rust
   impl SandboxWorkspaceWrite {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 验证所有路径为绝对路径
           // 验证路径存在且可写
           // 验证无路径遍历风险
       }
   }
   ```

2. **添加默认值**：
   ```rust
   impl Default for SandboxWorkspaceWrite {
       fn default() -> Self {
           Self {
               writable_roots: vec![PathBuf::from(".")],  // 默认当前目录
               network_access: false,
               exclude_tmpdir_env_var: false,
               exclude_slash_tmp: false,
           }
       }
   }
   ```

3. **添加辅助方法**：
   ```typescript
   // 检查路径是否在可写范围内
   function isPathWritable(config: SandboxWorkspaceWrite, path: string): boolean;
   
   // 获取有效的临时目录
   function getTempDirectory(config: SandboxWorkspaceWrite): string | null;
   ```

4. **文档完善**：
   - 说明 `writable_roots` 的路径格式要求
   - 说明临时文件排除的实际影响
   - 提供配置示例

### 使用示例
```typescript
// 基本配置
const basicConfig: SandboxWorkspaceWrite = {
  writable_roots: ["/home/user/project"],
  network_access: false,
  exclude_tmpdir_env_var: false,
  exclude_slash_tmp: false
};

// 严格配置（仅项目目录，无网络，无系统临时目录）
const strictConfig: SandboxWorkspaceWrite = {
  writable_roots: ["/home/user/project"],
  network_access: false,
  exclude_tmpdir_env_var: true,
  exclude_slash_tmp: true
};

// 宽松配置（多目录，允许网络）
const permissiveConfig: SandboxWorkspaceWrite = {
  writable_roots: [
    "/home/user/project",
    "/home/user/.cache",
    "/tmp/project-cache"
  ],
  network_access: true,
  exclude_tmpdir_env_var: false,
  exclude_slash_tmp: false
};
```

### 与 SandboxPolicy 的关系
```
SandboxPolicy
└── WorkspaceWrite {
      writable_roots: Vec<AbsolutePathBuf>,  // 本类型的字段
      read_only_access: ReadOnlyAccess,       // 额外字段
      network_access: bool,                   // 本类型的字段
      exclude_tmpdir_env_var: bool,           // 本类型的字段
      exclude_slash_tmp: bool,                // 本类型的字段
    }

SandboxWorkspaceWrite  <-- 本类型（独立配置类型）
├── writable_roots: Array<string>
├── network_access: boolean
├── exclude_tmpdir_env_var: boolean
└── exclude_slash_tmp: boolean
```

### 注意事项
- 该类型使用 `snake_case` 命名风格，与其他 v2 类型的 `camelCase` 不同
- 这可能是为了与配置文件（如 TOML）的命名风格保持一致
- 在使用时需要注意字段名的差异
