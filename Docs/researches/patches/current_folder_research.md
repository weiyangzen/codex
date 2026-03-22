# patches 目录研究文档

## 1. 场景与职责

`patches/` 目录是 Codex CLI 项目的**第三方依赖补丁存储库**，专门用于存放对 Rust 外部 crate 的构建时补丁。这些补丁在 Bazel 构建系统中通过 `crate.annotation` 机制应用，解决以下场景问题：

### 1.1 核心职责

| 职责 | 说明 |
|------|------|
| **构建系统兼容性修复** | 修复外部 crate 在 Bazel 沙箱/隔离构建环境中的问题 |
| **Hermetic 构建支持** | 确保外部依赖在封闭构建环境中可复现编译 |
| **跨平台适配** | 处理特定平台（如 Windows）的构建问题 |

### 1.2 补丁分类

项目中有两个 `patches` 目录：

1. **`/patches/` (根目录)** - 用于 Rust/Bazel 构建系统的 crate 补丁
2. **`/shell-tool-mcp/patches/`** - 用于 Shell 执行包装器的 C 语言补丁

---

## 2. 功能点目的

### 2.1 aws-lc-sys_memcmp_check.patch

**目标 Crate**: `aws-lc-sys` (AWS Libcrypto 的 Rust FFI 绑定)

**问题背景**:
- `aws-lc-sys` 在构建时执行编译器检查，尝试编译并运行测试程序来检测 `memcmp` 行为
- 在 Bazel 沙箱环境中，这些检查会失败，原因包括：
  1. 调用外部调试工具（如 `dsymutil`）在 hermetic 沙箱中不可用
  2. 使用相对于 Bazel execroot 的路径参数，但进程从其他位置运行

**补丁功能**:

```rust
// 1. 移除调试相关参数 (-g*), 添加 -g0 禁用调试信息
memcmp_compile_args.retain(|arg| {
    let Some(arg_str) = arg.to_str() else { return true };
    !arg_str.starts_with("-g")
});
memcmp_compile_args.push("-g0".into());

// 2. 重写 Bazel execroot 相对路径为绝对路径
if let Some(execroot) = Self::bazel_execroot(self.manifest_dir.as_path()) {
    for arg in &mut memcmp_compile_args {
        Self::rewrite_bazel_execroot_arg(execroot.as_path(), arg);
    }
}
```

**关键函数**:
- `rewrite_bazel_execroot_arg()`: 重写 `bazel-out/` 路径和 `-B`/`-L` 标志
- `bazel_execroot()`: 通过查找 `bazel-out` 组件定位 execroot

### 2.2 windows-link.patch

**目标 Crate**: `windows-link`

**问题背景**:
- `windows-link` crate 使用 `#![doc = include_str!("../readme.md")]` 包含外部文档
- 在 Bazel 构建环境中，编译时文件访问需要显式声明 `compile_data`/`build_script_data`
- 为避免复杂的 Bazel 配置，直接用占位字符串替换文档包含

**补丁内容**:
```diff
-#![doc = include_str!("../readme.md")]
+#![doc = "windows-link"]
```

### 2.3 shell-tool-mcp/patches/* (Shell 执行包装器补丁)

这些补丁用于支持 Codex 的**权限提升沙箱机制**。

#### bash-exec-wrapper.patch

**目标**: GNU Bash `execute_cmd.c`

**功能**: 添加 `EXEC_WRAPPER` 环境变量支持

```c
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    char *orig_command = command;
    larray = strvec_len (args);
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;
    args[1] = orig_command;
    command = exec_wrapper;
}
```

**工作流程**:
1. 当 `EXEC_WRAPPER` 设置时，在 `execve()` 前拦截
2. 将原命令包装为 wrapper 的参数
3. Wrapper (`codex-execve-wrapper`) 通过 `CODEX_ESCALATE_SOCKET` 与 Codex 通信决定是否执行

#### zsh-exec-wrapper.patch

**目标**: Zsh `Src/exec.c` 的 `zexecve()` 函数

**功能**: 与 Bash 补丁相同，为 Zsh 添加 `EXEC_WRAPPER` 支持

```c
exec_argv = argv;
if ((exec_wrapper = getenv("EXEC_WRAPPER")) &&
    *exec_wrapper && !inblank(*exec_wrapper)) {
    exec_argv = argv - 2;
    exec_argv[0] = exec_wrapper;
    exec_argv[1] = orig_pth;
    pth = exec_wrapper;
}
execve(pth, exec_argv, newenvp);
```

---

## 3. 具体技术实现

### 3.1 Bazel 集成 (MODULE.bazel)

补丁通过 `rules_rs` 的 `crate.annotation` 机制应用：

```starlark
# aws-lc-sys 补丁配置
crate.annotation(
    build_script_env = {
        "AWS_LC_SYS_NO_JITTER_ENTROPY": "1",
    },
    crate = "aws-lc-sys",
    patch_args = ["-p1"],  # 使用 git 格式的 patch
    patches = [
        "//patches:aws-lc-sys_memcmp_check.patch",
    ],
)

# windows-link 补丁配置
crate.annotation(
    crate = "windows-link",
    patch_args = ["-p1"],
    patches = [
        "//patches:windows-link.patch",
    ],
)
```

### 3.2 补丁应用流程

```
┌─────────────────┐
│  Cargo.toml     │
│  (定义依赖)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  MODULE.bazel   │
│  (crate.annotation) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  patches/*.patch │
│  (补丁文件)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  rules_rs       │
│  (应用补丁)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Bazel 构建     │
└─────────────────┘
```

### 3.3 数据结构

#### Patch 文件格式

所有补丁使用标准 **Unified Diff** 格式（`git diff` 输出）：

```
diff --git a/path/to/file b/path/to/file
index <hash>..<hash> <mode>
--- a/path/to/file
+++ b/path/to/file
@@ -start,count +start,count @@
 context line
-removed line
+added line
```

#### Bazel crate.annotation 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `crate` | string | 目标 crate 名称 |
| `patches` | label list | 补丁文件标签（如 `//patches:file.patch`） |
| `patch_args` | string list | 传递给 `patch` 命令的参数，`-p1` 表示 strip 第一层目录 |
| `build_script_env` | dict | 构建脚本环境变量 |

---

## 4. 关键代码路径与文件引用

### 4.1 补丁定义文件

| 文件路径 | 用途 | 目标 Crate |
|----------|------|-----------|
| `/patches/aws-lc-sys_memcmp_check.patch` | 修复 memcmp 检查在 Bazel 沙箱中的问题 | `aws-lc-sys` |
| `/patches/windows-link.patch` | 移除 readme.md 包含，避免 Bazel 编译时文件访问问题 | `windows-link` |
| `/patches/BUILD.bazel` | 空文件，使 patches 目录成为 Bazel package | - |
| `/shell-tool-mcp/patches/bash-exec-wrapper.patch` | 为 Bash 添加 EXEC_WRAPPER 支持 | GNU Bash |
| `/shell-tool-mcp/patches/zsh-exec-wrapper.patch` | 为 Zsh 添加 EXEC_WRAPPER 支持 | Zsh |

### 4.2 补丁消费配置

| 文件路径 | 相关代码 |
|----------|----------|
| `MODULE.bazel` | 第 73-82 行 (`aws-lc-sys` 配置) |
| `MODULE.bazel` | 第 158-165 行 (`windows-link` 配置) |

### 4.3 相关 Rust 代码（apply-patch 系统）

虽然 `patches/` 目录本身只存储第三方补丁，但项目有完整的 `apply_patch` 工具实现：

| 文件路径 | 功能 |
|----------|------|
| `codex-rs/apply-patch/src/lib.rs` | 补丁应用核心逻辑 |
| `codex-rs/apply-patch/src/parser.rs` | 自定义补丁格式解析器 |
| `codex-rs/apply-patch/src/seek_sequence.rs` | 模糊匹配算法（支持 Unicode 规范化） |
| `codex-rs/apply-patch/src/invocation.rs` | Shell 命令解析（支持 heredoc） |
| `codex-rs/core/src/tools/runtimes/apply_patch.rs` | 运行时执行逻辑 |

### 4.4 Shell 权限提升相关

| 文件路径 | 功能 |
|----------|------|
| `codex-rs/shell-escalation/README.md` | 文档说明 EXEC_WRAPPER 机制 |
| `codex-rs/shell-escalation/src/bin/codex-execve-wrapper.rs` | 执行包装器实现 |

---

## 5. 依赖与外部交互

### 5.1 构建时依赖

```
patches/
    ├── BUILD.bazel (空，仅标记为 Bazel package)
    ├── aws-lc-sys_memcmp_check.patch
    │   └── 依赖: Bazel, rules_rs, aws-lc-sys crate
    └── windows-link.patch
        └── 依赖: Bazel, rules_rs, windows-link crate
```

### 5.2 运行时依赖（Shell 补丁）

```
shell-tool-mcp/patches/
    ├── bash-exec-wrapper.patch
    │   ├── 依赖: GNU Bash 源码 (commit a8a1c2fac0)
    │   └── 被依赖: codex-execve-wrapper
    └── zsh-exec-wrapper.patch
        ├── 依赖: Zsh 源码
        └── 被依赖: codex-execve-wrapper
```

### 5.3 交互流程图

#### Bazel 构建时补丁应用

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  MODULE.bazel │────▶│  rules_rs    │────▶│  patch cmd   │
│  (配置)       │     │  (crate_ext) │     │  (系统命令)   │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                 │
                       ┌─────────────────────────┘
                       ▼
              ┌────────────────┐
              │  patches/*.patch │
              │  (补丁文件)      │
              └────────────────┘
```

#### Shell 权限提升流程

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   User      │────▶│  Patched Shell   │────▶│  EXEC_WRAPPER   │
│  (输入命令)  │     │  (bash/zsh)      │     │  (环境变量检查)  │
└─────────────┘     └──────────────────┘     └────────┬────────┘
                                                      │
                       ┌──────────────────────────────┘
                       ▼
              ┌─────────────────┐
              │ codex-execve-wrapper │
              │ (通过 socket 询问)     │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │  Codex Core     │
              │  (权限决策)      │
              └─────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 补丁维护风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| **上游更新不兼容** | 高 | `aws-lc-sys` 更新可能使补丁失效，需要手动同步 |
| **Bash/Zsh 版本漂移** | 中 | Shell 补丁针对特定 commit，新版本可能需要重新适配 |
| **Windows 补丁功能缺失** | 低 | `windows-link.patch` 只是占位，不影响功能 |

#### 6.1.2 构建系统风险

- **Hermetic 构建破坏**: `aws-lc-sys` 补丁修改编译器参数，可能影响确定性构建
- **平台特异性**: 部分补丁（如 `dsymutil` 检查）仅针对 macOS，在其他平台是 no-op

### 6.2 边界情况

#### 6.2.1 aws-lc-sys 补丁边界

```rust
// 边界: 仅处理以 "bazel-out/" 开头的路径
if arg_str.starts_with("bazel-out/") {
    *arg = execroot.join(arg_str).into_os_string();
    return;
}

// 边界: 仅处理 -B 和 -L 标志
for flag_prefix in ["-B", "-L"] {
    // ...
}
```

**未处理的情况**:
- 其他编译器标志中的相对路径（如 `-I`, `-include`）
- 非 `bazel-out/` 格式的 Bazel 路径

#### 6.2.2 Shell 补丁边界

- **环境变量长度**: 未检查 `EXEC_WRAPPER` 路径长度限制
- **参数数组边界**: `memmove` 操作假设 `args` 数组有足够空间

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加补丁版本注释**
   ```diff
   +// Patch for aws-lc-sys v0.x.x
   +// Target commit: <hash>
   +// Last verified: <date>
   ```

2. **统一补丁格式检查**
   ```bash
   # 添加 CI 检查
   git apply --check patches/*.patch
   ```

3. **文档化补丁测试流程**
   - 添加 `patches/README.md` 说明每个补丁的用途和测试方法

#### 6.3.2 中期改进

1. **自动化补丁更新检测**
   - 监控 `aws-lc-sys` 发布
   - 在 CI 中测试补丁是否仍能应用

2. **增强错误处理**
   ```rust
   // 在 aws-lc-sys 补丁中添加更多诊断信息
   if execroot.is_none() {
       eprintln!("Warning: Could not detect Bazel execroot");
   }
   ```

3. **支持更多平台**
   - 为 Windows ARM64 添加类似修复（参考 MODULE.bazel 中的 TODO 注释）

#### 6.3.3 长期改进

1. **上游化补丁**
   - 向 `aws-lc-sys` 提交 PR，添加原生 Bazel 支持选项
   - 向 `windows-link` 提交 PR，使文档包含可配置

2. **替代方案探索**
   - 使用 `crate.annotation` 的 `build_script_env` 替代部分补丁功能
   - 探索 `rules_rust` 的 `patch_tool` 选项

3. **沙箱机制重构**
   - 将 Shell 补丁机制标准化为可复用的库
   - 支持更多 Shell（fish, nushell 等）

### 6.4 测试建议

```bash
# 1. 验证补丁可应用性
cd /tmp
cargo download aws-lc-sys
git apply /home/sansha/Github/codex/patches/aws-lc-sys_memcmp_check.patch --check

# 2. Bazel 构建测试
bazel build @crates//:aws-lc-sys

# 3. Shell 补丁测试
EXEC_WRAPPER=/bin/echo bash -c 'echo test'
# 预期输出: test /bin/echo (包装器拦截成功)
```

---

## 7. 总结

`patches/` 目录是 Codex CLI 项目构建系统的关键组成部分，通过精心设计的补丁解决了以下核心问题：

1. **Hermetic 构建兼容性**: `aws-lc-sys` 补丁使加密库能在 Bazel 沙箱中构建
2. **构建简化**: `windows-link` 补丁避免了复杂的编译时文件依赖配置
3. **安全沙箱**: Shell 补丁实现了进程级权限提升控制

这些补丁体现了项目在**构建可复现性**和**安全执行**方面的工程投入，但也带来了维护负担。建议建立自动化监控和上游化流程，减少长期维护成本。
