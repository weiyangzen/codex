# SandboxWorkspaceWrite 研究文档

## 场景与职责

`SandboxWorkspaceWrite` 是 Codex app-server-protocol v2 协议中的工作区写入沙箱配置类型，用于配置工作区写入模式下的详细沙箱参数。该类型定义了可写根目录、网络访问权限以及临时文件排除选项，是 `SandboxPolicy::WorkspaceWrite` 的配置子集。

在 Codex 的沙箱配置体系中，`SandboxWorkspaceWrite` 承担以下职责：
1. **细粒度配置**：提供 `SandboxMode::WorkspaceWrite` 的详细参数
2. **路径控制**：精确控制可写文件系统范围
3. **网络控制**：配置网络访问权限
4. **临时文件处理**：控制临时目录的访问策略

## 功能点目的

### 核心功能
- **可写根目录**：指定允许写入的文件系统路径
- **网络访问**：控制是否允许网络访问
- **临时目录排除**：控制是否排除临时目录

### 设计意图
- **配置分离**：将 `WorkspaceWrite` 配置从 `Config` 中分离
- **灵活路径**：支持多个可写根目录
- **安全默认**：默认限制临时目录访问

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`SandboxWorkspaceWrite.ts`）：
```typescript
export type SandboxWorkspaceWrite = { 
  writable_roots: Array<string>, 
  network_access: boolean, 
  exclude_tmpdir_env_var: boolean, 
  exclude_slash_tmp: boolean, 
};
```

**Rust 定义**（`v2.rs` 行 525-534）：
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

### 关键字段说明

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `writable_roots` | `Array<string>` | `[]` | 可写根目录列表，相对于工作区的路径 |
| `network_access` | `boolean` | `false` | 是否允许网络访问 |
| `exclude_tmpdir_env_var` | `boolean` | `false` | 是否排除 `$TMPDIR` 环境变量指定的目录 |
| `exclude_slash_tmp` | `boolean` | `false` | 是否排除 `/tmp` 目录 |

### 与 Config 的关系

在 `Config` 中（行 705）：
```rust
pub struct Config {
    // ...
    pub sandbox_mode: Option<SandboxMode>,
    pub sandbox_workspace_write: Option<SandboxWorkspaceWrite>,
    // ...
}
```

### 与 SandboxPolicy 的关系

`SandboxWorkspaceWrite` 是 `SandboxPolicy::WorkspaceWrite` 的配置子集：

```rust
SandboxPolicy::WorkspaceWrite {
    writable_roots: Vec<AbsolutePathBuf>,      // 来自 SandboxWorkspaceWrite.writable_roots
    read_only_access: ReadOnlyAccess,          // 默认或额外配置
    network_access: bool,                      // 来自 SandboxWorkspaceWrite.network_access
    exclude_tmpdir_env_var: bool,              // 来自 SandboxWorkspaceWrite.exclude_tmpdir_env_var
    exclude_slash_tmp: bool,                   // 来自 SandboxWorkspaceWrite.exclude_slash_tmp
}
```

### 核心层对应类型

在 `core/src/config/types.rs` 行 836-860：
```rust
pub struct SandboxWorkspaceWrite {
    pub writable_roots: Vec<PathBuf>,
    pub network_access: bool,
    pub exclude_tmpdir_env_var: bool,
    pub exclude_slash_tmp: bool,
}

impl From<SandboxWorkspaceWrite> for codex_app_server_protocol::SandboxSettings {
    fn from(sandbox_workspace_write: SandboxWorkspaceWrite) -> Self {
        Self {
            writable_roots: sandbox_workspace_write.writable_roots,
            network_access: sandbox_workspace_write.network_access,
            exclude_tmpdir_env_var: sandbox_workspace_write.exclude_tmpdir_env_var,
            exclude_slash_tmp: sandbox_workspace_write.exclude_slash_tmp,
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 525-534
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxWorkspaceWrite.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ConfigReadResponse.json`

### 使用位置
- **Config**：`v2.rs` 行 705 - 配置的一部分
- **核心层**：`core/src/config/types.rs` 行 836 - 对应类型
- **配置解析**：`core/src/config/mod.rs` 行 1770 - 解析配置

### 相关类型
- `SandboxMode`：高层沙箱模式（行 301）
- `SandboxPolicy`：详细沙箱策略（行 1275）
- `Config`：包含 `sandbox_workspace_write` 字段（行 705）

### 配置示例

```toml
# config.toml
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
writable_roots = ["./src", "./tests"]
network_access = true
exclude_tmpdir_env_var = true
exclude_slash_tmp = true
```

## 依赖与外部交互

### 依赖项
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `SandboxWorkspaceWrite`（核心层）：`core/src/config/types.rs`

### 下游使用
- `Config`：配置类型
- `SandboxPolicy`：转换为详细策略的一部分

### 协议集成
- 通过 `config/read` 获取配置
- 在 `SandboxMode::WorkspaceWrite` 时生效

## 风险、边界与改进建议

### 潜在风险
1. **路径遍历**：`writable_roots` 中的路径可能存在遍历漏洞
2. **配置遗漏**：未正确配置 `writable_roots` 导致功能受限
3. **临时文件泄露**：临时目录配置不当可能导致敏感信息泄露
4. **网络滥用**：`network_access: true` 可能被滥用

### 边界情况
1. **空根目录**：`writable_roots` 为空时的行为
2. **无效路径**：指向不存在目录的路径
3. **相对路径**：非绝对路径的处理
4. **重叠路径**：多个根目录重叠的情况

### 改进建议
1. **验证增强**：
   - 添加路径验证（存在性、权限）
   - 规范化路径格式
   - 检查路径冲突

2. **功能扩展**：
   ```rust
   pub struct SandboxWorkspaceWrite {
       // 现有字段...
       /// 最大可写文件大小（字节）
       pub max_file_size: Option<u64>,
       /// 可写文件类型白名单
       pub allowed_extensions: Option<Vec<String>>,
       /// 磁盘配额（字节）
       pub disk_quota: Option<u64>,
   }
   ```

3. **安全增强**：
   - 实现路径访问审计
   - 添加异常写入检测
   - 支持只写目录（不可读）

4. **用户体验**：
   - 提供配置向导
   - 显示当前可写范围
   - 提供配置验证工具

5. **性能优化**：
   - 实现路径缓存
   - 优化权限检查
   - 支持异步配置加载

6. **文档完善**：
   - 提供配置示例
   - 说明安全最佳实践
   - 解释各选项的影响
