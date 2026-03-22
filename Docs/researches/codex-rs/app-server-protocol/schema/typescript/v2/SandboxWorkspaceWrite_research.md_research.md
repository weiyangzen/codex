# SandboxWorkspaceWrite 研究文档

## 场景与职责

`SandboxWorkspaceWrite` 是 Codex App Server Protocol v2 中用于配置工作区写入沙箱模式的结构体。它提供了 `workspace-write` 沙箱模式的详细配置选项，包括可写根目录、网络访问和临时目录处理。

该类型在配置（`Config`）中使用，允许用户精细控制工作区写入模式的行为。

## 功能点目的

1. **可写目录配置**：指定允许写入的根目录列表
2. **网络访问控制**：控制是否允许网络访问
3. **临时目录管理**：控制临时目录的访问权限
4. **配置持久化**：支持在配置文件中持久化设置

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
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

```typescript
// TypeScript 生成类型 (schema/typescript/v2/SandboxWorkspaceWrite.ts)
export type SandboxWorkspaceWrite = { 
    writable_roots: Array<string>, 
    network_access: boolean, 
    exclude_tmpdir_env_var: boolean, 
    exclude_slash_tmp: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `writable_roots` | `Vec<PathBuf>` | `[]` | 允许写入的根目录列表 |
| `network_access` | `bool` | `false` | 是否允许网络访问 |
| `exclude_tmpdir_env_var` | `bool` | `false` | 是否排除 `$TMPDIR` 环境变量指定的目录 |
| `exclude_slash_tmp` | `bool` | `false` | 是否排除 `/tmp` 目录 |

### 使用上下文

```rust
// 在 Config 中使用
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct Config {
    pub model: Option<String>,
    pub sandbox_mode: Option<SandboxMode>,
    pub sandbox_workspace_write: Option<SandboxWorkspaceWrite>,
    // ...
}
```

### 配置示例

```toml
# config.toml

# 使用 workspace-write 模式
sandbox_mode = "workspace-write"

# 详细配置
[sandbox_workspace_write]
writable_roots = ["/home/user/project", "/home/user/workspace"]
network_access = true
exclude_tmpdir_env_var = true
exclude_slash_tmp = true
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 522-534)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/SandboxWorkspaceWrite.ts`

### 相关类型
- `SandboxMode`: 沙箱模式枚举，`WorkspaceWrite` 变体使用此配置
- `SandboxPolicy::WorkspaceWrite`: 包含类似的字段
- `Config`: 包含 `sandbox_workspace_write` 字段

### 使用场景
- 配置文件中的 `sandbox_workspace_write` 部分
- 当 `sandbox_mode = "workspace-write"` 时生效

## 依赖与外部交互

### 内部依赖
- `std::path::PathBuf`: 路径类型
- `serde`: 序列化/反序列化（使用 `snake_case` 命名）
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**配置读取响应**:
```json
{
    "config": {
        "model": "gpt-4o",
        "sandboxMode": "workspace-write",
        "sandboxWorkspaceWrite": {
            "writableRoots": ["/home/user/project"],
            "networkAccess": false,
            "excludeTmpdirEnvVar": true,
            "excludeSlashTmp": true
        }
    }
}
```

### 与 SandboxPolicy::WorkspaceWrite 的关系

`SandboxWorkspaceWrite` 和 `SandboxPolicy::WorkspaceWrite` 有相似的字段，但用途不同：

| 特性 | SandboxWorkspaceWrite | SandboxPolicy::WorkspaceWrite |
|------|----------------------|------------------------------|
| 用途 | 配置文件中的持久化设置 | 运行时策略覆盖 |
| 字段 | 4 个字段 | 6 个字段（包含 `read_only_access`） |
| 使用位置 | `Config` | `TurnStartParams` |
| 灵活性 | 配置级别 | 回合级别 |

## 风险、边界与改进建议

### 当前限制
1. **无路径验证**：不验证路径是否存在或有效
2. **无重叠检测**：不检测 `writable_roots` 之间的重叠
3. **相对路径**：不处理相对路径的解析

### 边界情况
1. **空列表**：`writable_roots` 为空时，实际上没有可写目录
2. **根目录**：`/` 或 `C:\` 作为可写根目录的风险
3. **符号链接**：符号链接指向的目录的处理
4. **路径格式**：Windows 和 Unix 路径格式的差异

### 改进建议

1. **添加路径验证**：
   ```rust
   impl SandboxWorkspaceWrite {
       pub fn validate(&self) -> Result<(), ValidationError> {
           for root in &self.writable_roots {
               // 验证路径存在
               // 验证是绝对路径
               // 验证不是根目录
               // 验证没有符号链接循环
           }
       }
   }
   ```

2. **添加路径规范化**：
   ```rust
   impl SandboxWorkspaceWrite {
       pub fn normalize_paths(&mut self) {
           self.writable_roots = self.writable_roots
               .iter()
               .map(|p| p.canonicalize().unwrap_or_else(|_| p.clone()))
               .collect();
       }
   }
   ```

3. **添加默认工作区**：
   ```rust
   impl Default for SandboxWorkspaceWrite {
       fn default() -> Self {
           Self {
               writable_roots: vec![std::env::current_dir().unwrap_or_default()],
               network_access: false,
               exclude_tmpdir_env_var: true,
               exclude_slash_tmp: true,
           }
       }
   }
   ```

4. **添加安全警告**：
   ```rust
   impl SandboxWorkspaceWrite {
       pub fn security_warnings(&self) -> Vec<String> {
           let mut warnings = vec![];
           if self.writable_roots.iter().any(|p| p == Path::new("/")) {
               warnings.push("警告：允许写入根目录存在安全风险".to_string());
           }
           if self.network_access && self.writable_roots.len() > 3 {
               warnings.push("警告：网络访问配合多个可写目录可能风险较高".to_string());
           }
           warnings
       }
   }
   ```

### 兼容性注意
- 使用 `snake_case` 命名与 `config.toml` 保持一致
- 使用 `#[serde(default)]` 确保向后兼容
- TypeScript 中使用 `Array<string>` 表示路径列表

### 配置最佳实践

```toml
# 安全配置示例
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
# 只包含必要的项目目录
writable_roots = ["/home/user/myproject"]

# 默认关闭网络访问，需要时临时开启
network_access = false

# 排除临时目录，防止意外写入
exclude_tmpdir_env_var = true
exclude_slash_tmp = true
```

```toml
# 开发环境配置（较宽松）
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
# 包含多个工作区
writable_roots = [
    "/home/user/workspace/project1",
    "/home/user/workspace/project2"
]

# 开发时允许网络访问
network_access = true

# 仍然排除临时目录
exclude_tmpdir_env_var = true
exclude_slash_tmp = true
```

### 安全警告

1. **根目录风险**：不要将 `/` 或 `C:\` 添加到 `writable_roots`
2. **网络访问**：开启 `network_access` 时需谨慎
3. **家目录**：添加家目录（`~` 或 `/home/user`）会允许写入所有个人文件
4. **敏感目录**：避免添加包含敏感信息的目录（如 `.ssh`、`.aws`）
