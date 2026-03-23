# policy.rs 深度研究文档

## 场景与职责

`policy.rs` 是 Windows Sandbox 模块中的**策略解析器**，负责将字符串形式的策略描述转换为结构化的 `SandboxPolicy` 类型。它是沙箱安全模型的入口点，决定了沙箱的权限边界。

### 核心职责
1. **策略字符串解析**：支持预设名称和 JSON 格式
2. **策略验证**：拒绝不支持的策略类型
3. **策略创建**：提供标准策略的便捷构造方式

## 功能点目的

### 1. `parse_policy` - 策略解析主函数
```rust
pub fn parse_policy(value: &str) -> Result<SandboxPolicy>
```

**支持的输入格式**：

| 输入 | 解析结果 |
|------|----------|
| `"read-only"` | `SandboxPolicy::new_read_only_policy()` |
| `"workspace-write"` | `SandboxPolicy::new_workspace_write_policy()` |
| `"danger-full-access"` | 错误（不支持） |
| `"external-sandbox"` | 错误（不支持） |
| JSON 字符串 | 反序列化为对应的策略变体 |

**验证逻辑**：
- 显式拒绝 `DangerFullAccess` 和 `ExternalSandbox` 策略
- 这些策略在 Windows 沙箱中不被支持，因为它们绕过安全限制

### 2. 策略类型定义
策略类型定义在 `codex_protocol::protocol::SandboxPolicy` 中：

```rust
pub enum SandboxPolicy {
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    WorkspaceWrite { writable_roots: Vec<AbsolutePathBuf>, read_only_access: ReadOnlyAccess, network_access: bool, ... },
    DangerFullAccess,
    ExternalSandbox { network_access: NetworkAccess },
}
```

### 3. 标准策略构造

#### `new_read_only_policy`
- 只读访问权限
- 默认包含平台默认路径
- 无网络访问

#### `new_workspace_write_policy`
- 工作区写权限
- 可配置额外可写根目录
- 可配置网络访问

## 具体技术实现

### 解析流程
```rust
pub fn parse_policy(value: &str) -> Result<SandboxPolicy> {
    match value {
        "read-only" => Ok(SandboxPolicy::new_read_only_policy()),
        "workspace-write" => Ok(SandboxPolicy::new_workspace_write_policy()),
        "danger-full-access" | "external-sandbox" => anyhow::bail!(...),
        other => {
            let parsed: SandboxPolicy = serde_json::from_str(other)?;
            // 验证解析后的策略
            if matches!(parsed, SandboxPolicy::DangerFullAccess | SandboxPolicy::ExternalSandbox { .. }) {
                anyhow::bail!(...)
            }
            Ok(parsed)
        }
    }
}
```

### 错误处理
- 使用 `anyhow::bail!` 创建描述性错误
- JSON 解析错误通过 `?` 传播
- 明确的错误消息帮助用户理解策略限制

## 关键代码路径与文件引用

### 内部依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `SandboxPolicy` | `codex_protocol::protocol` | 策略类型定义 |

### 被调用方
| 调用方 | 场景 |
|--------|------|
| `lib.rs` (`run_windows_sandbox_capture`) | 解析传入的策略参数 |
| `elevated_impl.rs` | 解析策略用于提权执行 |
| 外部使用者 | 通过 `pub use policy::parse_policy` 导出 |

### 导出接口
```rust
#[cfg(target_os = "windows")]
pub use policy::parse_policy;
#[cfg(target_os = "windows")]
pub use policy::SandboxPolicy;
```

## 依赖与外部交互

### 外部 Crate
- `anyhow`：错误处理和传播
- `serde_json`：JSON 策略解析
- `codex_protocol`：策略类型定义

### 协议依赖
策略结构定义在 `codex_protocol` crate 中，包含：
- `SandboxPolicy`：主策略枚举
- `ReadOnlyAccess`：只读访问配置
- `NetworkAccess`：网络访问配置
- `AbsolutePathBuf`：绝对路径类型

## 风险、边界与改进建议

### 已知风险

1. **策略绕过风险**
   - 问题：`DangerFullAccess` 和 `ExternalSandbox` 被显式拒绝
   - 原因：这些策略授予过多权限，破坏沙箱隔离
   - 缓解：解析时拒绝，运行时再次检查

2. **JSON 注入**
   - 问题：接受任意 JSON 字符串解析
   - 风险：可能导致反序列化问题
   - 缓解：使用强类型反序列化，验证解析结果

3. **策略混淆**
   - 问题：预设名称和 JSON 格式混合
   - 风险：用户可能误用
   - 缓解：清晰的文档和错误消息

### 边界条件

1. **空字符串**：JSON 解析失败，返回错误
2. **无效 JSON**：`serde_json::from_str` 返回解析错误
3. **未知预设名称**：作为 JSON 尝试解析
4. **大小写敏感**：预设名称区分大小写（`"Read-Only"` 不被识别）

### 改进建议

1. **更多预设策略**
   - 当前：仅 `read-only` 和 `workspace-write`
   - 建议：添加 `network-only`、`restricted-shell` 等预设

2. **策略验证增强**
   - 当前：仅检查策略类型
   - 建议：验证路径有效性、检查冲突配置

3. **策略文档生成**
   - 建议：从代码生成策略文档和示例

4. **交互式策略构建器**
   - 建议：提供 CLI 工具帮助用户构建有效策略

5. **策略版本控制**
   - 建议：在策略中嵌入版本信息，支持迁移

### 测试覆盖

模块包含以下单元测试：
- `rejects_external_sandbox_preset`：验证预设拒绝
- `rejects_external_sandbox_json`：验证 JSON 拒绝
- `parses_read_only_policy`：验证预设解析

### 安全考虑

1. **白名单策略**
   - 采用白名单方式，仅允许已知安全的策略
   - 新策略需要显式添加支持

2. **防御性编程**
   - 即使解析成功，也再次验证策略类型
   - 防止协议更新引入不安全的策略变体

3. **最小权限原则**
   - 默认策略（`read-only`）授予最小权限
   - 需要显式选择更宽松的策略

### 使用示例

```rust
// 使用预设
let policy = parse_policy("read-only")?;

// 使用 JSON
let json = r#"{"WorkspaceWrite":{"writable_roots":[],"network_access":false}}"#;
let policy = parse_policy(json)?;

// 错误示例
let result = parse_policy("danger-full-access");
assert!(result.is_err());  // 被拒绝
```

### 策略对比

| 策略 | 读权限 | 写权限 | 网络 | 适用场景 |
|------|--------|--------|------|----------|
| `read-only` | 受限 | 无 | 无 | 安全分析、代码审查 |
| `workspace-write` | 受限 | 工作区 | 可选 | 开发、构建 |
| `danger-full-access` | 全部 | 全部 | 是 | **不支持** |
| `external-sandbox` | 外部决定 | 外部决定 | 可选 | **不支持** |
