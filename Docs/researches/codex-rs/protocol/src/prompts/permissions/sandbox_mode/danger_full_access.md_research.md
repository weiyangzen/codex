# danger_full_access.md 研究文档

## 场景与职责

`danger_full_access.md` 是 Codex CLI 中用于描述 **最宽松沙箱模式** 的提示模板文件。当系统配置为 `danger-full-access` 模式时，该文件内容会被注入到模型的开发者指令(developer instructions)中，告知 AI 模型当前执行环境拥有完全的文件系统访问权限。

该文件属于权限提示系统的一部分，位于 `codex-rs/protocol/src/prompts/permissions/sandbox_mode/` 目录下，与 `read_only.md` 和 `workspace_write.md` 共同构成完整的沙箱模式说明体系。

## 功能点目的

### 核心功能
1. **权限告知**: 向 AI 模型明确说明当前文件系统沙箱处于完全开放状态
2. **网络状态提示**: 通过 `{network_access}` 占位符动态插入网络访问状态信息
3. **安全边界定义**: 明确告知模型"无文件系统沙箱限制 - 所有命令都被允许"

### 设计意图
- **透明性**: 让模型清楚了解自身运行环境的权限边界
- **一致性**: 使用统一的模板格式，便于维护和国际化
- **动态性**: 通过占位符支持运行时网络状态的动态注入

## 具体技术实现

### 文件内容
```markdown
Filesystem sandboxing defines which files can be read or written. `sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. Network access is {network_access}.
```

### 关键流程

#### 1. 模板加载流程
```rust
// codex-rs/protocol/src/models.rs:485-489
const SANDBOX_MODE_DANGER_FULL_ACCESS: &str =
    include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
```

编译时通过 `include_str!` 宏将文件内容嵌入到二进制中，避免运行时文件读取开销。

#### 2. 指令生成流程
```rust
// codex-rs/protocol/src/models.rs:686-695
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
        // ...
    };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

#### 3. 调用链
```
DeveloperInstructions::from_policy()
  └── DeveloperInstructions::from_permissions_with_network()
        └── DeveloperInstructions::sandbox_text()
              └── 使用 SANDBOX_MODE_DANGER_FULL_ACCESS 模板
```

### 数据结构

#### SandboxMode 枚举
```rust
// codex-rs/protocol/src/config_types.rs:52-67
#[derive(...)]
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

#### NetworkAccess 枚举
```rust
// codex-rs/protocol/src/protocol.rs
pub enum NetworkAccess {
    Enabled,
    Restricted,
}
```

## 关键代码路径与文件引用

### 直接引用
| 文件 | 行号 | 用途 |
|------|------|------|
| `codex-rs/protocol/src/models.rs` | 485-486 | 编译时嵌入模板内容 |
| `codex-rs/protocol/src/models.rs` | 688 | 模式匹配时选择模板 |

### 相关配置类型
| 文件 | 说明 |
|------|------|
| `codex-rs/protocol/src/config_types.rs` | `SandboxMode` 枚举定义 |
| `codex-rs/utils/cli/src/sandbox_mode_cli_arg.rs` | CLI 参数映射 |

### 调用方
| 文件 | 函数 | 说明 |
|------|------|------|
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::from_policy()` | 从策略生成指令 |
| `codex-rs/protocol/src/models.rs` | `DeveloperInstructions::sandbox_text()` | 构建沙箱文本 |

### 配置关联
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/config/mod.rs` | 配置加载与权限解析 |
| `codex-rs/core/src/sandboxing/mod.rs` | 沙箱执行实现 |

## 依赖与外部交互

### 编译时依赖
- **Rust `include_str!` 宏**: 将 Markdown 文件内容嵌入编译后的二进制

### 运行时依赖
- **NetworkAccess 状态**: 通过字符串替换注入网络访问状态
- **SandboxPolicy**: 上层策略决定使用哪个沙箱模式模板

### 与其他模块的交互
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   CLI 参数解析   │────▶│  SandboxMode     │────▶│  提示模板选择    │
│   (CLI Arg)     │     │  (Config Types)  │     │  (models.rs)    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                                                          ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   AI 模型       │◀────│ DeveloperInstructions│◀──│ 模板内容注入    │
│   (OpenAI API)  │     │  (Developer Role)  │     │ (danger_full_   │
└─────────────────┘     └──────────────────┘     │   access.md)    │
                                                  └─────────────────┘
```

## 风险、边界与改进建议

### 安全风险
1. **权限过度宽松**: `danger-full-access` 模式完全禁用文件系统沙箱，允许读写任意路径
2. **命令执行风险**: 所有 shell 命令都被允许执行，无额外限制
3. **网络访问**: 虽然模板显示网络状态，但实际网络控制由 `NetworkAccess` 独立管理

### 使用边界
- **适用场景**: 受信任的本地开发环境、CI/CD 管道、容器化环境
- **禁用场景**: 多租户环境、处理敏感数据的场景、不可信代码执行

### 改进建议

#### 1. 安全增强
```markdown
# 建议增加警告提示
⚠️ WARNING: Running in danger-full-access mode. All filesystem operations 
are permitted. Use with caution in production environments.
```

#### 2. 审计日志
- 建议在进入 `danger-full-access` 模式时记录审计日志
- 可在 `codex-rs/core/src/config/mod.rs` 的权限初始化阶段添加

#### 3. 配置验证
- 建议增加配置校验，当检测到 `danger-full-access` 模式时发出警告
- 参考 `codex-rs/core/src/config/mod.rs` 中的 `startup_warnings` 机制

#### 4. 文档完善
- 当前模板仅有一行描述，建议增加：
  - 安全风险说明
  - 推荐使用场景
  - 如何切换到更安全的模式

### 测试覆盖
建议增加以下测试（参考 `codex-rs/protocol/src/models.rs` 中的测试模式）：
```rust
#[test]
fn danger_full_access_template_renders_correctly() {
    let instructions = DeveloperInstructions::sandbox_text(
        SandboxMode::DangerFullAccess, 
        NetworkAccess::Enabled
    );
    assert!(instructions.text.contains("danger-full-access"));
    assert!(instructions.text.contains("Enabled"));
}
```

### 相关配置项
| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `sandbox.mode` | 沙箱模式选择 | `read-only` |
| `permissions.sandbox_policy` | 详细沙箱策略 | 根据模式推导 |
| `features.strict_sandbox` | 严格沙箱开关 | `false` |
