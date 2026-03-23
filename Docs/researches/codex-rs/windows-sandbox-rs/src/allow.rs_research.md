# allow.rs 研究文档

## 场景与职责

`allow.rs` 负责根据沙箱策略计算允许和拒绝访问的文件路径集合。它是沙箱权限策略与实际文件系统 ACL 操作之间的桥梁，将高层次的 `SandboxPolicy` 转换为具体的 `AllowDenyPaths` 路径列表。

该模块在以下场景中使用：
- 沙箱启动前计算需要设置 ACL 的路径集合
- 确定工作区写入策略下的可写根目录
- 识别需要特殊保护的敏感子目录（`.git`, `.codex`, `.agents`）
- 处理临时目录环境变量（TEMP/TMP）的包含/排除

## 功能点目的

### 1. 路径分类数据结构
- **`AllowDenyPaths`**: 包含 `allow` 和 `deny` 两个 `HashSet<PathBuf>`
- 明确区分需要允许访问和明确拒绝访问的路径

### 2. 策略到路径的转换
- **`compute_allow_paths`**: 核心函数，将 `SandboxPolicy` 转换为路径集合
- 处理策略中的 `writable_roots` 扩展可写目录
- 根据 `exclude_tmpdir_env_var` 控制临时目录包含

### 3. 受保护子目录识别
- 自动识别工作区中的 `.git`, `.codex`, `.agents` 目录
- 将这些敏感目录加入 `deny` 集合，防止沙箱进程修改

### 4. 路径规范化
- 使用 `dunce::canonicalize` 处理相对路径和符号链接
- 确保路径比较的一致性

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Default, PartialEq, Eq)]
pub struct AllowDenyPaths {
    pub allow: HashSet<PathBuf>,   // 允许访问的路径
    pub deny: HashSet<PathBuf>,    // 拒绝写入的路径
}
```

### 核心算法流程

```
compute_allow_paths(policy, policy_cwd, command_cwd, env_map)
  └─> 初始化 allow/deny HashSet
  └─> 如果策略是 WorkspaceWrite:
  │     └─> add_writable_root(command_cwd)
  │     │     └─> 规范化路径 (canonicalize)
  │     │     └─> 加入 allow
  │     │     └─> 检查 protected_subdirs [.git, .codex, .agents]
  │     │           存在则加入 deny
  │     └─> 遍历 writable_roots，对每个根目录执行 add_writable_root
  └─> 如果 include_tmp_env_vars:
  │     └─> 检查 env_map 和 std::env 中的 TEMP/TMP
  │     └─> 存在的路径加入 allow
  └─> 返回 AllowDenyPaths { allow, deny }
```

### 策略匹配逻辑

```rust
let include_tmp_env_vars = matches!(
    policy,
    SandboxPolicy::WorkspaceWrite {
        exclude_tmpdir_env_var: false,
        ..
    }
);
```

只有 `WorkspaceWrite` 策略且 `exclude_tmpdir_env_var: false` 时才包含临时目录。

### 路径处理逻辑

```rust
let candidate = if root.is_absolute() {
    root
} else {
    policy_cwd.join(root)  // 相对路径基于策略 CWD 解析
};
let canonical = canonicalize(&candidate).unwrap_or(candidate);
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 用途 |
|--------|------|
| `lib.rs` (windows_impl) | `run_windows_sandbox_capture` 和 `run_windows_sandbox_legacy_preflight` |
| `elevated_impl.rs` | `run_windows_sandbox_capture` |
| `setup_orchestrator.rs` | `gather_write_roots` 内部使用 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/allow.rs
  ├─> 依赖: policy.rs (SandboxPolicy)
  ├─> 依赖: dunce (canonicalize)
  ├─> 被 lib.rs 公开导出: compute_allow_paths, AllowDenyPaths
  └─> 被 elevated_impl.rs 使用
```

### 依赖模块

```rust
use crate::policy::SandboxPolicy;  // 策略定义
use dunce::canonicalize;            // 路径规范化
```

## 依赖与外部交互

### 内部依赖
- **`policy.rs`**: `SandboxPolicy` 枚举定义

### 外部依赖
- **dunce**: Windows 友好的路径规范化（处理 UNC 路径前缀）
- **std::collections::HashSet/HashMap**: 路径集合管理

### 环境交互
- 读取 `std::env::var("TEMP")` 和 `std::env::var("TMP")`
- 检查路径 `exists()` 状态

### 策略配置

| 策略字段 | 影响 |
|----------|------|
| `writable_roots: Vec<AbsolutePathBuf>` | 额外的可写根目录 |
| `exclude_tmpdir_env_var: bool` | 是否排除 TEMP/TMP 目录 |
| `read_only_access` | 不影响 allow.rs（在别处处理） |
| `network_access` | 不影响 allow.rs（在别处处理） |

## 风险、边界与改进建议

### 安全风险

1. **路径遍历风险**
   - 当前实现使用 `canonicalize` 解析符号链接
   - 但 `exists()` 检查与后续 ACL 操作之间可能存在 TOCTOU 竞争

2. **策略绕过风险**
   - 如果 `exclude_tmpdir_env_var: true` 但应用通过其他方式获取临时目录路径
   - 沙箱可能仍能写入未预期的位置

3. **敏感目录硬编码**
   - `.git`, `.codex`, `.agents` 是硬编码的
   - 新增敏感目录需要代码修改

### 边界条件

| 边界 | 处理 |
|------|------|
| 路径不存在 | `add_allow_path/add_deny_path` 闭包中检查 `p.exists()`，不存在则跳过 |
| 规范化失败 | `unwrap_or(candidate)` 回退到原始路径 |
| 相对路径 | 基于 `policy_cwd` 解析 |
| 重复路径 | `HashSet` 自动去重 |
| 大小写敏感 | Windows 路径比较实际不区分大小写，但 HashSet 使用默认哈希 |

### 改进建议

1. **路径比较规范化**
   ```rust
   // 当前: HashSet<PathBuf> 在 Windows 上可能因大小写产生重复
   // 建议: 使用 canonical_path_key（来自 path_normalization.rs）作为 HashSet 键
   ```

2. **动态敏感目录配置**
   ```rust
   // 当前: const PROTECTED_SUBDIRS: &[&str] = &[".git", ".codex", ".agents"];
   // 建议: 从策略配置读取，允许用户扩展
   ```

3. **符号链接处理**
   - 当前 `canonicalize` 会解析符号链接
   - 考虑是否需要区分链接目标和链接本身的权限

4. **性能优化**
   - 对于大量 `writable_roots`，串行处理可能成为瓶颈
   - 考虑并行规范化路径（但注意文件系统竞争）

5. **日志和可观测性**
   - 当前无日志输出
   - 建议增加调试日志记录决策过程（哪些路径被加入 allow/deny 及原因）

6. **测试覆盖扩展**
   - 当前测试覆盖基本场景
   - 建议补充：
     - 循环符号链接处理
     - 非常长路径（>260 字符）
     - 网络路径（UNC）
     - 无效 UTF-8 路径

### 测试分析

现有测试用例：

| 测试 | 覆盖场景 |
|------|----------|
| `includes_additional_writable_roots` | 额外可写根目录 |
| `excludes_tmp_env_vars_when_requested` | `exclude_tmpdir_env_var: true` |
| `denies_git_dir_inside_writable_root` | `.git` 目录保护（目录形式） |
| `denies_git_file_inside_writable_root` | `.git` 文件保护（git worktree） |
| `denies_codex_and_agents_inside_writable_root` | `.codex` 和 `.agents` 保护 |
| `skips_protected_subdirs_when_missing` | 敏感目录不存在时的处理 |

测试使用 `tempfile::TempDir` 和 `pretty_assertions`，质量良好。
