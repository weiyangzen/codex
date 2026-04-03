# SandboxWorkspaceWrite.ts 研究文档

## 场景与职责

`SandboxWorkspaceWrite.ts` 定义了工作区写入沙箱配置的简化数据结构，用于在配置文件中指定工作区写入模式的详细参数。这是 `SandboxMode.WorkspaceWrite` 的详细配置形式，支持通过配置文件精细控制沙箱行为。

## 功能点目的

该类型用于：
1. **配置持久化**：在 config.toml 中保存工作区写入沙箱的详细配置
2. **额外可写路径**：指定除工作区外的其他可写目录
3. **临时目录控制**：控制是否包含系统临时目录
4. **网络访问**：配置是否允许网络访问

## 具体技术实现

### 数据结构定义

```typescript
export type SandboxWorkspaceWrite = { 
  writable_roots: Array<string>,      // 额外可写根目录路径
  network_access: boolean,            // 是否允许网络访问
  exclude_tmpdir_env_var: boolean,    // 是否排除 TMPDIR 环境变量目录
  exclude_slash_tmp: boolean,         // 是否排除 /tmp 目录
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| writable_roots | string[] | 除工作区外，还允许写入的额外目录路径 |
| network_access | boolean | 是否允许网络访问，默认为 false |
| exclude_tmpdir_env_var | boolean | 是否排除 TMPDIR 环境变量指向的目录，默认为 false |
| exclude_slash_tmp | boolean | 是否排除 /tmp 目录（UNIX 系统），默认为 false |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中：

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

### 核心配置类型

在 `codex-rs/core/src/config/types.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct SandboxWorkspaceWrite {
    #[serde(default)]
    pub writable_roots: Vec<AbsolutePathBuf>,
    #[serde(default)]
    pub network_access: bool,
    #[serde(default)]
    pub exclude_tmpdir_env_var: bool,
    #[serde(default)]
    pub exclude_slash_tmp: bool,
}

impl From<SandboxWorkspaceWrite> for codex_app_server_protocol::SandboxSettings {
    fn from(sandbox_workspace_write: SandboxWorkspaceWrite) -> Self {
        Self {
            writable_roots: sandbox_workspace_write.writable_roots,
            network_access: Some(sandbox_workspace_write.network_access),
            exclude_tmpdir_env_var: Some(sandbox_workspace_write.exclude_tmpdir_env_var),
            exclude_slash_tmp: Some(sandbox_workspace_write.exclude_slash_tmp),
        }
    }
}
```

### 配置使用示例

在 `config.toml` 中：

```toml
[sandbox_workspace_write]
writable_roots = ["/home/user/data", "/var/log/myapp"]
network_access = true
exclude_tmpdir_env_var = false
exclude_slash_tmp = false
```

### 到 SandboxPolicy 的转换

```rust
impl From<SandboxWorkspaceWriteConfig> for SandboxPolicy {
    fn from(config: SandboxWorkspaceWriteConfig) -> Self {
        SandboxPolicy::WorkspaceWrite {
            writable_roots: config.writable_roots,
            read_only_access: ReadOnlyAccess::default(),
            network_access: config.network_access,
            exclude_tmpdir_env_var: config.exclude_tmpdir_env_var,
            exclude_slash_tmp: config.exclude_slash_tmp,
        }
    }
}
```

### 默认可写路径

在 WorkspaceWrite 模式下，默认可写路径包括：
1. 当前工作目录 (cwd)
2. TMPDIR 环境变量指向的目录（除非 exclude_tmpdir_env_var = true）
3. /tmp 目录（UNIX 系统，除非 exclude_slash_tmp = true）
4. writable_roots 中指定的额外目录

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxWorkspaceWrite.ts`

### Rust 协议定义
- V2 API：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 核心配置
- 配置类型：`codex-rs/core/src/config/types.rs`
- 配置模块：`codex-rs/core/src/config/mod.rs`

### 配置模式
- JSON Schema：`codex-rs/core/config.schema.json`

### 相关类型
- Config：`codex-rs/app-server-protocol/schema/typescript/v2/Config.ts`
- SandboxPolicy：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxPolicy.ts`

## 依赖与外部交互

### 上游依赖
- 配置文件：从 config.toml 读取
- 配置 API：通过 config/read 和 config/write RPC 方法访问

### 下游消费
- SandboxPolicy：转换为完整的沙箱策略
- 执行引擎：应用沙箱限制

### 配置层级

```
Config
  └── sandbox_workspace_write: SandboxWorkspaceWrite
        └── 转换为 SandboxPolicy::WorkspaceWrite
              └── 应用到沙箱执行器
```

## 风险、边界与改进建议

### 边界情况
1. **路径验证**：writable_roots 中的路径需要是绝对路径
2. **路径存在**：指定的路径可能不存在，需要处理
3. **权限检查**：即使路径在列表中，也需要检查实际权限

### 潜在风险
1. **敏感目录**：用户可能意外添加敏感目录到 writable_roots
2. **符号链接**：需要处理符号链接指向的目录
3. **嵌套路径**：writable_roots 中的路径可能互相嵌套

### 改进建议
1. **路径验证**：添加路径存在性和权限验证
2. **敏感目录警告**：对常见敏感目录添加警告
3. **路径规范化**：自动规范化路径（解析符号链接等）
4. **模板支持**：提供常见场景的预设配置
5. **文档增强**：添加更多使用示例和最佳实践
