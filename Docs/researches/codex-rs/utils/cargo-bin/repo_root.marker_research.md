# repo_root.marker 研究文档

## 场景与职责

`repo_root.marker` 是一个空的标记文件，位于 `codex-rs/utils/cargo-bin/` 目录。它是 Codex 项目中用于在运行时定位仓库根目录的关键基础设施组件。

核心职责：
1. 作为仓库根目录的锚点标记
2. 通过已知路径偏移量（向上 4 层目录）计算仓库根目录
3. 支持 Bazel runfiles 系统和 Cargo 构建系统的双模式路径解析

## 功能点目的

### 1. 仓库根目录定位

**问题**：在测试和构建过程中，经常需要知道仓库的根目录路径（例如设置 `INSTA_WORKSPACE_ROOT`、定位 fixture 文件等）。但在不同构建系统和执行环境下，确定仓库根目录并不容易。

**解决方案**：
- 在已知位置放置一个空文件 `repo_root.marker`
- 在运行时通过环境变量或 runfiles 系统找到该文件
- 从该文件位置向上回溯固定层数（4 层）到达仓库根

目录结构示意：
```
/home/sansha/Github/codex/                    ← 仓库根（目标）
├── codex-rs/                                 ← 第 4 层
│   └── utils/                                ← 第 3 层
│       └── cargo-bin/                        ← 第 2 层
│           ├── BUILD.bazel                   ← 第 1 层
│           ├── src/                          ← 第 1 层
│           └── repo_root.marker  ← 文件位置 ← 第 0 层
├── MODULE.bazel
├── Cargo.toml
└── ...
```

回溯 4 层：`repo_root.marker` → `cargo-bin/` → `utils/` → `codex-rs/` → `codex/`（仓库根）

### 2. Bazel Runfiles 集成

**目的**：使标记文件能够在 Bazel 的 runfiles 系统中被正确解析。

**实现机制**：
1. 在 `BUILD.bazel` 中导出该文件：
   ```bazel
   exports_files(["repo_root.marker"], visibility = ["//visibility:public"])
   ```

2. 配置编译期环境变量指向 runfiles 路径：
   ```bazel
   rustc_env = {
       "CODEX_REPO_ROOT_MARKER": "$(rlocationpath :repo_root.marker)",
   }
   ```

3. 在 `src/lib.rs` 中通过 runfiles 系统解析：
   ```rust
   let marker_path = option_env!("CODEX_REPO_ROOT_MARKER")?;
   let marker = runfiles::rlocation!(runfiles, &marker_path)?;
   ```

### 3. Cargo 构建兼容

**目的**：在不使用 Bazel 的纯 Cargo 构建中也能定位仓库根。

**实现机制**：
当 `RUNFILES_MANIFEST_FILE` 不存在时，回退到 `CARGO_MANIFEST_DIR` 相对路径：
```rust
} else {
    resolve_cargo_runfile(Path::new("repo_root.marker"))?
}
```

## 具体技术实现

### 文件内容

`repo_root.marker` 是一个空文件（0 字节或仅包含换行符）。其内容不重要，重要的是其存在性和位置。

### 路径解析算法

在 `src/lib.rs` 中的 `repo_root()` 函数实现：

```rust
pub fn repo_root() -> io::Result<PathBuf> {
    // 1. 获取标记文件路径
    let marker = if runfiles_available() {
        // Bazel 模式：通过 runfiles 解析
        let runfiles = runfiles::Runfiles::create()?;
        let marker_path = option_env!("CODEX_REPO_ROOT_MARKER")
            .map(PathBuf::from)
            .ok_or_else(|| ...)?;
        runfiles::rlocation!(runfiles, &marker_path)
            .ok_or_else(|| ...)?
    } else {
        // Cargo 模式：相对 CARGO_MANIFEST_DIR
        resolve_cargo_runfile(Path::new("repo_root.marker"))?
    };
    
    // 2. 向上回溯 4 层目录
    let mut root = marker;
    for _ in 0..4 {
        root = root
            .parent()
            .ok_or_else(|| ...)?
            .to_path_buf();
    }
    Ok(root)
}
```

### 使用场景

#### 1. Insta Snapshot 测试
在 `defs.bzl` 中配置测试环境：
```bazel
test_env = {
    "INSTA_WORKSPACE_ROOT": ".",
    "INSTA_SNAPSHOT_PATH": "src",
}
```

测试启动器使用 `repo_root()` 解析绝对路径，确保 Insta 在任何平台上都能正确找到 snapshot 文件。

#### 2. 工作区根测试启动器
`workspace_root_test_launcher.sh.tpl` 模板使用此标记文件：
```bash
# 解析仓库根目录并设置环境变量
INSTA_WORKSPACE_ROOT=$(realpath ...)
```

## 关键代码路径与文件引用

### 本文件引用
- 无（空文件）

### 引用本文件的代码

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `BUILD.bazel` | `exports_files(["repo_root.marker"])` | 导出为 Bazel 目标 |
| `src/lib.rs` | `option_env!("CODEX_REPO_ROOT_MARKER")` | 编译期获取 runfiles 路径 |
| `defs.bzl` | `workspace_root_marker = "//codex-rs/utils/cargo-bin:repo_root.marker"` | 配置测试规则 |

### 引用链
```
repo_root.marker (空标记文件)
    ↓
BUILD.bazel (exports_files)
    ↓
//visibility:public (全局可见)
    ↓
defs.bzl workspace_root_test (workspace_root_marker 属性)
    ↓
workspace_root_test_launcher.sh.tpl (运行时解析)
    ↓
测试进程 (INSTA_WORKSPACE_ROOT 环境变量)
```

## 依赖与外部交互

### Bazel 构建系统
- **runfiles 系统**：文件通过 `rlocationpath` 在 runfiles manifest 中注册
- **workspace_root_test 规则**：自定义规则，使用此文件定位仓库根

### Cargo 构建系统
- **CARGO_MANIFEST_DIR**：在 Cargo 构建中，文件通过相对路径 `codex-rs/utils/cargo-bin/repo_root.marker` 访问

### 运行时依赖
- `runfiles` crate：解析 Bazel runfiles 路径
- `CODEX_REPO_ROOT_MARKER` 环境变量：编译期注入的 runfiles 路径

## 风险、边界与改进建议

### 风险

1. **目录结构硬编码风险**：
   ```rust
   for _ in 0..4 { root = root.parent()?.to_path_buf(); }
   ```
   如果 `codex-rs/utils/cargo-bin/` 目录结构变化（如移动 crate 位置），回溯 4 层的假设将失效。

2. **空文件被误删除**：
   由于文件内容为空，可能在清理操作中被误认为是"无用文件"而删除。

3. **并发修改风险**：
   虽然当前是空文件，但如果未来有人向其中写入内容，可能影响路径解析（如换行符处理）。

4. **跨工作区引用**：
   如果项目被作为外部依赖（external workspace）引入，`_main` 路径前缀可能变化。

### 边界情况

1. **符号链接**：
   如果仓库根目录或路径中的任何目录是符号链接，`parent()` 操作可能产生意外结果。

2. **Windows 路径**：
   Windows 上的路径分隔符和 UNC 路径可能影响 `parent()` 的行为。

3. **Cargo 构建中的相对路径**：
   当从非标准位置运行测试时（如 `cargo test --workspace` 从子目录运行），`CARGO_MANIFEST_DIR` 可能指向子 crate 而非 `cargo-bin` crate。

### 改进建议

1. **动态根目录检测**：
   替代硬编码 4 层回溯，应该动态查找 `.git` 目录或 `MODULE.bazel` 文件：
   ```rust
   pub fn repo_root() -> io::Result<PathBuf> {
       let marker = /* ... */;
       let mut current = marker.parent();
       while let Some(dir) = current {
           if dir.join("MODULE.bazel").exists() || dir.join(".git").exists() {
               return Ok(dir.to_path_buf());
           }
           current = dir.parent();
       }
       Err(io::Error::new(...))
   }
   ```

2. **验证文件内容**：
   向 `repo_root.marker` 写入校验内容，如仓库名称或版本标识：
   ```
   codex-repo-root-v1
   ```
   运行时验证内容，防止错误定位到错误的标记文件。

3. **文档化目录假设**：
   在 `src/lib.rs` 和本文件顶部添加注释，说明目录深度假设：
   ```rust
   // WARNING: This assumes repo_root.marker is at codex-rs/utils/cargo-bin/
   // and the repo root is exactly 4 levels up. If moving this crate, update
   // the parent() loop count below.
   ```

4. **添加完整性检查**：
   在 `repo_root()` 函数中添加验证，确保找到的目录确实包含预期的文件：
   ```rust
   let root = /* ... 回溯 4 层 ... */;
   if !root.join("MODULE.bazel").exists() {
       return Err(io::Error::new(
           io::ErrorKind::NotFound,
           "Resolved path does not appear to be repo root (MODULE.bazel not found)"
       ));
   }
   Ok(root)
   ```

5. **考虑替代方案**：
   - 使用 `git rev-parse --show-toplevel`（需要 git 命令）
   - 在编译期通过 build script 检测并硬编码路径
   - 使用 `CARGO_MANIFEST_DIR` 结合 `../../..` 相对路径（仅限 Cargo）
