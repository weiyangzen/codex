# mod.rs (tools/runtimes) 深入研究

## 场景与职责

`codex-rs/core/src/tools/runtimes/mod.rs` 是工具运行时模块的入口文件，负责：

1. **模块组织**：声明并导出三个子模块（`apply_patch`, `shell`, `unified_exec`）
2. **共享工具函数**：提供运行时通用的辅助函数
3. **Shell 快照集成**：实现 shell 环境快照的包装逻辑

**架构定位：**
- 位于工具执行栈的运行时层
- 被 `handlers` 层调用，通过 `orchestrator` 编排
- 提供跨运行时的共享功能

---

## 功能点目的

### 1. 模块导出

```rust
pub mod apply_patch;
pub mod shell;
pub mod unified_exec;
```

**设计意图：**
- `apply_patch`: 文件补丁操作运行时
- `shell`: 传统 shell 命令执行运行时
- `unified_exec`: 统一执行运行时（支持 PTY 和长时间运行的进程）

### 2. ExecveSessionApproval - 执行会话审批元数据

```rust
#[derive(Debug, Clone)]
pub(crate) struct ExecveSessionApproval {
    /// 如果此执行会话审批与技能脚本关联，包含技能元数据
    #[cfg_attr(not(unix), allow(dead_code))]
    pub skill: Option<SkillMetadata>,
}
```

**用途：**
- 关联技能脚本执行与审批流程
- Unix 特有功能，非 Unix 平台允许未使用

### 3. build_command_spec - 命令规范构建

```rust
pub(crate) fn build_command_spec(
    command: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    expiration: ExecExpiration,
    sandbox_permissions: SandboxPermissions,
    additional_permissions: Option<PermissionProfile>,
    justification: Option<String>,
) -> Result<CommandSpec, ToolError>
```

**功能：**
- 将分词的命令行转换为结构化的 `CommandSpec`
- 验证命令非空（至少包含程序名）
- 被 `shell.rs` 和 `unified_exec.rs` 共享使用

### 4. maybe_wrap_shell_lc_with_snapshot - Shell 快照包装

**核心功能**：将 `shell -lc "<script>"` 形式的命令重写为支持 shell 快照的版本。

**重写逻辑：**
```
原始: shell -lc "<script>"
重写: user_shell -c ". SNAPSHOT (best effort); exec shell -c <script>"
```

**目的：**
- 在登录 shell 执行前加载用户 shell 环境快照
- 保留用户的 PATH、别名、函数等环境设置
- 支持显式环境变量覆盖的优先级处理

---

## 具体技术实现

### Shell 快照包装算法

#### 触发条件检查

```rust
pub(crate) fn maybe_wrap_shell_lc_with_snapshot(
    command: &[String],
    session_shell: &Shell,
    cwd: &Path,
    explicit_env_overrides: &HashMap<String, String>,
) -> Vec<String> {
    // 1. Windows 平台直接返回
    if cfg!(windows) { return command.to_vec(); }
    
    // 2. 检查是否有快照
    let Some(snapshot) = session_shell.shell_snapshot() else { ... };
    
    // 3. 检查快照文件是否存在
    if !snapshot.path.exists() { ... }
    
    // 4. 检查 CWD 匹配
    if snapshot_cwd != command_cwd { ... }
    
    // 5. 检查命令格式是否为 "-lc"
    if flag != "-lc" { ... }
    
    // 6. 执行重写
    ...
}
```

#### 重写脚本构造

```rust
let rewritten_script = if override_exports.is_empty() {
    format!(
        "if . '{snapshot_path}' >/dev/null 2>&1; then :; fi\n\nexec '{original_shell}' -c '{original_script}'{trailing_args}"
    )
} else {
    format!(
        "{override_captures}\n\nif . '{snapshot_path}' >/dev/null 2>&1; then :; fi\n\n{override_exports}\n\nexec '{original_shell}' -c '{original_script}'{trailing_args}"
    )
};
```

**关键点：**
- `if . '{snapshot_path}'`: 尝试 source 快照文件，失败不报错
- `exec`: 用新 shell 替换当前进程，避免嵌套
- 单引号转义：使用 `shell_single_quote` 处理特殊字符

### 环境变量覆盖处理

#### build_override_exports

```rust
fn build_override_exports(explicit_env_overrides: &HashMap<String, String>) -> (String, String) {
    // 1. 过滤有效变量名
    let mut keys = explicit_env_overrides
        .keys()
        .filter(|key| is_valid_shell_variable_name(key))
        .collect::<Vec<_>>();
    keys.sort_unstable();
    
    // 2. 生成捕获代码（保存原始值）
    let captures = keys.iter().enumerate().map(|(idx, key)| {
        format!("__CODEX_SNAPSHOT_OVERRIDE_SET_{idx}=\"${{{key}+x}}\"\n__CODEX_SNAPSHOT_OVERRIDE_{idx}=\"${{{key}-}}\"")
    });
    
    // 3. 生成恢复代码（在快照 source 后恢复）
    let restores = keys.iter().enumerate().map(|(idx, key)| {
        format!("if [ -n \"${{__CODEX_SNAPSHOT_OVERRIDE_SET_{idx}}}\" ]; then export {key}=\"${{__CODEX_SNAPSHOT_OVERRIDE_{idx}}}\"; else unset {key}; fi")
    });
    
    (captures, restores)
}
```

**安全设计：**
- 使用临时变量保存原始状态
- 在快照 source 后恢复显式覆盖值
- 支持取消设置（unset）的变量

#### 变量名验证

```rust
fn is_valid_shell_variable_name(name: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else { return false; };
    if !(first == '_' || first.is_ascii_alphabetic()) { return false; }
    chars.all(|c| c == '_' || c.is_ascii_alphanumeric())
}
```

符合 POSIX shell 变量命名规范。

#### 单引号转义

```rust
fn shell_single_quote(input: &str) -> String {
    input.replace('\'', r#"'"'"'"#)
}
```

将 `'` 转义为 `'"'"'`，这是 POSIX shell 中单引号内包含单引号的标准技巧。

---

## 关键代码路径与文件引用

### 模块结构

```
codex-rs/core/src/tools/runtimes/
├── mod.rs              # 本文件，模块入口
├── apply_patch.rs      # 补丁运行时
├── apply_patch_tests.rs # 补丁运行时测试
├── shell.rs            # Shell 运行时
├── shell/
│   ├── unix_escalation.rs   # Unix 权限提升
│   └── zsh_fork_backend.rs  # Zsh fork 后端
├── unified_exec.rs     # 统一执行运行时
└── mod_tests.rs        # 本模块测试（Unix only）
```

### 调用关系

| 函数 | 调用方 |
|------|--------|
| `build_command_spec` | `shell.rs`, `unified_exec.rs` |
| `maybe_wrap_shell_lc_with_snapshot` | `shell.rs:224`, `unified_exec.rs:197` |

### 依赖模块

| 模块 | 用途 |
|------|------|
| `crate::exec::ExecExpiration` | 执行超时配置 |
| `crate::path_utils` | 路径规范化 |
| `crate::sandboxing::CommandSpec` | 命令规范结构 |
| `crate::shell::Shell` | Shell 类型和快照 |
| `crate::skills::SkillMetadata` | 技能元数据 |

---

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `codex_protocol::models::PermissionProfile` | 权限配置 |

### 内部模块交互

```
mod.rs
├── 使用 crate::exec::ExecExpiration
├── 使用 crate::sandboxing::CommandSpec, SandboxPermissions
├── 使用 crate::shell::Shell
└── 使用 crate::skills::SkillMetadata
```

### 条件编译

```rust
#[cfg(all(test, unix))]
#[path = "mod_tests.rs"]
mod tests;
```

- 测试仅在 Unix 平台编译
- 因为 shell 快照功能主要面向 Unix shell（Bash/Zsh/sh）

---

## 风险、边界与改进建议

### 风险点

1. **Shell 快照安全性**
   - **风险**：快照文件可能被篡改，执行恶意代码
   - **现状**：使用 `if . '{snapshot_path}' >/dev/null 2>&1; then :; fi` 静默失败
   - **建议**：考虑验证快照文件完整性或来源

2. **命令注入风险**
   - **风险**：`shell_single_quote` 是否正确处理所有边缘情况
   - **现状**：仅处理单引号转义
   - **建议**：审计是否还有其他需要转义的特殊字符

3. **环境变量泄漏**
   - **风险**：`__CODEX_SNAPSHOT_OVERRIDE_*` 临时变量可能残留
   - **现状**：在子 shell 中执行，不影响父环境
   - **缓解**：设计正确，但需确保 `exec` 成功执行

4. **跨平台差异**
   - **风险**：Windows 直接返回原命令，行为不一致
   - **现状**：Windows 不支持 shell 快照
   - **建议**：文档化平台差异，或考虑 PowerShell 配置文件支持

### 边界条件

| 边界 | 处理 |
|------|------|
| 空命令 | `build_command_spec` 返回 `ToolError::Rejected` |
| 无快照 | `maybe_wrap_shell_lc_with_snapshot` 原样返回 |
| CWD 不匹配 | 跳过重写，原样返回 |
| 非 `-lc` 标志 | 跳过重写，原样返回 |
| 无效变量名 | `build_override_exports` 过滤掉 |

### 改进建议

1. **测试覆盖增强**
   - 当前：仅在 Unix 平台有测试（`mod_tests.rs`）
   - 建议：添加 `build_command_spec` 的跨平台测试

2. **错误处理细化**
   - 当前：快照 source 失败静默忽略
   - 建议：可选的日志记录，帮助调试环境问题

3. **性能优化**
   - 当前：每次命令都进行字符串拼接
   - 建议：缓存重写后的命令模板（如果快照和覆盖不变）

4. **功能扩展**
   - 当前：仅支持 `-lc` 形式的登录 shell
   - 建议：支持 `-c` 非登录 shell 的快照加载

5. **文档完善**
   - 当前：代码注释较清晰
   - 建议：添加架构文档，说明 shell 快照在整体执行流程中的作用

### 与测试的关联

- `mod_tests.rs`（398 行）包含 12+ 个测试用例
- 覆盖场景：基本重写、引号转义、不同 shell、CWD 匹配、环境覆盖等
- 详见 `mod_tests.rs_research.md` 分析
