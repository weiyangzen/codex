# build.rs 研究文档

## 场景与职责

`build.rs` 是 `codex-linux-sandbox` crate 的 Cargo 构建脚本，负责在编译时检测环境、编译 vendored bubblewrap C 代码，并生成必要的配置文件。它是 Cargo 构建路径（与 Bazel 构建路径相对）的关键组件。

## 功能点目的

### 1. 构建配置声明

```rust
println!("cargo:rustc-check-cfg=cfg(vendored_bwrap_available)");
println!("cargo:rerun-if-env-changed=CODEX_BWRAP_SOURCE_DIR");
println!("cargo:rerun-if-env-changed=PKG_CONFIG_ALLOW_CROSS");
println!("cargo:rerun-if-env-changed=PKG_CONFIG_PATH");
println!("cargo:rerun-if-env-changed=PKG_CONFIG_SYSROOT_DIR");
```

**功能说明：**
- `rustc-check-cfg`: 声明 `vendored_bwrap_available` 是预期的 cfg 值，避免编译器警告
- `rerun-if-env-changed`: 当指定环境变量变化时，Cargo 会自动重新运行 build.rs

### 2. 源码变更检测

```rust
let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
let vendor_dir = manifest_dir.join("../vendor/bubblewrap");
println!("cargo:rerun-if-changed={}", vendor_dir.join("bubblewrap.c").display());
println!("cargo:rerun-if-changed={}", vendor_dir.join("bind-mount.c").display());
println!("cargo:rerun-if-changed={}", vendor_dir.join("network.c").display());
println!("cargo:rerun-if-changed={}", vendor_dir.join("utils.c").display());
```

**目的：** 当 vendored bubblewrap 源码变化时自动重新编译

### 3. 平台检测与条件编译

```rust
let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
if target_os != "linux" {
    return;
}
```

**设计决策：** 非 Linux 目标直接返回，不编译 C 代码。这意味着：
- 非 Linux 平台不会设置 `vendored_bwrap_available`
- `src/vendored_bwrap.rs` 中的非 Linux 实现会 panic

### 4. Vendored Bubblewrap 编译

#### 4.1 源码目录解析

```rust
fn resolve_bwrap_source_dir(manifest_dir: &Path) -> Result<PathBuf, String> {
    // 优先级 1: CODEX_BWRAP_SOURCE_DIR 环境变量
    if let Ok(path) = env::var("CODEX_BWRAP_SOURCE_DIR") {
        let src_dir = PathBuf::from(path);
        if src_dir.exists() {
            return Ok(src_dir);
        }
        return Err(format!("CODEX_BWRAP_SOURCE_DIR was set but does not exist: {}", ...));
    }

    // 优先级 2: 默认 vendored 路径
    let vendor_dir = manifest_dir.join("../vendor/bubblewrap");
    if vendor_dir.exists() {
        return Ok(vendor_dir);
    }

    Err(format!("expected vendored bubblewrap at {}...", ...))
}
```

**优先级：**
1. `CODEX_BWRAP_SOURCE_DIR` 环境变量（允许开发者使用自定义 bubblewrap）
2. `codex-rs/vendor/bubblewrap` 默认路径

#### 4.2 libcap 检测

```rust
let libcap = pkg_config::Config::new()
    .probe("libcap")
    .map_err(|err| format!("libcap not available via pkg-config: {err}"))?;
```

**依赖：** Linux capabilities 库，bubblewrap 需要它进行特权操作

#### 4.3 config.h 生成

```rust
let config_h = out_dir.join("config.h");
std::fs::write(
    &config_h,
    r#"#pragma once
#define PACKAGE_STRING "bubblewrap built at codex build-time"
"#,
)
.map_err(|err| format!("failed to write {}: {err}", config_h.display()))?;
```

**注意：** 生成的 `config.h` 仅包含最小配置，与静态 `config.h` 文件（在源码树中）内容相同

#### 4.4 C 代码编译

```rust
let mut build = cc::Build::new();
build
    .file(src_dir.join("bubblewrap.c"))
    .file(src_dir.join("bind-mount.c"))
    .file(src_dir.join("network.c"))
    .file(src_dir.join("utils.c"))
    .include(&out_dir)      // 包含生成的 config.h
    .include(&src_dir)      // 包含 bubblewrap 头文件
    .define("_GNU_SOURCE", None)           // 启用 GNU 扩展
    .define("main", Some("bwrap_main"));   // 重命名 main 函数

// 添加 libcap 头文件路径（使用 -idirafter 确保 sysroot 头文件优先）
for include_path in libcap.include_paths {
    build.flag(format!("-idirafter{}", include_path.display()));
}

build.compile("build_time_bwrap");
println!("cargo:rustc-cfg=vendored_bwrap_available");
```

**关键编译选项：**

| 选项 | 说明 |
|------|------|
| `_GNU_SOURCE` | 启用 GNU 扩展（如 `asprintf`, `getline` 等） |
| `main=bwrap_main` | 将 bubblewrap 的 `main` 重命名为 `bwrap_main`，以便通过 FFI 调用 |
| `-idirafter` | 将 libcap 头文件路径放在系统头文件之后，避免 musl 交叉构建冲突 |

## 关键代码路径与文件引用

### 编译流程

```
build.rs
├── 平台检测 (target_os == "linux")
│   └── 非 Linux: 直接返回
│
├── 解析源码目录
│   ├── CODEX_BWRAP_SOURCE_DIR (环境变量)
│   └── ../vendor/bubblewrap (默认)
│
├── 检测 libcap (pkg-config)
│
├── 生成 config.h → OUT_DIR/config.h
│
├── 编译 C 代码 (cc::Build)
│   ├── bubblewrap.c
│   ├── bind-mount.c
│   ├── network.c
│   └── utils.c
│
└── 设置 cfg(vendored_bwrap_available)
```

### 与源码的交互

```
OUT_DIR/
├── config.h (生成) ──────┐
└── libbuild_time_bwrap.a  │
                           │
src/vendored_bwrap.rs      │
├── #[cfg(vendored_bwrap_available)] ───┘
│   └── extern "C" { fn bwrap_main(...) }
│
└── #[cfg(not(vendored_bwrap_available))]
    └── panic!("build-time bubblewrap is not available")
```

### 引用的外部文件

| 文件 | 路径 | 用途 |
|------|------|------|
| bubblewrap.c | `codex-rs/vendor/bubblewrap/bubblewrap.c` | 主程序逻辑 |
| bind-mount.c | `codex-rs/vendor/bubblewrap/bind-mount.c` | 绑定挂载实现 |
| network.c | `codex-rs/vendor/bubblewrap/network.c` | 网络设置 |
| utils.c | `codex-rs/vendor/bubblewrap/utils.c` | 工具函数 |
| config.h | 静态: `codex-rs/linux-sandbox/config.h`<br>生成: `OUT_DIR/config.h` | 构建配置 |

## 依赖与外部交互

### 构建依赖 (build-dependencies)

| Crate | 版本 | 用途 |
|-------|------|------|
| `cc` | "1" | C 代码编译 |
| `pkg-config` | "0.3" | 系统库检测 |

### 系统依赖

| 依赖 | 检测方式 | 必需 |
|------|---------|------|
| libcap | pkg-config | 是 |
| C 编译器 | cc crate 自动检测 | 是 |

### 环境变量

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `CODEX_BWRAP_SOURCE_DIR` | 自定义 bubblewrap 源码路径 | `../vendor/bubblewrap` |
| `PKG_CONFIG_ALLOW_CROSS` | 允许交叉编译 | - |
| `PKG_CONFIG_PATH` | pkg-config 搜索路径 | - |
| `PKG_CONFIG_SYSROOT_DIR` | 交叉编译 sysroot | - |
| `CARGO_MANIFEST_DIR` | Cargo 提供，manifest 目录 | - |
| `CARGO_CFG_TARGET_OS` | Cargo 提供，目标 OS | - |
| `OUT_DIR` | Cargo 提供，输出目录 | - |

## 风险、边界与改进建议

### 风险点

1. **构建失败场景：**
   - 系统缺少 libcap 开发包（`libcap-dev` 或 `libcap-devel`）
   - pkg-config 配置错误
   - C 编译器不可用

2. **交叉编译复杂性：**
   - 需要正确配置 `PKG_CONFIG_SYSROOT_DIR`
   - musl 交叉构建需要特殊处理头文件优先级

3. **与 Bazel 的差异：**
   - Bazel 构建禁用 `build.rs` (`build_script_enabled = False`)
   - 两种构建路径可能产生不一致的结果

### 边界条件

| 场景 | 行为 |
|------|------|
| 非 Linux 目标 | 直接返回，不设置 `vendored_bwrap_available` |
| `CODEX_BWRAP_SOURCE_DIR` 指向不存在路径 | 返回错误，构建失败 |
| libcap 检测失败 | 返回错误，构建失败 |
| 默认 vendor 路径不存在 | 返回错误，构建失败 |

### 改进建议

1. **错误信息优化：**
   ```rust
   // 当前
   .map_err(|err| format!("libcap not available via pkg-config: {err}"))?;
   
   // 建议：添加安装指导
   .map_err(|err| format!(
       "libcap not available via pkg-config: {err}\n\
        Please install libcap development package:\n\
        - Debian/Ubuntu: apt-get install libcap-dev\n\
        - RHEL/CentOS: yum install libcap-devel\n\
        - Arch: pacman -S libcap"
   ))?;
   ```

2. **可选功能支持：**
   - 考虑添加 feature flag 允许禁用 vendored bubblewrap
   - 允许纯系统 bwrap 模式（不编译 C 代码）

3. **缓存优化：**
   - 考虑检测系统 bwrap 版本，如果兼容则跳过 vendored 编译
   - 减少不必要的构建时间

4. **与 Bazel 统一：**
   - 考虑将 C 编译逻辑抽取到共享脚本
   - 或提供 Bazel 风格的工具链配置

5. **config.h 增强：**
   - 当前只包含 `PACKAGE_STRING`
   - 可考虑添加版本信息、构建时间等元数据
