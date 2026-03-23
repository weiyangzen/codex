# read_only.md 研究文档

## 场景与职责

`read_only.md` 是 Codex CLI 中用于描述 **只读沙箱模式** 的提示模板文件。当系统配置为 `read-only` 模式时，该文件内容会被注入到模型的开发者指令(developer instructions)中，告知 AI 模型当前执行环境仅允许读取文件，禁止写入操作。

该文件是三个沙箱模式模板中最严格、最安全的一个，也是 `SandboxMode` 枚举的默认模式（`#[default]`）。

## 功能点目的

### 核心功能
1. **权限限制告知**: 明确告知 AI 模型当前环境只允许读取文件
2. **安全边界定义**: 建立严格的写入保护，防止意外或恶意的文件修改
3. **网络状态提示**: 通过 `{network_access}` 占位符显示网络访问状态

### 设计意图
- **默认安全**: 作为默认沙箱模式，确保新用户或默认配置下具有最高安全性
- **最小权限原则**: 仅授予完成任务所需的最小权限（读取）
- **防止数据损坏**: 在探索性任务中防止意外修改代码库

## 具体技术实现

### 文件内容
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `read-only`: The sandbox only permits reading files. Network access is {network_access}.
```

### 关键流程

#### 1. 模板加载
```rust
// codex-rs/protocol/src/models.rs:489
const SANDBOX_MODE_READ_ONLY: &str = 
    include_str!("prompts/permissions/sandbox_mode/read_only.md");
```

#### 2. 指令生成
```rust
// codex-rs/protocol/src/models.rs:686-695
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::ReadOnly => SANDBOX_MODE_READ_ONLY.trim_end(),
        SandboxMode::WorkspaceWrite => SANDBOX_MODE_WORKSPACE_WRITE.trim_end(),
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
    };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

#### 3. 默认模式设置
```rust
// codex-rs/protocol/src/config_types.rs:57-60
pub enum SandboxMode {
    #[serde(rename = "read-only")]
    #[default]  // <-- 默认模式
    ReadOnly,
    // ...
}
```

### 数据结构

#### SandboxPolicy::ReadOnly 变体
```rust
// codex-rs/protocol/src/protocol.rs (相关定义)
SandboxPolicy::ReadOnly {
    access: ReadOnlyAccess,
    network_access: bool,
}
```

#### ReadOnlyAccess 枚举
```rust
pub enum ReadOnlyAccess {
    FullAccess,  // 可读取所有文件
    Restricted {
        include_platform_defaults: bool,
        readable_roots: Vec<AbsolutePathBuf>,
    },
}
```

## 关键代码路径与文件引用

### 直接引用
| 文件 | 行号 | 用途 |
|------|------|------|
| `codex-rs/protocol/src/models.rs` | 489 | 编译时嵌入模板 |
| `codex-rs/protocol/src/models.rs` | 690 | 模式匹配选择模板 |

### 默认配置
| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/protocol/src/config_types.rs` | 59 | `#[default]` 属性标记 |

### 策略转换
| 文件 | 函数/代码 | 说明 |
|------|-----------|------|
| `codex-rs/protocol/src/permissions.rs` | `FileSystemSandboxPolicy::from()` | 从 SandboxPolicy 转换 |
| `codex-rs/core/src/config/mod.rs` | 权限配置解析 | 加载用户配置的沙箱模式 |

### CLI 参数
| 文件 | 说明 |
|------|------|
| `codex-rs/utils/cli/src/sandbox_mode_cli_arg.rs` | `--sandbox read-only` 参数支持 |

## 依赖与外部交互

### 编译时依赖
- `include_str!` 宏编译时嵌入

### 运行时依赖
- `NetworkAccess` 状态注入
- `SandboxPolicy` 策略决策

### 数据流
```
用户配置/CLI ──▶ ConfigLoader ──▶ SandboxPolicy ──▶ 
DeveloperInstructions::from_policy() ──▶ sandbox_text() 
──▶ read_only.md 模板 ──▶ 替换 {network_access} ──▶ AI 提示
```

### 与文件系统沙箱的关联
```rust
// codex-rs/protocol/src/permissions.rs:712-753
impl From<&SandboxPolicy> for FileSystemSandboxPolicy {
    fn from(value: &SandboxPolicy) -> Self {
        match value {
            SandboxPolicy::ReadOnly { access, .. } => {
                let mut entries = Vec::new();
                match access {
                    ReadOnlyAccess::FullAccess => {
                        entries.push(FileSystemSandboxEntry {
                            path: FileSystemPath::Special {
                                value: FileSystemSpecialPath::Root,
                            },
                            access: FileSystemAccessMode::Read,
                        })
                    }
                    ReadOnlyAccess::Restricted { ... } => {
                        // 受限读取配置
                    }
                }
                FileSystemSandboxPolicy::restricted(entries)
            }
            // ...
        }
    }
}
```

## 风险、边界与改进建议

### 安全特性
1. **默认安全**: 作为默认模式，防止新用户意外暴露系统
2. **写入保护**: 完全禁止文件写入操作
3. **可组合性**: 可与网络代理、Seatbelt 等其他安全机制组合

### 使用限制
- **功能受限**: 无法执行需要文件写入的任务（如代码生成、日志写入）
- **临时文件**: 需要显式配置才能写入 `/tmp` 等临时目录
- **模型困惑**: AI 模型可能不理解为何写入操作失败

### 改进建议

#### 1. 增强提示信息
当前模板过于简略，建议增加：
```markdown
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `read-only`: The sandbox only permits reading files. 
Network access is {network_access}.

Note: File write operations will be blocked. To enable writes, switch to 
`workspace-write` mode or request permission for specific operations.
```

#### 2. 模型引导改进
建议在提示中增加对模型的引导：
```markdown
If you need to write files to complete the user's request, use the 
`request_permissions` tool to ask for elevated permissions.
```

#### 3. 错误信息优化
当写入被阻止时，系统应返回清晰的错误信息，帮助用户理解：
```
Write operation blocked: Running in read-only sandbox mode. 
Use `--sandbox workspace-write` or request permissions to enable writes.
```

#### 4. 与 request_permissions 工具集成
- 在 `read-only` 模式下，应更积极地提示使用 `request_permissions` 工具
- 参考 `on_request_rule_request_permission.md` 的实现方式

### 测试建议
```rust
// 建议增加的测试
#[test]
fn read_only_is_default_sandbox_mode() {
    assert_eq!(SandboxMode::default(), SandboxMode::ReadOnly);
}

#[test]
fn read_only_template_blocks_writes() {
    // 验证 FileSystemSandboxPolicy 正确阻止写入
}
```

### 配置示例
```toml
# ~/.codex/config.toml
[sandbox]
mode = "read-only"  # 显式设置（虽然已是默认）

# 可选：配置可读路径
[sandbox.read_only]
include_platform_defaults = true
readable_roots = ["/home/user/docs"]
```

### 相关模式对比
| 模式 | 读取 | 写入 | 适用场景 |
|------|------|------|----------|
| `read-only` | ✅ 全部/受限 | ❌ 禁止 | 代码审查、安全分析 |
| `workspace-write` | ✅ 全部 | ✅ 工作区 | 日常开发 |
| `danger-full-access` | ✅ 全部 | ✅ 全部 | 系统管理、特殊任务 |
