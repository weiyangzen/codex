# Approval Overlay Additional Permissions Prompt Snapshot 研究文档

## 场景与职责

此快照文件是 `codex_tui` crate 中 `approval_overlay` 模块的测试快照，用于验证 **Approval Overlay** 在执行命令需要额外文件系统权限时的 UI 渲染输出。这是 Codex TUI 安全模型的关键组件，负责向用户透明展示命令执行所需的文件访问权限。

### 业务场景
- 当 Codex 需要执行涉及文件系统访问的命令时触发（如读取配置文件、写入输出文件）
- 作为命令执行审批流程的一部分，在标准执行审批之上叠加额外的权限请求
- 支持网络访问和文件系统读写的组合权限展示

### 与 macOS 权限提示的区别
| 维度 | Additional Permissions (通用) | Additional Permissions (macOS) |
|------|------------------------------|-------------------------------|
| 权限类型 | 文件系统、网络 | macOS 系统权限 |
| 权限格式 | `read /path`, `write /path` | `macOS preferences readwrite` |
| 适用平台 | 所有平台 | 仅 macOS |
| 权限来源 | `PermissionProfile.file_system` | `PermissionProfile.macos` |

## 功能点目的

### 核心功能
1. **文件权限透明化**：清晰展示命令需要访问的文件路径和权限类型
2. **路径规范化**：显示绝对路径，避免相对路径的歧义
3. **分级授权**：支持"仅一次"、"会话内允许"等多种授权级别
4. **安全决策**：用户可查看具体文件路径后做出知情决策

### UI 元素（从快照可见）
```
Would you like to run the following command?

Reason: need filesystem access

Permission rule: network; read `/tmp/readme.txt`; write `/tmp/out.txt`

$ cat /tmp/readme.txt

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### 权限规则格式
```
network                          # 网络访问权限
read `/tmp/readme.txt`           # 读取特定文件
write `/tmp/out.txt`             # 写入特定文件
```

## 具体技术实现

### 关键数据结构

```rust
// PermissionProfile 结构（简化）
pub struct PermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,  // 文件权限来源
    pub macos: Option<MacOsSeatbeltProfileExtensions>,
}

pub struct FileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,   // 可读路径列表
    pub write: Option<Vec<AbsolutePathBuf>>,  // 可写路径列表
}

pub struct NetworkPermissions {
    pub enabled: Option<bool>,
}
```

### 权限规则格式化

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
        // 读取权限
        if let Some(read) = file_system.read.as_ref() {
            let reads = read
                .iter()
                .map(|path| format!("`{}`", path.display()))  // 反引号包裹路径
                .collect::<Vec<_>>()
                .join(", ");
            parts.push(format!("read {reads}"));
        }
        
        // 写入权限
        if let Some(write) = file_system.write.as_ref() {
            let writes = write
                .iter()
                .map(|path| format!("`{}`", path.display()))
                .collect::<Vec<_>>()
                .join(", ");
            parts.push(format!("write {writes}"));
        }
    }
    
    // macOS 权限（见 macOS 快照文档）
    if let Some(macos) = additional_permissions.macos.as_ref() { ... }
    
    if parts.is_empty() { None } else { Some(parts.join("; ")) }
}
```

### 路径规范化

```rust
// 测试中使用 AbsolutePathBuf 确保路径一致性
fn absolute_path(path: &str) -> AbsolutePathBuf {
    AbsolutePathBuf::from_absolute_path(path).expect("absolute path")
}

// 快照测试中路径被规范化为 /tmp/readme.txt
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

### 决策处理

```rust
fn handle_exec_decision(&self, id: &str, command: &[String], decision: ReviewDecision) {
    // 记录到历史单元格
    if request.thread_label().is_none() {
        let cell = history_cell::new_approval_decision_cell(
            command.to_vec(),
            decision.clone(),
            history_cell::ApprovalDecisionActor::User,
        );
        self.app_event_tx.send(AppEvent::InsertHistoryCell(cell));
    }
    
    // 发送审批决策到后端
    let thread_id = request.thread_id();
    self.app_event_tx.send(AppEvent::SubmitThreadOp {
        thread_id,
        op: Op::ExecApproval {
            id: id.to_string(),
            turn_id: None,
            decision,
        },
    });
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:750-827` | `format_additional_permissions_rule` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:1318-1394` | 额外权限提示快照测试 |
| `codex-protocol/src/models.rs` | `FileSystemPermissions` 定义 |
| `codex-utils/absolute-path/src/lib.rs` | `AbsolutePathBuf` 实现 |

### 相关测试用例

```rust
#[test]
fn additional_permissions_prompt_snapshot() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let exec_request = ApprovalRequest::Exec {
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
    };

    let view = ApprovalOverlay::new(exec_request, tx, Features::with_defaults());
    assert_snapshot!(
        "approval_overlay_additional_permissions_prompt",
        normalize_snapshot_paths(render_overlay_lines(&view, 120))
    );
}
```

## 依赖与外部交互

### 路径处理依赖

```rust
// codex-utils/absolute-path/src/lib.rs
pub struct AbsolutePathBuf(PathBuf);

impl AbsolutePathBuf {
    pub fn from_absolute_path(path: impl AsRef<Path>) -> Result<Self, Error> {
        // 确保路径是绝对路径
        let path = path.as_ref();
        if path.is_absolute() {
            Ok(Self(path.to_path_buf()))
        } else {
            Err(Error::NotAbsolute)
        }
    }
}
```

### 事件交互

| 事件 | 方向 | 触发条件 |
|------|------|---------|
| `AppEvent::SubmitThreadOp { op: Op::ExecApproval }` | TUI → 后端 | 用户做出决策 |
| `AppEvent::InsertHistoryCell` | TUI → 历史系统 | 记录审批决策 |

### 历史单元格格式

```rust
// 审批决策历史单元格示例
"✔ You approved codex to run"
"  cat /tmp/readme.txt this time"
```

## 风险、边界与改进建议

### 安全边界

1. **路径遍历风险**:
   - 需要验证路径不包含 `..` 等 traversal 组件
   - 符号链接可能被利用访问未授权文件

2. **权限范围**:
   - 当前实现显示具体路径，但用户可能不理解路径含义
   - 建议添加路径类型标识（如系统文件、用户文件、临时文件）

3. **权限组合**:
   - `network` + `write` 组合可能被用于数据外泄
   - 建议对高风险组合添加额外警告

### 已知限制

1. **路径长度**: 长路径可能导致权限规则行过长，需要换行处理
2. **路径可读性**: 绝对路径可能包含冗长的 home 目录路径
3. **动态路径**: 某些命令可能访问运行时确定的动态路径

### 改进建议

1. **路径分类显示**:
   ```rust
   enum PathCategory {
       System,      // /etc, /usr, etc.
       UserData,    // ~/Documents, ~/Downloads, etc.
       Project,     // 当前工作目录下的文件
       Temporary,   // /tmp, /var/tmp, etc.
   }
   ```

2. **路径别名**: 将长路径显示为别名，如 `~` 代替 `/home/username`

3. **权限预览**: 显示如果授予权限，命令将执行的具体操作

4. **批量权限管理**: 允许用户一次性查看和撤销多个已授予的权限

5. **路径验证**: 在显示前验证路径是否存在、是否可访问

```rust
// 建议添加路径验证
fn validate_paths(permissions: &FileSystemPermissions) -> Vec<PathValidationResult> {
    let mut results = Vec::new();
    for path in permissions.read.iter().flatten() {
        results.push(PathValidationResult {
            path: path.clone(),
            exists: path.exists(),
            readable: path.readable(),
            category: categorize_path(path),
        });
    }
    results
}
```
