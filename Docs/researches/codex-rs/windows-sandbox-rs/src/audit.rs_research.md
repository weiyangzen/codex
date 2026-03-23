# audit.rs 研究文档

## 场景与职责

`audit.rs` 实现沙箱环境的安全审计功能，主要用于扫描和识别系统中对世界（Everyone/World SID）可写的目录，并可选地应用 Capability-based 拒绝写入 ACE 作为缓解措施。

该模块在以下场景中使用：
- 沙箱启动前的安全审计（预检）
- 识别可能被恶意利用的世界可写目录
- 对世界可写目录应用额外的 Capability 拒绝策略
- 为沙箱进程创建更严格的文件系统沙箱

## 功能点目的

### 1. 世界可写目录扫描
- **`audit_everyone_writable`**: 核心审计函数
- 扫描 CWD、TEMP/TMP、用户目录、PATH 条目、系统根目录
- 检查 ACL 是否授予 World SID 写入权限

### 2. 候选路径收集
- **`gather_candidates`**: 收集需要扫描的路径集合
- 优先级排序：CWD → TEMP/TMP → 用户根目录 → PATH 条目 → 系统根目录
- 使用 `HashSet` 去重，确保唯一性

### 3. Capability 拒绝策略应用
- **`apply_capability_denies_for_world_writable`**: 对世界可写目录应用 Capability 拒绝 ACE
- **`apply_world_writable_scan_and_denies`**: 组合扫描和应用
- 使用 `cap.rs` 生成的 Capability SID 创建拒绝规则

### 4. 性能限制
- **`MAX_ITEMS_PER_DIR`**: 每目录最大扫描条目数（1000）
- **`AUDIT_TIME_LIMIT_SECS`**: 审计时间上限（2 秒）
- **`MAX_CHECKED_LIMIT`**: 最大检查路径数（50000）

### 5. 噪声过滤
- **`SKIP_DIR_SUFFIXES`**: 跳过特定 Windows 系统目录
  - `/windows/installer`
  - `/windows/registration`
  - `/programdata`

## 具体技术实现

### 关键常量

```rust
const MAX_ITEMS_PER_DIR: i32 = 1000;
const AUDIT_TIME_LIMIT_SECS: i64 = 2;
const MAX_CHECKED_LIMIT: i32 = 50000;

const SKIP_DIR_SUFFIXES: &[&str] = &[
    "/windows/installer",
    "/windows/registration",
    "/programdata",
];

// 写入权限掩码
const write_mask = FILE_WRITE_DATA 
    | FILE_APPEND_DATA 
    | FILE_WRITE_EA 
    | FILE_WRITE_ATTRIBUTES;
```

### 核心算法流程

#### 世界可写扫描流程

```
audit_everyone_writable(cwd, env, logs_base_dir)
  └─> 获取 world_sid()
  └─> 定义 check_world_writable 闭包
  │     └─> path_mask_allows(path, &[psid_world], write_mask, false)
  └─> 快速路径：扫描 CWD 直接子目录（优先发现工作区问题）
  │     └─> 限制 MAX_ITEMS_PER_DIR
  │     └─> 检查时间/计数限制
  │     └─> 跳过符号链接
  │     └─> 对世界可写目录加入 flagged 列表
  └─> 广度扫描：gather_candidates 收集路径
  │     └─> CWD, TEMP/TMP, USERPROFILE, PUBLIC, PATH, C:/, C:/Windows
  └─> 对每个候选根目录:
        └─> 检查根目录本身是否世界可写
        └─> 扫描一级子目录（限制 MAX_ITEMS_PER_DIR）
        └─> 跳过符号链接和 SKIP_DIR_SUFFIXES
        └─> 对世界可写目录加入 flagged 列表
  └─> 记录审计结果日志
  └─> 返回 flagged 路径列表
```

#### Capability 拒绝应用流程

```
apply_capability_denies_for_world_writable(codex_home, flagged, policy, cwd, logs)
  └─> 如果 flagged 为空，直接返回
  └─> 创建 codex_home 目录
  └─> load_or_create_cap_sids() 获取 Capability SID
  └─> 根据策略确定 active_sid:
  │     WorkspaceWrite -> caps.workspace
  │     ReadOnly -> caps.readonly
  │     其他 -> 返回（不应用）
  └─> 转换 SID 字符串为指针 (convert_string_sid_to_sid)
  └─> 对每个 flagged 路径:
        └─> 如果路径在 workspace_roots 下，跳过（不拒绝自己的工作区）
        └─> unsafe { add_deny_write_ace(path, active_sid) }
        └─> 记录成功/失败日志
```

### 路径去重机制

```rust
fn unique_push(set: &mut HashSet<PathBuf>, out: &mut Vec<PathBuf>, p: PathBuf) {
    if let Ok(abs) = p.canonicalize() {
        if set.insert(abs.clone()) {
            out.push(abs);
        }
    }
}
```

使用 `canonicalize` + `HashSet` 确保物理上相同的路径只被检查一次。

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `setup_orchestrator.rs` | `apply_world_writable_scan_and_denies` | 设置/刷新时审计 |
| 外部（通过 lib.rs 导出） | `apply_world_writable_scan_and_denies` | 预检调用 |

### 被调用模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `acl.rs` | `add_deny_write_ace`, `path_mask_allows` | ACL 操作 |
| `cap.rs` | `load_or_create_cap_sids`, `cap_sid_file`, `workspace_cap_sid_for_cwd` | Capability SID 管理 |
| `token.rs` | `convert_string_sid_to_sid`, `world_sid` | SID 转换 |
| `logging.rs` | `debug_log`, `log_note` | 日志记录 |
| `path_normalization.rs` | `canonical_path_key` | 路径规范化 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/audit.rs
  ├─> 依赖: acl.rs (add_deny_write_ace, path_mask_allows)
  ├─> 依赖: cap.rs (load_or_create_cap_sids, workspace_cap_sid_for_cwd)
  ├─> 依赖: token.rs (convert_string_sid_to_sid, world_sid)
  ├─> 依赖: logging.rs (debug_log, log_note)
  ├─> 依赖: path_normalization.rs (canonical_path_key)
  ├─> 依赖: policy.rs (SandboxPolicy)
  └─> 被 lib.rs 公开导出: apply_world_writable_scan_and_denies
```

## 依赖与外部交互

### 内部依赖
- **`acl.rs`**: ACL 检查和修改
- **`cap.rs`**: Capability SID 加载/创建
- **`token.rs`**: SID 转换和 World SID 获取
- **`logging.rs`**: 审计日志记录
- **`path_normalization.rs`**: 路径键规范化
- **`policy.rs`**: 策略类型定义

### 外部依赖
- **std::time**: 超时控制 (`Instant`, `Duration`)
- **std::collections::HashSet**: 路径去重

### 环境交互
- 读取环境变量：`TEMP`, `TMP`, `USERPROFILE`, `PUBLIC`, `PATH`
- 文件系统遍历：`std::fs::read_dir`
- 符号链接检测：`file_type().is_symlink()`

### Windows API（间接通过 acl.rs）
- `path_mask_allows` 内部使用 Windows 安全 API

## 风险、边界与改进建议

### 安全风险

1. **审计绕过风险**
   - 审计有时间限制（2秒）和数量限制（50000）
   - 攻击者可能利用大量目录导致审计不完全
   - 符号链接被跳过，但 junction point 可能绕过

2. **TOCTOU 风险**
   - 审计和应用拒绝 ACE 之间有时间窗口
   - 目录权限可能在检查后被修改

3. **误报和漏报**
   - 某些系统目录被硬编码跳过，可能存在误判
   - 继承的权限可能未被准确评估

4. **Capability SID 持久化**
   - 拒绝 ACE 是持久化的（写入文件系统）
   - 如果 Capability SID 被泄露或预测，可能成为攻击向量

### 边界条件

| 边界 | 处理 |
|------|------|
| 超时 | 检查 `start.elapsed() > Duration::from_secs(AUDIT_TIME_LIMIT_SECS)` |
| 计数限制 | 检查 `checked > MAX_CHECKED_LIMIT` |
| 符号链接 | 通过 `file_type().is_symlink()` 跳过 |
| 重解析点 | 同样被跳过（避免审计链接目标） |
| 目录不存在 | `read_dir` 返回 Err，跳过处理 |
| ACL 不可读 | `debug_log` 记录，视为非世界可写（保守策略） |

### 改进建议

1. **异步/并行扫描**
   ```rust
   // 当前: 单线程顺序扫描
   // 建议: 使用 rayon 或 tokio 并行扫描独立子树
   ```

2. **增量审计**
   - 当前每次启动都全量扫描
   - 建议维护持久化的审计缓存，仅扫描变更

3. **更精确的权限评估**
   - 当前仅检查 World SID
   - 建议扩展检查其他高权限组（如 Authenticated Users）

4. **可配置跳过列表**
   ```rust
   // 当前: const SKIP_DIR_SUFFIXES: &[&str]
   // 建议: 从策略配置读取，允许环境特定定制
   ```

5. **审计报告增强**
   - 当前仅记录路径列表
   - 建议增加：权限详情、继承来源、修复建议

6. **回滚机制**
   - 当前 `add_deny_write_ace` 是持久化的
   - 建议记录应用的拒绝 ACE，支持集中清理

7. **内存优化**
   - 大量路径时 `flagged` Vec 可能占用大量内存
   - 考虑流式处理或分页

### 测试分析

现有测试：

| 测试 | 覆盖场景 |
|------|----------|
| `gathers_path_entries_by_list_separator` | PATH 环境变量解析（含空格路径） |

测试覆盖不足，建议补充：
- 超时行为测试
- 符号链接跳过验证
- 权限检测准确性测试
- Capability 拒绝应用测试
- 大目录性能测试
