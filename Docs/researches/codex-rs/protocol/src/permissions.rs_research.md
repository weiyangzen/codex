# permissions.rs 研究文档

## 场景与职责

`permissions.rs` 是 Codex 协议库中的文件系统权限和沙箱策略核心模块，负责定义和管理文件系统访问控制策略。该模块实现了从旧版 `SandboxPolicy` 到新版 `FileSystemSandboxPolicy` 的迁移，提供了细粒度的文件系统访问控制，支持特殊路径、读写权限管理和沙箱策略转换。

**核心职责：**
- 定义文件系统访问模式（读/写/无）
- 实现文件系统沙箱策略（受限/无限制/外部沙箱）
- 支持特殊路径（Root、CWD、Tmpdir、ProjectRoots 等）
- 提供新旧沙箱策略的兼容转换
- 管理可写根目录及其只读子路径

## 功能点目的

### 1. 网络沙箱策略 (NetworkSandboxPolicy)

**目的：** 控制网络访问权限。

```rust
pub enum NetworkSandboxPolicy {
    Restricted,  // 默认：限制网络访问
    Enabled,     // 允许网络访问
}
```

### 2. 文件系统访问模式 (FileSystemAccessMode)

**目的：** 定义文件系统条目的访问级别，支持冲突解决优先级。

```rust
pub enum FileSystemAccessMode {
    Read,   // 只读
    Write,  // 读写
    None,   // 无访问（最高优先级）
}
```

**优先级规则：** `None > Write > Read`
- 当两个条目指向相同路径时，按此优先级解决冲突

### 3. 特殊路径系统 (FileSystemSpecialPath)

**目的：** 提供与具体文件系统位置无关的抽象路径引用。

```rust
pub enum FileSystemSpecialPath {
    Root,                       // 文件系统根目录
    Minimal,                    // 最小平台默认路径
    CurrentWorkingDirectory,    // 当前工作目录
    ProjectRoots { subpath: Option<PathBuf> },  // 项目根目录
    Tmpdir,                     // TMPDIR 环境变量路径
    SlashTmp,                   // /tmp 目录
    Unknown { path: String, subpath: Option<PathBuf> },  // 向前兼容
}
```

**向前兼容性设计：**
- `Unknown` 变体用于处理新版本引入的未知特殊路径
- 旧版本遇到未知路径时会忽略而不是报错
- 注释明确警告不要破坏向前兼容性（参考 Codex 0.112.0 的问题）

### 4. 文件系统沙箱策略 (FileSystemSandboxPolicy)

**目的：** 提供细粒度的文件系统访问控制。

```rust
pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,
    pub entries: Vec<FileSystemSandboxEntry>,
}

pub enum FileSystemSandboxKind {
    Restricted,       // 受限模式：基于条目列表
    Unrestricted,     // 无限制：完全访问
    ExternalSandbox,  // 外部沙箱：由外部系统管理
}
```

### 5. 可写根目录管理 (WritableRoot)

**目的：** 表示可写目录及其内部的只读子路径，用于保护敏感目录（如 `.git`、`.codex`）。

```rust
pub struct WritableRoot {
    pub root: AbsolutePathBuf,
    pub read_only_subpaths: Vec<AbsolutePathBuf>,
}
```

**默认只读子路径：**
- `.git` 目录（包括通过 gitdir 文件指向的外部 git 目录）
- `.agents` 目录
- `.codex` 目录

## 具体技术实现

### 路径解析系统

#### 特殊路径解析

```rust
fn resolve_file_system_special_path(
    value: &FileSystemSpecialPath,
    cwd: Option<&AbsolutePathBuf>,
) -> Option<AbsolutePathBuf> {
    match value {
        FileSystemSpecialPath::Root => None,  // Root 需要特殊处理
        FileSystemSpecialPath::CurrentWorkingDirectory => cwd.cloned(),
        FileSystemSpecialPath::ProjectRoots { subpath } => {
            // 解析相对于 cwd 的子路径
        }
        FileSystemSpecialPath::Tmpdir => {
            // 从 TMPDIR 环境变量解析
        }
        FileSystemSpecialPath::SlashTmp => {
            // 检查 /tmp 是否存在且为目录
        }
        // ...
    }
}
```

#### 条目优先级排序

```rust
fn resolved_entry_precedence(entry: &ResolvedFileSystemEntry) -> (usize, FileSystemAccessMode) {
    let specificity = entry.path.as_path().components().count();
    (specificity, entry.access)
}
```

- 路径组件越多（越具体），优先级越高
- 相同具体性时，按 `FileSystemAccessMode` 排序（None > Write > Read）

### 权限检查流程

#### `resolve_access_with_cwd`

```rust
pub fn resolve_access_with_cwd(&self, path: &Path, cwd: &Path) -> FileSystemAccessMode {
    // 1. 无限制或外部沙箱模式直接返回 Write
    // 2. 解析候选路径为绝对路径
    // 3. 过滤匹配该路径前缀的所有条目
    // 4. 按优先级排序，取最高优先级
    // 5. 默认返回 None
}
```

#### 完整磁盘访问检查

```rust
pub fn has_full_disk_read_access(&self) -> bool {
    match self.kind {
        FileSystemSandboxKind::Unrestricted | FileSystemSandboxKind::ExternalSandbox => true,
        FileSystemSandboxKind::Restricted => {
            self.has_root_access(FileSystemAccessMode::can_read)
                && !self.has_explicit_deny_entries()
        }
    }
}
```

### 新旧策略转换

#### 从旧版 SandboxPolicy 转换

```rust
impl From<&SandboxPolicy> for FileSystemSandboxPolicy {
    fn from(value: &SandboxPolicy) -> Self {
        match value {
            SandboxPolicy::DangerFullAccess => FileSystemSandboxPolicy::unrestricted(),
            SandboxPolicy::ExternalSandbox { .. } => FileSystemSandboxPolicy::external_sandbox(),
            SandboxPolicy::ReadOnly { access, .. } => { /* 构建受限条目 */ }
            SandboxPolicy::WorkspaceWrite { ... } => { /* 构建受限条目 */ }
        }
    }
}
```

#### 转换为旧版 SandboxPolicy

```rust
pub fn to_legacy_sandbox_policy(
    &self,
    network_policy: NetworkSandboxPolicy,
    cwd: &Path,
) -> io::Result<SandboxPolicy> {
    // 处理各种特殊情况，返回对应的旧版策略
    // 如果无法精确映射，返回错误
}
```

### 符号链接处理

```rust
fn normalize_effective_absolute_path(path: AbsolutePathBuf) -> AbsolutePathBuf {
    // 尝试对路径的每个祖先进行 canonicalize
    // 成功后拼接剩余部分
    // 失败则返回原路径
}
```

**符号链接保留策略：**
- 在可写根目录内保留符号链接的原始路径
- 确保下游沙箱（如 bwrap）可以正确屏蔽符号链接本身
- 处理指向根目录外部或根目录本身的符号链接

### Git 目录处理

```rust
fn default_read_only_subpaths_for_writable_root(
    writable_root: &AbsolutePathBuf,
) -> Vec<AbsolutePathBuf> {
    // 1. 检查 .git 是目录还是文件
    // 2. 如果是文件，解析 gitdir 指针
    // 3. 添加 .agents 和 .codex 目录
}
```

**Git 工作树支持：**
- 处理普通仓库（.git 目录）
- 处理 worktree/submodule（.git 文件包含 gitdir 指针）
- 处理裸仓库

## 关键代码路径与文件引用

### 本文件关键代码

| 行号 | 内容 | 说明 |
|------|------|------|
| 20-29 | `NetworkSandboxPolicy` | 网络沙箱策略枚举 |
| 42-62 | `FileSystemAccessMode` | 文件系统访问模式 |
| 74-102 | `FileSystemSpecialPath` | 特殊路径枚举 |
| 117-140 | `FileSystemSandboxPolicy` | 主沙箱策略结构 |
| 180-306 | `FileSystemSandboxPolicy` 方法 | 核心权限检查方法 |
| 322-340 | `resolve_access_with_cwd` | 路径权限解析 |
| 350-366 | `needs_direct_runtime_enforcement` | 运行时强制检查 |
| 387-486 | `get_writable_roots_with_cwd` | 可写根目录计算 |
| 513-673 | `to_legacy_sandbox_policy` | 旧版策略转换 |
| 712-824 | `From<&SandboxPolicy>` | 从旧版转换 |
| 827-930 | 路径解析辅助函数 | 特殊路径解析、目标匹配 |
| 932-937 | `resolved_entry_precedence` | 条目优先级排序 |
| 990-1007 | `dedup_absolute_paths` | 路径去重 |
| 1009-1025 | `normalize_effective_absolute_path` | 符号链接规范化 |
| 1027-1061 | `default_read_only_subpaths_for_writable_root` | 默认只读子路径 |
| 1063-1126 | Git 指针文件处理 | gitdir 解析 |

### 依赖关系

**本文件导入：**
```rust
use codex_utils_absolute_path::AbsolutePathBuf;
use crate::protocol::NetworkAccess;
use crate::protocol::ReadOnlyAccess;
use crate::protocol::SandboxPolicy;
use crate::protocol::WritableRoot;
```

**被导入方：**
- `protocol.rs`: 重新导出主要类型
- `core/src/tools/handlers/unified_exec.rs`: 执行工具
- `core/src/guardian/`:  Guardian 审批系统

### 调用路径示例

```
FileSystemSandboxPolicy::resolve_access_with_cwd(path, cwd)
    └── resolve_candidate_path(path, cwd)  // 解析为绝对路径
    └── resolved_entries_with_cwd(cwd)      // 获取所有解析后的条目
        └── resolve_entry_path(entry.path, cwd_absolute)  // 解析每个条目
    └── filter + max_by_key(resolved_entry_precedence)  // 找最匹配的
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_utils_absolute_path` | 绝对路径类型 |
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `strum_macros` | 枚举显示 trait |
| `tracing` | 日志记录 |
| `ts_rs` | TypeScript 类型生成 |

### 内部模块依赖

- `protocol.rs`: `NetworkAccess`, `ReadOnlyAccess`, `SandboxPolicy`, `WritableRoot`

## 风险、边界与改进建议

### 已知风险

1. **向前兼容性**
   - 风险：新增特殊路径类型可能导致旧版本拒绝配置
   - 缓解：`Unknown` 变体处理未知路径，但旧版本仍需更新才能识别新语义

2. **符号链接竞争条件**
   - 风险：路径检查和实际访问之间符号链接目标可能改变
   - 缓解：这是 TOCTOU 问题的固有限制，需要下游沙箱配合

3. **Git 指针文件解析失败**
   - 风险：格式不正确或指向不存在的路径
   - 缓解：记录错误日志并优雅降级

4. **路径规范化性能**
   - 风险：`normalize_effective_absolute_path` 对每个祖先调用 `canonicalize`
   - 影响：可能产生多次系统调用

### 边界条件

| 场景 | 行为 |
|------|------|
| 空条目列表 | 默认拒绝所有访问（Restricted 模式） |
| 冲突条目 | 按 specificity + access 优先级解决 |
| 相对路径 | 必须提供 cwd 进行解析 |
| 不存在的路径 | 解析失败，返回 None 访问 |
| 循环符号链接 | `canonicalize` 会返回错误 |
| TMPDIR 未设置 | `Tmpdir` 特殊路径解析为 None |

### 测试覆盖

当前测试包括（约 40 个测试用例）：
- `unknown_special_paths_are_ignored_by_legacy_bridge`: 向前兼容
- `effective_runtime_roots_canonicalize_symlinked_paths`: 符号链接处理
- `current_working_directory_special_path_canonicalizes_symlinked_cwd`: CWD 规范化
- `writable_roots_preserve_symlinked_protected_subpaths`: 符号链接保护
- `resolve_access_with_cwd_uses_most_specific_entry`: 优先级规则
- `split_only_nested_carveouts_need_direct_runtime_enforcement`: 运行时强制

### 改进建议

1. **缓存优化**
   - 缓存 `resolved_entries_with_cwd` 结果
   - 缓存路径规范化结果

2. **错误处理增强**
   - 为 `to_legacy_sandbox_policy` 提供更详细的错误信息
   - 区分配置错误和系统错误

3. **配置验证**
   - 添加 `validate()` 方法检查配置一致性
   - 检测明显错误的配置（如 Write 和 None 冲突）

4. **审计日志**
   - 记录权限决策原因
   - 帮助调试访问被拒绝问题

5. **性能分析**
   - 测量大规模条目列表的性能
   - 考虑使用更高效的数据结构（如 trie）

6. **文档完善**
   - 添加更多使用示例
   - 记录常见配置模式
