# SandboxMode 研究文档

## 场景与职责

`SandboxMode` 是 Codex app-server-protocol v2 协议中的沙箱模式类型，用于定义代码执行的安全级别。该类型提供三种预设的安全模式，从严格的只读访问到完全访问，满足不同场景下的安全与功能需求平衡。

在 Codex 的安全体系中，`SandboxMode` 承担以下职责：
1. **安全分级**：提供不同级别的代码执行安全策略
2. **权限控制**：控制文件系统访问和网络访问权限
3. **用户保护**：防止恶意或意外代码造成损害
4. **配置简化**：提供预设配置，降低用户配置复杂度

## 功能点目的

### 核心功能
- **ReadOnly**：只读访问，最安全但功能受限
- **WorkspaceWrite**：工作区可写，平衡安全与功能
- **DangerFullAccess**：完全访问，功能最强但风险最高

### 设计意图
- **渐进安全**：从安全到功能的三级递进
- **易于理解**：命名直观，用户易于选择
- **与核心协议对齐**：与 `CoreSandboxMode` 双向映射
- **配置友好**：支持序列化和反序列化

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`SandboxMode.ts`）：
```typescript
export type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```

**Rust 定义**（`v2.rs` 行 301-325）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[ts(rename_all = "kebab-case", export_to = "v2/")]
pub enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}

impl SandboxMode {
    pub fn to_core(self) -> CoreSandboxMode {
        match self {
            SandboxMode::ReadOnly => CoreSandboxMode::ReadOnly,
            SandboxMode::WorkspaceWrite => CoreSandboxMode::WorkspaceWrite,
            SandboxMode::DangerFullAccess => CoreSandboxMode::DangerFullAccess,
        }
    }
}

impl From<CoreSandboxMode> for SandboxMode {
    fn from(value: CoreSandboxMode) -> Self {
        match value {
            CoreSandboxMode::ReadOnly => SandboxMode::ReadOnly,
            CoreSandboxMode::WorkspaceWrite => SandboxMode::WorkspaceWrite,
            CoreSandboxMode::DangerFullAccess => SandboxMode::DangerFullAccess,
        }
    }
}
```

### 关键值说明

| 值 | 说明 | 文件系统权限 | 网络权限 | 适用场景 |
|----|------|--------------|----------|----------|
| `"read-only"` | 只读模式 | 只读访问 | 受限 | 查看代码、安全分析 |
| `"workspace-write"` | 工作区写入 | 工作区可写 | 受限 | 日常开发、代码编辑 |
| `"danger-full-access"` | 完全访问 | 完全访问 | 完全访问 | 系统管理、特殊任务 |

### 与 SandboxPolicy 的关系

`SandboxMode` 是高层抽象，映射到 `SandboxPolicy` 的具体实现：

```
SandboxMode::ReadOnly 
  → SandboxPolicy::ReadOnly { access, network_access }

SandboxMode::WorkspaceWrite 
  → SandboxPolicy::WorkspaceWrite { writable_roots, read_only_access, network_access, ... }

SandboxMode::DangerFullAccess 
  → SandboxPolicy::DangerFullAccess
```

### 配置使用

在 `Config` 中（行 704）：
```rust
pub struct Config {
    // ...
    pub sandbox_mode: Option<SandboxMode>,
    pub sandbox_workspace_write: Option<SandboxWorkspaceWrite>,
    // ...
}
```

在 `ThreadStartParams` 中（行 2477）：
```rust
pub struct ThreadStartParams {
    // ...
    pub sandbox: Option<SandboxMode>,
    // ...
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 301-325
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/SandboxMode.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ConfigReadResponse.json`

### 使用位置
- **Config**：`v2.rs` 行 704 - 配置的一部分
- **ConfigRequirements**：`v2.rs` 行 826 - 允许的沙箱模式列表
- **ThreadStartParams**：`v2.rs` 行 2477 - 线程启动参数
- **消息处理器**：`codex_message_processor.rs` 行 7461-7470 - 模式处理

### 相关类型
- `CoreSandboxMode`：核心协议中的对应类型（`protocol/src/config_types.rs` 行 57）
- `SandboxPolicy`：详细的沙箱策略（行 1275-1305）
- `SandboxWorkspaceWrite`：工作区写入配置（行 525-534）
- `ConfigRequirements`：配置要求中的 `allowed_sandbox_modes`（行 826）

### 模式转换

在 `codex_message_processor.rs` 行 2132-2146：
```rust
fn to_sandbox_mode(sandbox: Option<SandboxMode>) -> Option<CoreSandboxMode> {
    sandbox.map(SandboxMode::to_core)
}
```

## 依赖与外部交互

### 依赖项
- `CoreSandboxMode`：核心协议中的沙箱模式
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `SandboxModeRequirement`（配置层）：`config/src/config_requirements.rs` 行 438

### 下游使用
- `Config`：配置类型
- `ThreadStartParams`, `ThreadResumeParams`, `ThreadForkParams`：线程生命周期参数
- `SandboxPolicy`：转换为详细策略

### 协议集成
- 通过 `config/read` 获取配置
- 通过 `thread/start` 等指定线程沙箱模式
- 受 `configRequirements/read` 中的 `allowedSandboxModes` 约束

## 风险、边界与改进建议

### 潜在风险
1. **权限提升**：`DangerFullAccess` 可能被恶意利用
2. **配置错误**：用户可能误选不安全的模式
3. **绕过可能**：某些情况下沙箱可能被绕过
4. **平台差异**：不同平台的沙箱实现可能有差异

### 边界情况
1. **嵌套执行**：子进程的沙箱模式处理
2. **外部工具**：调用外部工具时的沙箱继承
3. **网络代理**：`WorkspaceWrite` 模式下的网络访问控制
4. **符号链接**：沙箱内的符号链接处理

### 改进建议
1. **添加更多模式**：
   ```rust
   pub enum SandboxMode {
       ReadOnly,
       WorkspaceWrite,
       NetworkEnabled,    // 工作区可写 + 网络访问
       Containerized,     // 容器化隔离
       DangerFullAccess,
   }
   ```

2. **细粒度控制**：
   ```rust
   pub struct SandboxModeConfig {
       pub mode: SandboxMode,
       /// 额外的可写路径
       pub extra_writable_paths: Option<Vec<PathBuf>>,
       /// 允许的网络域名
       pub allowed_domains: Option<Vec<String>>,
       /// 环境变量白名单
       pub allowed_env_vars: Option<Vec<String>>,
   }
   ```

3. **安全增强**：
   - 添加模式切换确认（降级到 `DangerFullAccess` 时）
   - 实现模式审计日志
   - 添加异常行为检测
   - 支持只读快照执行

4. **用户体验**：
   - 提供模式选择向导
   - 显示当前模式的安全级别
   - 提供模式影响预览
   - 添加模式推荐功能

5. **企业功能**：
   - 支持强制模式策略
   - 实现模式审批工作流
   - 提供模式合规报告
   - 支持模式模板

6. **平台优化**：
   - 优化 macOS Seatbelt 配置
   - 改进 Linux Landlock/Bubblewrap 集成
   - 增强 Windows 沙箱支持
   - 支持容器运行时（Docker、containerd）
