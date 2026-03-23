# BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中 `codex-rs/linux-sandbox` crate 的构建配置文件。该文件定义了如何在 Bazel 构建环境下编译 Rust 代码以及如何处理 vendored bubblewrap C 代码的集成。

## 功能点目的

### 1. Rust Crate 定义 (`codex_rust_crate`)

```bazel
codex_rust_crate(
    name = "linux-sandbox",
    crate_name = "codex_linux_sandbox",
    build_script_enabled = False,
    deps_extra = select({
        "@platforms//os:linux": [":vendored-bwrap-ffi"],
        "//conditions:default": [],
    }),
    rustc_flags_extra = select({
        "@platforms//os:linux": ["--cfg=vendored_bwrap_available"],
        "//conditions:default": [],
    }),
)
```

**关键设计决策：**
- `build_script_enabled = False`: Bazel 跳过 Cargo 的 `build.rs`，因为 Bazel 通过 `:vendored-bwrap-ffi` 目标直接管理 bubblewrap 的编译
- `deps_extra`: 仅在 Linux 平台下链接 vendored bubblewrap FFI 库
- `rustc_flags_extra`: 在 Linux 平台下设置 `vendored_bwrap_available` cfg 标志，启用 vendored bwrap 功能

### 2. Vendored Bubblewrap C 库 (`cc_library`)

```bazel
cc_library(
    name = "vendored-bwrap-ffi",
    srcs = ["//codex-rs/vendor:bubblewrap_c_sources"],
    hdrs = [
        "config.h",
        "//codex-rs/vendor:bubblewrap_headers",
    ],
    copts = [
        "-D_GNU_SOURCE",
        "-Dmain=bwrap_main",
    ],
    includes = ["."],
    deps = ["@libcap//:libcap"],
    target_compatible_with = ["@platforms//os:linux"],
    visibility = ["//visibility:private"],
)
```

**关键编译选项：**
- `-D_GNU_SOURCE`: 启用 GNU 扩展功能
- `-Dmain=bwrap_main`: 将 bubblewrap 的 `main` 函数重命名为 `bwrap_main`，以便通过 FFI 调用
- `includes = ["."]`: 包含当前目录，使 `config.h` 可被找到
- `deps = ["@libcap//:libcap"]`: 依赖 libcap 库用于 Linux capabilities

## 具体技术实现

### 条件编译策略

Bazel 使用 `select()` 实现平台特定的构建逻辑：

| 平台 | deps_extra | rustc_flags_extra |
|------|-----------|-------------------|
| Linux | `:vendored-bwrap-ffi` | `--cfg=vendored_bwrap_available` |
| 其他 | `[]` | `[]` |

### 与 Cargo 构建的差异

| 方面 | Cargo (build.rs) | Bazel |
|------|-----------------|-------|
| Bubblewrap 编译 | 通过 `cc` crate 在 build.rs 中编译 | 通过 `cc_library` 规则预编译 |
| config.h 生成 | 在 OUT_DIR 中动态生成 | 使用静态 `config.h` 文件 |
| libcap 检测 | 通过 `pkg-config` 动态检测 | 通过 Bazel 依赖 `@libcap//:libcap` |

## 关键代码路径与文件引用

### 依赖关系

```
BUILD.bazel
├── codex_rust_crate (:linux-sandbox)
│   └── 依赖 :vendored-bwrap-ffi (Linux only)
│       ├── srcs: //codex-rs/vendor:bubblewrap_c_sources
│       │   ├── bubblewrap.c
│       │   ├── bind-mount.c
│       │   ├── network.c
│       │   └── utils.c
│       ├── hdrs: config.h (本地)
│       └── hdrs: //codex-rs/vendor:bubblewrap_headers
│           ├── bind-mount.h
│           ├── network.h
│           └── utils.h
└── @libcap//:libcap (外部依赖)
```

### 引用的外部目标

- `//:defs.bzl`: 定义 `codex_rust_crate` 宏
- `//codex-rs/vendor:bubblewrap_c_sources`: vendored bubblewrap C 源文件
- `//codex-rs/vendor:bubblewrap_headers`: vendored bubblewrap 头文件
- `@libcap//:libcap`: libcap 库（Bazel 外部依赖）

## 依赖与外部交互

### 外部依赖

1. **rules_cc**: Bazel 的 C/C++ 规则集
2. **libcap**: Linux capabilities 库，用于 bubblewrap 的特权操作
3. **platforms**: Bazel 的平台检测规则

### 与 Rust 代码的交互

- `vendored_bwrap_available` cfg 标志控制 `src/vendored_bwrap.rs` 中的条件编译
- FFI 符号 `bwrap_main` 在 `src/vendored_bwrap.rs` 中被调用

## 风险、边界与改进建议

### 风险点

1. **平台兼容性**: 仅在 Linux 平台启用完整功能，其他平台功能受限
2. **Bazel/Cargo 差异**: 两种构建系统的行为可能产生差异，需要保持同步
3. **libcap 依赖**: 需要确保 Bazel 工作区正确配置 libcap

### 边界条件

- `target_compatible_with` 确保 `:vendored-bwrap-ffi` 仅在 Linux 上构建
- `visibility = ["//visibility:private"]` 限制 `:vendored-bwrap-ffi` 仅在本包内使用

### 改进建议

1. **统一构建逻辑**: 考虑将 `build.rs` 和 Bazel 的编译逻辑抽取到共享的脚本中
2. **更好的错误处理**: 在非 Linux 平台提供更清晰的降级行为说明
3. **文档同步**: 确保 Bazel 和 Cargo 构建的文档保持一致
