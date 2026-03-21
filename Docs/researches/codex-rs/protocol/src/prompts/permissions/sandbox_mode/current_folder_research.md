# 研究文档：codex-rs/protocol/src/prompts/permissions/sandbox_mode

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`sandbox_mode` 目录是 Codex 协议层中负责**沙箱模式提示模板**的核心组件。其主要职责包括：

1. **向 AI 模型传达沙箱权限策略**：通过 Markdown 模板文件，向 AI 模型说明当前会话的文件系统访问权限和网络访问权限。

2. **支持三种沙箱模式**：
   - `read-only`：仅允许读取文件，禁止写入
   - `workspace-write`：允许读取文件，并可在当前工作目录和可写根目录中编辑文件
   - `danger-full-access`：无文件系统沙箱限制，所有命令都被允许

3. **与审批策略协同工作**：沙箱模式与 `approval_policy`（审批策略）共同构成 Codex 的安全权限模型。

4. **动态提示生成**：模板中的 `{network_access}` 占位符在运行时被替换为实际的网络访问状态（enabled/restricted）。

---

## 功能点目的

### 2.1 安全边界声明

沙箱模式提示模板的核心目的是**向 AI 模型明确声明当前执行环境的安全边界**，使模型能够：
- 了解哪些文件操作是允许的
- 知道何时需要请求用户审批
- 理解网络访问是否受限

### 2.2 三种模式的语义差异

| 模式 | 文件读取 | 文件写入 | 典型使用场景 |
|------|----------|----------|--------------|
| `read-only` | ✅ 允许 | ❌ 禁止 | 代码审查、只读分析 |
| `workspace-write` | ✅ 允许 | ✅ 仅在 cwd 和 writable_roots | 日常开发、项目编辑 |
| `danger-full-access` | ✅ 允许 | ✅ 无限制 | 系统管理、危险操作 |

### 2.3 与 NetworkAccess 的组合

每个沙箱模式模板都包含 `{network_access}` 占位符，实际渲染时会替换为：
- `NetworkAccess::Enabled` → "Network access is enabled."
- `NetworkAccess::Restricted` → "Network access is restricted."

---

## 具体技术实现

### 3.1 模板文件结构

```
codex-rs/protocol/src/prompts/permissions/sandbox_mode/
├── read_only.md           # 只读模式提示模板
├── workspace_write.md     # 工作区写入模式提示模板
└── danger_full_access.md  # 完全访问模式提示模板
```

### 3.2 模板内容示例

**read_only.md**:
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `read-only`: The sandbox only permits reading files. Network access is {network_access}.
```

**workspace_write.md**:
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `workspace-write`: The sandbox permits reading files, and editing files in `cwd` and `writable_roots`. Editing files in other directories requires approval. Network access is {network_access}.
```

**danger_full_access.md**:
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. Network access is {network_access}.
```

### 3.3 代码中的模板加载与渲染

模板通过 Rust 的 `include_str!` 宏在编译时嵌入到二进制中：

```rust
// codex-rs/protocol/src/models.rs 第 485-489 行
const SANDBOX_MODE_DANGER_FULL_ACCESS: &str = 
    include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
const SANDBOX_MODE_WORKSPACE_WRITE: &str = 
    include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
const SANDBOX_MODE_READ_ONLY: &str = 
    include_str!("prompts/permissions/sandbox_mode/read_only.md");
```

### 3.4 DeveloperInstructions 的生成流程

`sandbox_text` 方法负责根据 `SandboxMode` 和 `NetworkAccess` 生成开发者指令：

```rust
// codex-rs/protocol/src/models.rs 第 686-695 行
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
        SandboxMode::WorkspaceWrite => SANDBOX_MODE_WORKSPACE_WRITE.trim_end(),
        SandboxMode::ReadOnly => SANDBOX_MODE_READ_ONLY.trim_end(),
    };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

### 3.5 SandboxMode 枚举定义

```rust
// codex-rs/protocol/src/config_types.rs 第 52-67 行
#[derive(Deserialize, Debug, Clone, Copy, PartialEq, Default, Serialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum SandboxMode {
    #[serde(rename = "read-only")]
    #[default]
    ReadOnly,

    #[serde(rename = "workspace-write")]
    WorkspaceWrite,

    #[serde(rename = "danger-full-access")]
    DangerFullAccess,
}
```

### 3.6 与 SandboxPolicy 的映射关系

`SandboxMode` 与 `SandboxPolicy`（运行时沙箱策略）之间存在映射关系：

```rust
// codex-rs/protocol/src/models.rs 第 604-612 行
let (sandbox_mode, writable_roots) = match sandbox_policy {
    SandboxPolicy::DangerFullAccess => (SandboxMode::DangerFullAccess, None),
    SandboxPolicy::ReadOnly { .. } => (SandboxMode::ReadOnly, None),
    SandboxPolicy::ExternalSandbox { .. } => (SandboxMode::DangerFullAccess, None),
    SandboxPolicy::WorkspaceWrite { .. } => {
        let roots = sandbox_policy.get_writable_roots_with_cwd(cwd);
        (SandboxMode::WorkspaceWrite, Some(roots))
    }
};
```

---

## 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/*.md` | 沙箱模式提示模板 |
| `codex-rs/protocol/src/models.rs` | 模板加载、DeveloperInstructions 生成 |
| `codex-rs/protocol/src/config_types.rs` | `SandboxMode` 枚举定义 |
| `codex-rs/protocol/src/protocol.rs` | `SandboxPolicy`、`NetworkAccess` 定义 |

### 4.2 配置层相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/config/profile.rs` | `ConfigProfile` 包含 `sandbox_mode` 字段 |
| `codex-rs/core/src/config/mod.rs` | 配置解析、沙箱策略派生 |
| `codex-rs/core/src/config/types.rs` | `WindowsSandboxModeToml` 定义 |

### 4.3 权限系统相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/protocol/src/permissions.rs` | `FileSystemSandboxPolicy` 定义与转换 |
| `codex-rs/core/src/tools/sandboxing.rs` | 运行时沙箱 trait 和审批逻辑 |

### 4.4 调用链示例

```
ConfigProfile::sandbox_mode
    ↓
Config::derive_sandbox_policy()
    ↓
SandboxPolicy
    ↓
DeveloperInstructions::from_policy()
    ↓
DeveloperInstructions::sandbox_text()
    ↓
include_str!("prompts/permissions/sandbox_mode/*.md")
```

---

## 依赖与外部交互

### 5.1 编译时依赖

- `include_str!` 宏：将 Markdown 模板嵌入到编译后的二进制中
- 模板修改后需要重新编译才能生效

### 5.2 运行时依赖

| 依赖项 | 说明 |
|--------|------|
| `SandboxMode` | 决定使用哪个模板 |
| `NetworkAccess` | 填充模板中的 `{network_access}` 占位符 |
| `SandboxPolicy` | 运行时沙箱策略，映射到 `SandboxMode` |
| `WritableRoot` | `workspace-write` 模式下的可写根目录列表 |

### 5.3 与审批策略的交互

沙箱模式与审批策略（`approval_policy`）共同工作：

```rust
// 审批策略模板位于
codex-rs/protocol/src/prompts/permissions/approval_policy/
├── never.md
├── unless_trusted.md
├── on_failure.md
├── on_request_rule.md
└── on_request_rule_request_permission.md
```

`DeveloperInstructions::from_permissions_with_network()` 方法将沙箱模式提示与审批策略提示合并：

```rust
// codex-rs/protocol/src/models.rs 第 639-663 行
fn from_permissions_with_network(
    sandbox_mode: SandboxMode,
    network_access: NetworkAccess,
    approval_policy: AskForApproval,
    ...
) -> Self {
    let start_tag = DeveloperInstructions::new("<permissions instructions>");
    let end_tag = DeveloperInstructions::new("</permissions instructions>");
    start_tag
        .concat(DeveloperInstructions::sandbox_text(sandbox_mode, network_access))
        .concat(DeveloperInstructions::from(approval_policy, ...))
        .concat(DeveloperInstructions::from_writable_roots(writable_roots))
        .concat(end_tag)
}
```

### 5.4 与配置系统的交互

沙箱模式可以通过以下方式配置：

1. **配置文件** (`config.toml`):
   ```toml
   sandbox_mode = "workspace-write"  # 或 "read-only", "danger-full-access"
   ```

2. **Profile 配置**:
   ```toml
   [profiles.work]
   sandbox_mode = "danger-full-access"
   ```

3. **CLI 覆盖**:
   ```rust
   ConfigOverrides {
       sandbox_mode: Some(SandboxMode::WorkspaceWrite),
       ...
   }
   ```

---

## 风险、边界与改进建议

### 6.1 潜在风险

1. **模板与代码不同步**
   - 风险：修改模板后忘记更新测试中的预期字符串
   - 缓解：测试 `converts_sandbox_mode_into_developer_instructions` 验证模板渲染结果

2. **NetworkAccess 默认值误导**
   - 风险：`SandboxMode::DangerFullAccess` 默认映射到 `NetworkAccess::Enabled`，可能不符合预期
   - 代码位置：`models.rs` 第 856-857 行

3. **模板硬编码英文**
   - 风险：不支持国际化，非英语用户可能难以理解权限提示
   - 现状：模板内容为硬编码英文，无翻译机制

### 6.2 边界情况

1. **ExternalSandbox 映射**
   - `SandboxPolicy::ExternalSandbox` 被映射到 `SandboxMode::DangerFullAccess`
   - 这可能误导 AI 模型认为没有沙箱限制，实际上外部沙箱可能仍有约束

2. **Windows 平台降级**
   - 在 Windows 平台上，`WorkspaceWrite` 模式会被降级为 `ReadOnly`（如果 Windows 沙箱未启用）
   - 代码位置：`core/src/config/mod.rs` 第 1786-1798 行

3. **空 writable_roots**
   - 当 `writable_roots` 为空时，`from_writable_roots()` 返回空字符串，不添加任何提示
   - 代码位置：`models.rs` 第 665-684 行

### 6.3 改进建议

1. **模板版本控制**
   - 建议：在模板中添加版本标识，便于追踪模板变更
   - 实现：在 Markdown 文件头部添加 YAML frontmatter

2. **动态模板加载**
   - 建议：支持从文件系统动态加载模板，便于用户自定义
   - 现状：模板通过 `include_str!` 硬编码，修改需重新编译

3. **增强测试覆盖**
   - 建议：为 `danger-full-access` 模式添加专门的测试用例
   - 现状：测试主要覆盖 `workspace-write` 和 `read-only` 模式

4. **国际化支持**
   - 建议：使用 `fluent` 或类似框架支持多语言模板
   - 优先级：低（当前目标用户主要为开发者）

5. **模板验证工具**
   - 建议：添加 CI 检查确保模板语法正确（占位符格式等）
   - 实现：编写脚本验证 `{network_access}` 占位符存在且格式正确

### 6.4 相关测试

关键测试用例位于：

```rust
// codex-rs/protocol/src/models.rs 第 1903-1919 行
#[test]
fn converts_sandbox_mode_into_developer_instructions() {
    let workspace_write: DeveloperInstructions = SandboxMode::WorkspaceWrite.into();
    assert_eq!(...);

    let read_only: DeveloperInstructions = SandboxMode::ReadOnly.into();
    assert_eq!(...);
}
```

---

## 附录：完整模板文本

### read_only.md
```
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `read-only`: The sandbox only permits reading files. Network access is {network_access}.
```

### workspace_write.md
```
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `workspace-write`: The sandbox permits reading files, and editing files in `cwd` and `writable_roots`. Editing files in other directories requires approval. Network access is {network_access}.
```

### danger_full_access.md
```
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. Network access is {network_access}.
```

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/protocol/src/prompts/permissions/sandbox_mode 目录及其依赖*
