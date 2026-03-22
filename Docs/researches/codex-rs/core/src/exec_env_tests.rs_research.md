# exec_env_tests.rs 研究文档

## 场景与职责

`exec_env_tests.rs` 是 `exec_env.rs` 模块的单元测试文件，负责验证环境变量构建逻辑的正确性。测试覆盖了 `populate_env` 函数的各种配置场景，确保环境变量继承、过滤、设置等行为符合预期。

### 测试范围

1. **继承策略测试**：All/None/Core 三种继承级别
2. **敏感信息过滤**：默认排除和用户自定义排除
3. **包含限制**：`include_only` 模式匹配
4. **用户设置覆盖**：`r#set` 自定义环境变量
5. **线程 ID 注入**：`CODEX_THREAD_ID` 自动注入
6. **平台兼容性**：Windows 大小写不敏感处理

## 功能点目的

### 测试用例设计原则

每个测试用例遵循 **Arrange-Act-Assert** 模式：
1. **Arrange**: 构建输入环境变量和策略配置
2. **Act**: 调用 `populate_env` 函数
3. **Assert**: 验证输出环境变量映射

### 测试辅助函数

```rust
fn make_vars(pairs: &[(&str, &str)]) -> Vec<(String, String)>
```
- 将 `&[(&str, &str)]` 转换为 `Vec<(String, String)>`
- 用于快速构建测试输入

## 具体技术实现

### 测试用例详解

#### 1. `test_core_inherit_defaults_keep_sensitive_vars`

**目的**：验证默认策略（inherit All，不应用默认排除）保留敏感变量

**输入**：
```rust
vars = [("PATH", "/usr/bin"), ("HOME", "/home/user"), 
        ("API_KEY", "secret"), ("SECRET_TOKEN", "t")]
policy = ShellEnvironmentPolicy::default()  // inherit All, ignore_default_excludes = true
```

**期望输出**：保留所有变量（包括敏感变量）

**意义**：默认策略向后兼容，不破坏现有行为

---

#### 2. `test_core_inherit_with_default_excludes_enabled`

**目的**：验证启用默认排除后过滤敏感变量

**输入**：
```rust
policy.ignore_default_excludes = false  // 应用 *KEY*, *SECRET*, *TOKEN* 过滤
```

**期望输出**：仅保留 `PATH` 和 `HOME`

**意义**：安全配置生效，防止密钥泄露

---

#### 3. `test_include_only`

**目的**：验证 `include_only` 模式匹配

**输入**：
```rust
policy.ignore_default_excludes = true
policy.include_only = vec![EnvironmentVariablePattern::new_case_insensitive("*PATH")]
vars = [("PATH", "/usr/bin"), ("FOO", "bar")]
```

**期望输出**：仅保留 `PATH`

**意义**：精确控制允许的环境变量

---

#### 4. `test_set_overrides`

**目的**：验证用户设置可以添加新变量

**输入**：
```rust
policy.r#set.insert("NEW_VAR", "42")
```

**期望输出**：包含 `NEW_VAR=42`

**意义**：支持自定义环境变量注入

---

#### 5. `populate_env_inserts_thread_id`

**目的**：验证线程 ID 自动注入

**输入**：
```rust
thread_id = Some(ThreadId::new())
```

**期望输出**：包含 `CODEX_THREAD_ID=<thread_id>`

**意义**：跨进程追踪能力

---

#### 6. `populate_env_omits_thread_id_when_missing`

**目的**：验证无线程 ID 时不注入

**输入**：
```rust
thread_id = None
```

**期望输出**：不包含 `CODEX_THREAD_ID`

**意义**：避免空值污染

---

#### 7. `test_inherit_all`

**目的**：验证 `inherit: All` 保留所有变量

**输入**：
```rust
policy.inherit = ShellEnvironmentPolicyInherit::All
policy.ignore_default_excludes = true
```

**期望输出**：保留所有输入变量

---

#### 8. `test_inherit_all_with_default_excludes`

**目的**：验证 `inherit: All` 与默认排除组合

**输入**：
```rust
vars = [("PATH", "/usr/bin"), ("API_KEY", "secret")]
policy.inherit = All
policy.ignore_default_excludes = false
```

**期望输出**：仅保留 `PATH`

---

#### 9. `test_core_inherit_respects_case_insensitive_names_on_windows`

**目的**：验证 Windows 平台大小写不敏感处理

**输入**：
```rust
#[cfg(target_os = "windows")]
vars = [("Path", "C:\\Windows"), ("TEMP", "C:\\Temp"), ("FOO", "bar")]
policy.inherit = Core
```

**期望输出**：保留 `Path` 和 `TEMP`（Core 变量），排除 `FOO`

**平台条件**：仅在 Windows 编译

---

#### 10. `test_inherit_none`

**目的**：验证 `inherit: None` 模式

**输入**：
```rust
policy.inherit = None
policy.ignore_default_excludes = true
policy.r#set.insert("ONLY_VAR", "yes")
```

**期望输出**：仅包含 `ONLY_VAR` 和 `CODEX_THREAD_ID`

**意义**：完全控制环境变量，不从父进程继承

## 关键代码路径与文件引用

### 测试结构

```rust
// exec_env.rs
#[cfg(test)]
#[path = "exec_env_tests.rs"]
mod tests;
```

### 依赖关系

```
exec_env_tests.rs
├── super::* (exec_env 模块)
├── crate::config::types::ShellEnvironmentPolicyInherit
└── maplit::hashmap (测试依赖)
```

### 被测函数

```rust
// exec_env.rs
fn populate_env<I>(
    vars: I,
    policy: &ShellEnvironmentPolicy,
    thread_id: Option<ThreadId>,
) -> HashMap<String, String>
```

## 依赖与外部交互

### 测试依赖 Crate

| Crate | 用途 |
|-------|------|
| `maplit::hashmap` | 方便的 HashMap 字面量宏 |
| `pretty_assertions::assert_eq` | 清晰的测试失败输出 |

### 类型依赖

| 类型 | 来源 |
|------|------|
| `ShellEnvironmentPolicy` | `super::*` |
| `ShellEnvironmentPolicyInherit` | `crate::config::types` |
| `ThreadId` | `codex_protocol::ThreadId` |
| `EnvironmentVariablePattern` | `super::*` |

## 风险、边界与改进建议

### 测试覆盖分析

#### 已覆盖场景 ✅

| 场景 | 测试用例 |
|------|----------|
| 默认策略（All + 不禁用排除） | `test_core_inherit_defaults_keep_sensitive_vars` |
| 启用默认排除 | `test_core_inherit_with_default_excludes_enabled` |
| include_only 限制 | `test_include_only` |
| 用户设置 | `test_set_overrides` |
| 线程 ID 注入 | `populate_env_inserts_thread_id` |
| 无线程 ID | `populate_env_omits_thread_id_when_missing` |
| inherit: All | `test_inherit_all` |
| inherit: All + 排除 | `test_inherit_all_with_default_excludes` |
| inherit: Core (Windows) | `test_core_inherit_respects_case_insensitive_names_on_windows` |
| inherit: None | `test_inherit_none` |

#### 未覆盖场景 ⚠️

1. **复杂模式匹配**
   - `exclude` 与 `include_only` 交互
   - 多个模式的优先级

2. **边界值**
   - 空环境变量名
   - 空环境变量值
   - 非常大的环境变量值

3. **并发场景**
   - 虽然函数无状态，但 `std::env::vars()` 可能受外部影响

4. **Unicode 处理**
   - 非 ASCII 环境变量名
   - 特殊字符值

5. **Core 变量完整列表验证**
   - 验证所有 Core 变量都被正确识别

### 改进建议

#### 1. 补充边界测试

```rust
#[test]
fn test_empty_variable_name() {
    // 测试空变量名处理
}

#[test]
fn test_unicode_variable_names() {
    // 测试 Unicode 变量名
    let vars = make_vars(&[("变量", "value"), ("ПЕРЕМЕННАЯ", "value")]);
}
```

#### 2. 添加模式交互测试

```rust
#[test]
fn test_exclude_and_include_only_interaction() {
    // 验证 exclude 和 include_only 同时存在时的行为
    // exclude 先执行，include_only 后执行
    // 因此 include_only 可以"复活"被 exclude 的变量
}
```

#### 3. 添加 Core 变量完整验证

```rust
#[test]
fn test_core_variables_complete_list() {
    const ALL_CORE_VARS: &[&str] = &[
        "HOME", "LOGNAME", "PATH", "SHELL", 
        "USER", "USERNAME", "TMPDIR", "TEMP", "TMP"
    ];
    // 验证每个 Core 变量都被正确识别
}
```

#### 4. 添加性能测试

```rust
#[test]
fn test_large_environment_performance() {
    // 测试处理大量环境变量时的性能
    // 1000+ 个环境变量
}
```

#### 5. 改进 Windows 测试

当前 Windows 测试仅在 Windows 平台运行。考虑：
- 使用条件编译模拟 Windows 行为
- 或在 CI 中确保 Windows 测试运行

### 测试质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 功能覆盖 | ⭐⭐⭐⭐ | 主要功能已覆盖 |
| 边界覆盖 | ⭐⭐⭐ | 缺少一些边界情况 |
| 平台覆盖 | ⭐⭐⭐ | Windows 特定测试有条件编译 |
| 可读性 | ⭐⭐⭐⭐⭐ | 测试清晰，命名良好 |
| 维护性 | ⭐⭐⭐⭐⭐ | 使用辅助函数，易于维护 |

### 测试执行

```bash
# 运行 exec_env 测试
cargo test -p codex-core exec_env

# 运行特定测试
cargo test -p codex-core test_core_inherit_defaults_keep_sensitive_vars
```
