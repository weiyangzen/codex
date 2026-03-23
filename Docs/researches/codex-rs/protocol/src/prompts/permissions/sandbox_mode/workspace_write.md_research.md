# workspace_write.md 研究文档

## 场景与职责

`workspace_write.md` 是 Codex CLI 中用于描述 **工作区写入沙箱模式** 的提示模板文件。当系统配置为 `workspace-write` 模式时，该文件内容会被注入到模型的开发者指令(developer instructions)中，告知 AI 模型当前执行环境允许读取文件，并允许在 `cwd`（当前工作目录）和配置的 `writable_roots` 中编辑文件。

这是 **最常用的沙箱模式**，在安全性与功能性之间取得平衡，适合日常开发工作。

## 功能点目的

### 核心功能
1. **分层权限告知**: 明确告知模型可以读取所有文件，但写入受限
2. **工作区边界定义**: 限制写入操作仅在指定的工作区目录内
3. **审批流程提示**: 告知编辑其他目录需要用户审批
4. **网络状态显示**: 通过 `{network_access}` 占位符显示网络访问状态

### 设计意图
- **安全与便利平衡**: 允许在工作区内自由编辑，同时保护系统其他区域
- **最小意外原则**: 超出工作区的写入需要显式审批
- **协作友好**: 适合团队协作场景，防止意外修改系统文件

## 具体技术实现

### 文件内容
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `workspace-write`: The sandbox permits reading files, and editing files in `cwd` and `writable_roots`. Editing files in other directories requires approval. Network access is {network_access}.
```

### 关键流程

#### 1. 模板加载
```rust
// codex-rs/protocol/src/models.rs:487-488
const SANDBOX_MODE_WORKSPACE_WRITE: &str =
    include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
```

#### 2. 指令生成与 writable_roots 注入
```rust
// codex-rs/protocol/src/models.rs:590-623
pub fn from_policy(
    sandbox_policy: &SandboxPolicy,
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    cwd: &Path,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> Self {
    let (sandbox_mode, writable_roots) = match sandbox_policy {
        SandboxPolicy::DangerFullAccess => (SandboxMode::DangerFullAccess, None),
        SandboxPolicy::ReadOnly { .. } => (SandboxMode::ReadOnly, None),
        SandboxPolicy::ExternalSandbox { .. } => (SandboxMode::DangerFullAccess, None),
        SandboxPolicy::WorkspaceWrite { .. } => {
            let roots = sandbox_policy.get_writable_roots_with_cwd(cwd);
            (SandboxMode::WorkspaceWrite, Some(roots))
        }
    };

    DeveloperInstructions::from_permissions_with_network(
        sandbox_mode,
        network_access,
        approval_policy,
        exec_policy,
        writable_roots,  // <-- 传递给指令生成
        // ...
    )
}
```

#### 3. writable_roots 渲染
```rust
// codex-rs/protocol/src/models.rs:665-684
fn from_writable_roots(writable_roots: Option<Vec<WritableRoot>>) -> Self {
    let Some(roots) = writable_roots else {
        return DeveloperInstructions::new("");
    };

    if roots.is_empty() {
        return DeveloperInstructions::new("");
    }

    let roots_list: Vec<String> = roots
        .iter()
        .map(|r| format!("`{}`", r.root.to_string_lossy()))
        .collect();
    let text = if roots_list.len() == 1 {
        format!(" The writable root is {}.", roots_list[0])
    } else {
        format!(" The writable roots are {}.", roots_list.join(", "))
    };
    DeveloperInstructions::new(text)
}
```

### 数据结构

#### SandboxPolicy::WorkspaceWrite
```rust
// codex-rs/protocol/src/protocol.rs
SandboxPolicy::WorkspaceWrite {
    writable_roots: Vec<AbsolutePathBuf>,
    read_only_access: ReadOnlyAccess,
    network_access: bool,
    exclude_tmpdir_env_var: bool,
    exclude_slash_tmp: bool,
}
```

#### WritableRoot 结构
```rust
pub struct WritableRoot {
    pub root: AbsolutePathBuf,
    pub read_only_subpaths: Vec<AbsolutePathBuf>,  // 可写根目录内的只读子路径
}
```

#### FileSystemSandboxPolicy 转换
```rust
// codex-rs/protocol/src/permissions.rs:754-822
SandboxPolicy::WorkspaceWrite { ... } => {
    let mut entries = Vec::new();
    // 添加读取权限配置...
    
    entries.push(FileSystemSandboxEntry {
        path: FileSystemPath::Special {
            value: FileSystemSpecialPath::CurrentWorkingDirectory,
        },
        access: FileSystemAccessMode::Write,
    });
    if !exclude_slash_tmp {
        entries.push(FileSystemSandboxEntry {
            path: FileSystemPath::Special {
                value: FileSystemSpecialPath::SlashTmp,
            },
            access: FileSystemAccessMode::Write,
        });
    }
    if !exclude_tmpdir_env_var {
        entries.push(FileSystemSandboxEntry {
            path: FileSystemPath::Special {
                value: FileSystemSpecialPath::Tmpdir,
            },
            access: FileSystemAccessMode::Write,
        });
    }
    // 添加 writable_roots...
    FileSystemSandboxPolicy::restricted(entries)
}
```

## 关键代码路径与文件引用

### 直接引用
| 文件 | 行号 | 用途 |
|------|------|------|
| `codex-rs/protocol/src/models.rs` | 487-488 | 编译时嵌入模板 |
| `codex-rs/protocol/src/models.rs` | 689 | 模式匹配选择模板 |

### 核心调用链
| 文件 | 函数 | 说明 |
|------|------|------|
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::from_policy()` | 入口函数 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::from_permissions_with_network()` | 构建权限指令 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::sandbox_text()` | 选择并渲染模板 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::from_writable_roots()` | 追加可写根目录信息 |

### 策略实现
| 文件 | 说明 |
|------|------|
| `codex-rs/protocol/src/permissions.rs` | `FileSystemSandboxPolicy` 转换实现 |
| `codex-rs/core/src/sandboxing/mod.rs` | 运行时沙箱执行 |

### 配置支持
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/config/mod.rs` | 配置加载与解析 |
| `codex-rs/core/src/config/types.rs` | `SandboxWorkspaceWrite` 配置类型 |

## 依赖与外部交互

### 编译时依赖
- `include_str!` 宏编译时嵌入

### 运行时依赖
- `SandboxPolicy::WorkspaceWrite` 策略数据
- `cwd` 当前工作目录
- `writable_roots` 配置的额外可写目录
- `NetworkAccess` 网络状态

### 数据流
```
配置文件/CLI
    │
    ▼
┌─────────────────┐
│  ConfigLoader   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  SandboxPolicy  │────▶│  WorkspaceWrite  │
│  (WorkspaceWrite)│     │  {              │
└────────┬────────┘     │    writable_roots│
         │              │  }               │
         ▼              └──────────────────┘
┌─────────────────┐              │
│  Developer      │◀─────────────┘
│  Instructions   │  get_writable_roots_with_cwd()
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  sandbox_text() │────▶│ workspace_write  │
│                 │     │ .md 模板渲染      │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  from_writable  │────▶│ 追加 writable    │
│  _roots()       │     │ roots 列表       │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐
│   AI 模型提示    │
└─────────────────┘
```

### 与审批系统的交互
当模型尝试写入 `writable_roots` 之外的目录时：
1. 工具调用被拦截
2. 生成审批请求（`ExecApprovalRequestEvent`）
3. 用户批准后，可能通过 `sandbox_permissions: RequireEscalated` 提升权限执行

## 风险、边界与改进建议

### 安全边界
1. **工作区隔离**: 写入限制在 `cwd` 和 `writable_roots`
2. **临时目录控制**: 可通过配置排除 `/tmp` 或 `$TMPDIR`
3. **子路径保护**: 支持在可写根目录内设置只读子路径（如 `.git`）

### 使用边界
- **符号链接**: 需要正确处理符号链接防止路径逃逸
- **相对路径**: 所有相对路径基于 `cwd` 解析
- **跨平台**: 路径处理需考虑 Windows/Unix 差异

### 潜在风险
1. **路径遍历**: 如果路径解析不当，可能通过 `../` 逃逸工作区
2. **符号链接攻击**: 恶意符号链接可能指向敏感路径
3. **竞争条件**: 路径检查与实际操作之间的时间窗口

### 改进建议

#### 1. 增强提示信息
当前模板可扩展以包含更多指导：
```markdown
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `workspace-write`: The sandbox permits reading files, 
and editing files in `cwd` and `writable_roots`. Editing files in other 
directories requires approval. Network access is {network_access}.

Writable roots: {writable_roots_list}

To edit files outside these directories, use the `request_permissions` 
tool or run with `sandbox_permissions: "require_escalated"`.
```

#### 2. 动态权限提示
建议在提示中动态包含实际的 `writable_roots` 列表：
```rust
// 在 from_writable_roots() 中增强
let text = format!(
    "{}\n\nAllowed write locations: {}",
    base_template,
    roots_list.join(", ")
);
```

#### 3. 与 apply_patch 工具协调
- 确保 `apply_patch` 工具遵守相同的写入限制
- 在补丁应用前进行路径验证

#### 4. 审计与监控
- 记录超出工作区的写入尝试
- 提供配置选项启用详细审计日志

### 配置示例
```toml
# ~/.codex/config.toml
[sandbox]
mode = "workspace-write"

# 可选：额外可写目录
[[sandbox.writable_roots]]
path = "/home/user/shared-libs"
read_only_subpaths = [".git", "node_modules"]

# 可选：限制临时目录访问
[sandbox.workspace_write]
exclude_tmpdir_env_var = false
exclude_slash_tmp = true
```

### 测试建议
```rust
#[test]
fn workspace_write_respects_writable_roots() {
    let policy = SandboxPolicy::WorkspaceWrite {
        writable_roots: vec!["/workspace".into()],
        read_only_access: ReadOnlyAccess::FullAccess,
        network_access: false,
        exclude_tmpdir_env_var: false,
        exclude_slash_tmp: false,
    };
    
    let fs_policy = FileSystemSandboxPolicy::from(&policy);
    assert!(fs_policy.can_write_path_with_cwd("/workspace/file.txt", "/workspace"));
    assert!(!fs_policy.can_write_path_with_cwd("/etc/passwd", "/workspace"));
}
```

### 与其他模式对比
| 特性 | `read-only` | `workspace-write` | `danger-full-access` |
|------|-------------|-------------------|---------------------|
| 读取 | ✅ 受限/全部 | ✅ 全部 | ✅ 全部 |
| 工作区写入 | ❌ | ✅ | ✅ |
| 系统写入 | ❌ | ❌ (需审批) | ✅ |
| 安全性 | ⭐⭐⭐ | ⭐⭐ | ⭐ |
| 适用场景 | 审查/分析 | 日常开发 | 系统管理 |

### 相关文件引用
| 文件 | 关键功能 |
|------|----------|
| `codex-rs/protocol/src/permissions.rs` | `FileSystemSandboxPolicy` 实现路径解析与权限检查 |
| `codex-rs/core/src/sandboxing/mod.rs` | 运行时沙箱执行与权限执行 |
| `codex-rs/core/src/tools/sandboxing.rs` | 工具级别的沙箱集成 |
