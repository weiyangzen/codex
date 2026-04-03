# Approval Overlay Additional Permissions Prompt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `approval_overlay.rs` 模块的测试快照，用于验证**额外权限请求的审批覆盖层**的渲染输出。当 Codex 需要超出默认沙盒限制的权限（如文件系统访问、网络访问）时，向用户展示此界面。

### 业务场景
- 读取或写入特定文件/目录
- 访问网络资源
- 组合权限请求（如同时需要文件读取和网络访问）

### 权限规则展示
该快照展示了以下权限组合：
- `network` - 网络访问
- `read "/tmp/readme.txt"` - 读取特定文件
- `write "/tmp/out.txt"` - 写入特定文件

## 功能点目的

### 核心功能
1. **命令预览**：展示将要执行的命令（`$ cat /tmp/readme.txt`）
2. **权限规则展示**：清晰列出所有请求的权限
3. **理由说明**：解释为什么需要这些权限（"need filesystem access"）
4. **用户决策**：提供批准或拒绝的选项

### 安全设计目标
- **透明度**：用户必须明确知道哪些资源将被访问
- **最小权限**：只请求完成任务所需的具体文件和网络资源
- **可追溯性**：所有权限请求都有理由说明

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,  // 额外权限在这里
    },
    // ... 其他变体
}

pub struct PermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
    pub macos: Option<MacOsSeatbeltProfileExtensions>,
}

pub struct FileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}

pub struct NetworkPermissions {
    pub enabled: Option<bool>,
}
```

### 权限格式化
```rust
pub(crate) fn format_additional_permissions_rule(
    additional_permissions: &PermissionProfile,
) -> Option<String> {
    let mut parts = Vec::new();
    
    // 网络权限
    if additional_permissions
        .network
        .as_ref()
        .and_then(|network| network.enabled)
        .unwrap_or(false)
    {
        parts.push("network".to_string());
    }
    
    // 文件系统权限
    if let Some(file_system) = additional_permissions.file_system.as_ref() {
        if let Some(read) = file_system.read.as_ref() {
            let reads = read
                .iter()
                .map(|path| format!("`{}`", path.display()))
                .collect::<Vec<_>>()
                .join(", ");
            parts.push(format!("read {reads}"));
        }
        if let Some(write) = file_system.write.as_ref() {
            let writes = write
                .iter()
                .map(|path| format!("`{}`", path.display()))
                .collect::<Vec<_>>()
                .join(", ");
            parts.push(format!("write {writes}"));
        }
    }
    
    // macOS 权限（见 macOS prompt 文档）
    // ...
    
    Some(parts.join("; "))
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- **测试函数**: `additional_permissions_prompt_snapshot` (行 1351-1380)
- **权限格式化**: `format_additional_permissions_rule` (行 736-813)

### 测试参数
```rust
ApprovalRequest::Exec {
    thread_id: ThreadId::new(),
    thread_label: None,
    id: "test".into(),
    command: vec!["cat".into(), "/tmp/readme.txt".into()],
    reason: Some("need filesystem access".into()),
    available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
    network_approval_context: None,
    additional_permissions: Some(PermissionProfile {
        network: Some(NetworkPermissions {
            enabled: Some(true),
        }),
        file_system: Some(FileSystemPermissions {
            read: Some(vec![absolute_path("/tmp/readme.txt")]),
            write: Some(vec![absolute_path("/tmp/out.txt")]),
        }),
        ..Default::default()
    }),
}
```

### 路径规范化
测试中使用了 `normalize_snapshot_paths` 函数处理路径差异：
```rust
fn normalize_snapshot_paths(rendered: String) -> String {
    [
        (absolute_path("/tmp/readme.txt"), "/tmp/readme.txt"),
        (absolute_path("/tmp/out.txt"), "/tmp/out.txt"),
    ]
    .into_iter()
    .fold(rendered, |rendered, (path, normalized)| {
        rendered.replace(&path.display().to_string(), normalized)
    })
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::models::PermissionProfile` - 权限配置模型
- `codex_protocol::models::FileSystemPermissions` - 文件系统权限
- `codex_protocol::models::NetworkPermissions` - 网络权限
- `codex_utils_absolute_path::AbsolutePathBuf` - 绝对路径类型

### 外部交互
- **Seatbelt/Sandbox**: 实际执行权限控制
- **文件系统**: 验证路径存在性和可访问性
- **网络栈**: 控制出站连接

## 风险、边界与改进建议

### 潜在风险
1. **路径遍历攻击**: 需要验证请求的路径不包含 `..` 等遍历组件
2. **符号链接攻击**: 需要处理符号链接指向敏感文件的情况
3. **权限升级**: 批准的权限可能被用于非预期目的

### 边界情况
1. **长路径**: 非常长的文件路径可能导致权限规则行溢出
2. **大量路径**: 大量读写路径可能导致显示混乱
3. **不存在的路径**: 请求访问不存在的文件时的处理
4. **相对路径**: 测试中使用了绝对路径，但相对路径的处理需要验证

### 改进建议
1. **路径验证**: 添加路径规范化验证，防止路径遍历
2. **权限预览**: 显示权限的实际影响（如"这将允许读取您的 SSH 私钥"）
3. **目录 vs 文件**: 区分目录和文件的权限请求
4. **通配符支持**: 考虑支持 `*` 通配符（如 `read ~/.config/*`）
5. **权限继承**: 考虑子目录的权限继承规则

### 测试覆盖
- 额外权限提示: `additional_permissions_prompt_snapshot`
- 权限规则行显示: `additional_permissions_prompt_shows_permission_rule_line`
- macOS 权限: `additional_permissions_macos_prompt_snapshot`

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- 路径工具: `codex-rs/utils/absolute_path/src/lib.rs`
