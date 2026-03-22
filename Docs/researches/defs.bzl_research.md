# defs.bzl 文件研究文档

## 场景与职责

defs.bzl 是 Bazel 构建系统的核心 Starlark 扩展文件，为 OpenAI Codex 项目提供：
- **Rust 项目构建抽象**: 封装 Cargo 和 Bazel 的构建差异
- **跨平台二进制文件生成**: 支持多平台发布构建
- **测试基础设施**: 统一的单元测试和集成测试规则
- **工作区根目录测试**: 支持从工作区根目录运行测试

## 功能点目的

### 1. 核心宏和规则
| 组件 | 类型 | 用途 |
|------|------|------|
| `multiplatform_binaries` | 宏 | 为多个平台生成二进制文件 |
| `workspace_root_test` | 规则 | 在工作区根目录运行测试 |
| `codex_rust_crate` | 宏 | 统一的 Rust crate 构建 |

### 2. 支持平台
```python
PLATFORMS = [
    "linux_arm64_musl",
    "linux_amd64_musl",
    "macos_amd64",
    "macos_arm64",
    "windows_amd64",
    "windows_arm64",
]
```

### 3. 构建目标矩阵
```
codex_rust_crate
├── Library (rust_library/rust_proc_macro)
├── Binaries (rust_binary) × N
├── Unit Tests (rust_test + workspace_root_test)
└── Integration Tests (rust_test) × N
```

## 具体技术实现

### 1. 多平台二进制文件生成

#### `multiplatform_binaries` 宏
```python
def multiplatform_binaries(name, platforms = PLATFORMS):
    for platform in platforms:
        platform_data(
            name = name + "_" + platform,
            platform = "@llvm//platforms:" + platform,
            target = name,
            tags = ["manual"],
        )

    native.filegroup(
        name = "release_binaries",
        srcs = [name + "_" + platform for platform in platforms],
        tags = ["manual"],
    )
```

**关键实现点**:
- 使用 `platform_data` 规则为每个平台创建特定配置
- `tags = ["manual"]` 防止在 `bazel build //...` 时自动构建
- `release_binaries` filegroup 聚合所有平台二进制文件

### 2. 工作区根目录测试

#### `workspace_root_test` 规则
```python
def _workspace_root_test_impl(ctx):
    is_windows = ctx.target_platform_has_constraint(
        ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]
    )
    launcher = ctx.actions.declare_file(
        ctx.label.name + ".bat" if is_windows else ctx.label.name
    )
    
    # 展开模板（Bash 或 Batch）
    ctx.actions.expand_template(
        template = launcher_template,
        output = launcher,
        is_executable = True,
        substitutions = {
            "__TEST_BIN__": test_bin.short_path,
            "__WORKSPACE_ROOT_MARKER__": workspace_root_marker.short_path,
        },
    )
    
    return [
        DefaultInfo(executable = launcher, ...),
        RunEnvironmentInfo(environment = ctx.attr.env),
    ]
```

**设计目的**:
- 解决 Insta 快照测试需要工作区根目录的问题
- 支持 macOS 等 manifest-only 平台
- 统一 Linux/macOS/Windows 的测试行为

**模板文件**:
- `workspace_root_test_launcher.sh.tpl` (Unix)
- `workspace_root_test_launcher.bat.tpl` (Windows)

### 3. Rust Crate 统一构建

#### `codex_rust_crate` 宏
这是项目最核心的构建宏，提供 20+ 参数支持复杂构建场景：

```python
def codex_rust_crate(
    name,                    # Bazel 目标名
    crate_name,             # Cargo crate 名
    crate_features = [],    # Cargo features
    crate_srcs = None,      # 显式源文件列表
    crate_edition = None,   # Rust edition 覆盖
    proc_macro = False,     # 是否为 proc-macro
    build_script_enabled = True,   # 启用 build.rs
    build_script_data = [],        # build.rs 数据文件
    compile_data = [],             # 编译时数据
    lib_data_extra = [],           # 库额外运行时数据
    rustc_flags_extra = [],        # 额外 rustc 标志
    rustc_env = {},                # rustc 环境变量
    deps_extra = [],               # 额外依赖
    integration_compile_data_extra = [],  # 集成测试编译数据
    test_data_extra = [],          # 测试额外数据
    test_tags = [],                # 测试标签
    extra_binaries = [],           # 额外二进制文件
):
```

**构建流程**:
```
codex_rust_crate("tui", "codex_tui")
├── 1. 解析 DEP_DATA 获取二进制文件列表
├── 2. 收集源文件 (src/**/*.rs)
├── 3. 处理 build.rs (如存在)
│   └── cargo_build_script(name="tui-build-script")
├── 4. 构建库 (rust_library/rust_proc_macro)
│   └── name="tui", crate_name="codex_tui"
├── 5. 创建单元测试
│   ├── rust_test(name="tui-unit-tests-bin")
│   └── workspace_root_test(name="tui-unit-tests")
├── 6. 构建二进制文件
│   └── rust_binary(name="codex-tui") × N
└── 7. 创建集成测试
    └── rust_test(name="tui-<test>-test") × N
```

**关键特性**:

1. **路径重映射** (解决 Bazel/Cargo 路径差异):
```python
rustc_flags = rustc_flags_extra + [
    "--remap-path-prefix=../codex-rs=",
    "--remap-path-prefix=codex-rs=",
]
```

2. **Insta 环境配置**:
```python
test_env = {
    "INSTA_WORKSPACE_ROOT": ".",
    "INSTA_SNAPSHOT_PATH": "src",
}
```

3. **Cargo 二进制文件环境变量**:
```python
cargo_env = {}
for binary, main in binaries.items():
    cargo_env["CARGO_BIN_EXE_" + binary] = "$(rlocationpath :%s)" % binary
```

### 4. 依赖管理

#### 外部依赖加载
```python
load("@crates//:data.bzl", "DEP_DATA")
load("@crates//:defs.bzl", "all_crate_deps")
```

**DEP_DATA 结构** (由 `rules_rs` 生成):
```python
DEP_DATA = {
    "tui": {
        "binaries": {
            "codex-tui": "src/main.rs",
            # ...
        }
    }
}
```

## 关键代码路径与文件引用

### 相关文件
| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/defs.bzl` | 本文件 |
| `/home/sansha/Github/codex/MODULE.bazel` | Bazel 模块配置 |
| `/home/sansha/Github/codex/BUILD.bazel` | 根构建文件 |
| `/home/sansha/Github/codex/workspace_root_test_launcher.sh.tpl` | Unix 测试启动器模板 |
| `/home/sansha/Github/codex/workspace_root_test_launcher.bat.tpl` | Windows 测试启动器模板 |
| `/home/sansha/Github/codex/rbe.bzl` | 远程执行平台配置 |
| `codex-rs/*/BUILD.bazel` | 各 crate 的构建文件 |

### 使用示例
```python
# codex-rs/tui/BUILD.bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "tui",
    crate_name = "codex_tui",
    compile_data = ["styles.md"],
    test_data_extra = ["tests/snapshots/"],
)
```

### 构建命令
```bash
# 构建特定 crate
bazel build //codex-rs/tui

# 运行测试
bazel test //codex-rs/tui:tui-unit-tests

# 构建发布二进制文件
bazel build //codex-rs/cli:release_binaries --config=remote

# 运行集成测试
bazel test //codex-rs/core:core-integration-test
```

## 依赖与外部交互

### Bazel 生态系统
```
defs.bzl
├── rules_rust ────────────────────┐
│   ├── rust_library               │
│   ├── rust_binary                │
│   ├── rust_test                  │
│   └── cargo_build_script         │
├── rules_platform ────────────────┤
│   └── platform_data              │
├── @crates (rules_rs 生成) ───────┤
│   ├── DEP_DATA                   │
│   └── all_crate_deps()           │
└── 本地规则 ──────────────────────┘
    ├── workspace_root_test
    └── multiplatform_binaries
```

### 与 Cargo 的互操作
| 方面 | Bazel | Cargo | 桥接方式 |
|------|-------|-------|---------|
| 依赖解析 | `MODULE.bazel` + `rules_rs` | `Cargo.lock` | `crate.from_cargo()` |
| 构建脚本 | `cargo_build_script` | `build.rs` | 原生支持 |
| 特性 | `crate_features` 参数 | `[features]` | 显式传递 |
| 环境变量 | `rustc_env` | `build.rs` 设置 | 显式配置 |

### 与 CI/CD 集成
```yaml
# .github/workflows/bazel.yml
- name: bazel test //...
  run: |
    bazel test //... \
      --test_verbose_timeout_warnings \
      --build_metadata=REPO_URL=https://github.com/openai/codex.git
```

## 风险、边界与改进建议

### 风险

#### 1. 复杂性和学习曲线
| 风险 | 说明 | 缓解措施 |
|------|------|---------|
| Starlark 语法 | 团队成员需要学习 Bazel/Starlark | 文档和培训 |
| 调试困难 | 构建失败信息难以理解 | 改进错误消息 |
| 增量构建问题 | 缓存失效可能导致全量重建 | 监控和优化 |

#### 2. 与 Cargo 的差异
```python
# 问题示例：Bazel 和 Cargo 的路径处理不同
# Bazel: bazel-out/k8-fastbuild/bin/codex-rs/tui/...
# Cargo: target/debug/...

# 解决方案：路径重映射
"--remap-path-prefix=../codex-rs=",
"--remap-path-prefix=codex-rs=",
```

#### 3. 平台特定问题
- Windows 路径长度限制
- macOS 沙箱行为差异
- Linux musl 交叉编译复杂性

### 边界

#### 功能边界
- 不支持 Cargo workspace 的所有特性
- 某些 `build.rs` 场景需要手动配置
- 跨 crate 依赖需要显式声明

#### 平台边界
- Windows ARM64 支持实验性
- 某些平台特定的 crate 需要条件编译

### 改进建议

#### 1. 添加文档生成
```python
def codex_rust_crate(name, crate_name, **kwargs):
    """Defines a Rust crate with library, binaries, and tests.
    
    Args:
        name: Bazel target name for the library
        crate_name: Cargo crate name from Cargo.toml
        crate_features: Cargo features to enable
        ...
    
    Example:
        codex_rust_crate(
            name = "core",
            crate_name = "codex_core",
            crate_features = ["full"],
        )
    """
```

#### 2. 添加构建诊断
```python
def _codex_rust_crate_diagnostic(name, crate_name, **kwargs):
    """验证 crate 配置的一致性。"""
    # 检查 crate_name 与 Cargo.toml 匹配
    # 检查 features 有效性
    # 检查依赖版本兼容性
    pass
```

#### 3. 改进测试发现
```python
# 当前：需要显式列出测试文件
for test in native.glob(["tests/*.rs"], allow_empty = True):
    ...

# 建议：支持测试模块发现
# tests/
#   ├── integration_test.rs
#   └── unit/
#       └── utils_test.rs
```

#### 4. 添加性能分析支持
```python
def codex_rust_crate(name, enable_profiling = False, **kwargs):
    if enable_profiling:
        rustc_flags_extra = kwargs.get("rustc_flags_extra", []) + [
            "-C", "profile-generate=/tmp/pgo",
        ]
```

#### 5. 改进错误消息
```python
# 当 DEP_DATA 缺失时提供有用的错误
def _get_dep_data(package_name):
    if package_name not in DEP_DATA:
        fail("""
Package '{package_name}' not found in DEP_DATA.
Make sure:
1. The package has a Cargo.toml
2. You ran 'just bazel-lock-update' after adding the package
3. The package name matches between Bazel and Cargo
""".format(package_name = package_name))
    return DEP_DATA[package_name]
```

#### 6. 支持更多测试类型
```python
def codex_rust_crate(
    name,
    # ... 现有参数
    benchmark_tests = False,      # 添加 benchmark 支持
    doc_tests = True,             # 控制文档测试
    ui_tests = [],                # UI 测试（快照）
):
```

#### 7. 添加构建缓存优化
```python
# 支持 sccache 集成
def codex_rust_crate(name, use_sccache = None, **kwargs):
    if use_sccache == None:
        use_sccache = "SCCACHE_BUCKET" in ctx.os.environ
    
    if use_sccache:
        rustc_flags_extra = kwargs.get("rustc_flags_extra", []) + [
            "-C", "llvm-args=-cache-dir=/tmp/sccache",
        ]
```

### 维护建议

#### 定期审计
- 检查未使用的 `crate_features`
- 验证 `deps_extra` 是否仍然需要
- 审查 `test_tags` 的合理性

#### 与 Cargo 保持同步
```bash
# 建议的同步流程
1. 更新 Cargo.toml
2. 运行 cargo check（验证）
3. 运行 just bazel-lock-update
4. 验证 Bazel 构建
5. 提交 MODULE.bazel.lock 变更
```
