# rust-ci.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流是 Rust 代码库的核心 CI 流程，负责在多个平台和架构上执行代码格式检查、lint、构建和测试。它是保证 codex-rs 代码质量和跨平台兼容性的关键基础设施。

## 功能点目的

1. **变更检测**：智能检测变更范围，避免不必要的构建
2. **代码质量**：fmt、clippy、自定义 lint（argument-comment-lint）
3. **多平台验证**：Linux (x86_64/ARM64)、macOS (x86_64/ARM64)、Windows (x86_64/ARM64)
4. **构建优化**：sccache 缓存、cargo-chef 依赖预编译
5. **musl 支持**：静态链接构建支持

## 具体技术实现

### 触发条件
```yaml
on:
  pull_request: {}
  push:
    branches:
      - main
  workflow_dispatch:
```

### Job 1: changed（变更检测）

```yaml
- name: Detect changed paths
  run: |
    if [[ "${{ github.event_name }}" == "pull_request" ]]; then
      BASE_SHA='${{ github.event.pull_request.base.sha }}'
      HEAD_SHA='${{ github.event.pull_request.head.sha }}'
      mapfile -t files < <(git diff --name-only --no-renames "$BASE_SHA" "$HEAD_SHA")
    else
      files=("codex-rs/force" ".github/force")
    fi
    
    for f in "${files[@]}"; do
      [[ $f == codex-rs/* ]] && codex=true
      [[ $f == codex-rs/* || $f == tools/argument-comment-lint/* || $f == justfile ]] && argument_comment_lint=true
      [[ $f == tools/argument-comment-lint/* || $f == .github/workflows/rust-ci.yml ]] && argument_comment_lint_package=true
      [[ $f == .github/* ]] && workflows=true
    done
```

输出变量：
| 变量 | 说明 |
|------|------|
| `codex` | codex-rs 目录有变更 |
| `argument_comment_lint` | 需要运行 argument-comment-lint |
| `argument_comment_lint_package` | 需要测试 lint 包本身 |
| `workflows` | 工作流文件有变更 |

### Job 2: general（格式检查）

```yaml
cargo fmt -- --config imports_granularity=Item --check
```
- 使用 `imports_granularity=Item` 统一导入格式

### Job 3: cargo_shear（未使用依赖检测）

```yaml
- uses: taiki-e/install-action@44c6d64aa62cd779e873306675c7a58e86d6d532
  with:
    tool: cargo-shear
    version: 1.5.1
- run: cargo shear
```
- `cargo-shear`：检测 `Cargo.toml` 中未使用的依赖

### Job 4: argument_comment_lint（自定义 Lint）

```yaml
- uses: dtolnay/rust-toolchain@1.93.0
  with:
    toolchain: nightly-2025-09-18
    components: llvm-tools-preview, rustc-dev, rust-src

- name: Cache cargo-dylint tooling
  uses: actions/cache@v5
  with:
    path: |
      ~/.cargo/bin/cargo-dylint
      ~/.cargo/bin/dylint-link
      ...
    key: argument-comment-lint-${{ runner.os }}-${{ hashFiles(...) }}

- name: Install cargo-dylint tooling
  run: cargo install --locked cargo-dylint dylint-link

- name: Run argument comment lint on codex-rs
  run: ./tools/argument-comment-lint/run.sh
```

- 使用 nightly 工具链（dylint 需要）
- 缓存 dylint 工具避免重复安装
- 运行自定义 lint 检查参数注释

### Job 5: lint_build（Lint 和构建）

#### 构建矩阵
```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      # macOS dev
      - runner: macos-15-xlarge
        target: aarch64-apple-darwin
        profile: dev
      - runner: macos-15-xlarge
        target: x86_64-apple-darwin
        profile: dev
      
      # Linux dev
      - runner: ubuntu-24.04
        target: x86_64-unknown-linux-musl
        profile: dev
        runs_on:
          group: codex-runners
          labels: codex-linux-x64
      
      # Linux release（代表性检查）
      - runner: ubuntu-24.04
        target: x86_64-unknown-linux-musl
        profile: release
        runs_on:
          group: codex-runners
          labels: codex-linux-x64
      
      # Windows dev/release
      - runner: windows-x64
        target: x86_64-pc-windows-msvc
        profile: dev
        runs_on:
          group: codex-runners
          labels: codex-windows-x64
```

#### 环境变量
```yaml
env:
  USE_SCCACHE: ${{ startsWith(matrix.runner, 'windows') && 'false' || 'true' }}
  CARGO_INCREMENTAL: "0"
  SCCACHE_CACHE_SIZE: 10G
  CARGO_PROFILE_RELEASE_LTO: ${{ matrix.profile == 'release' && 'thin' || 'fat' }}
```

| 变量 | 说明 |
|------|------|
| `USE_SCCACHE` | Windows 禁用 sccache |
| `CARGO_INCREMENTAL` | 禁用增量编译（CI 中无效） |
| `SCCACHE_CACHE_SIZE` | sccache 缓存大小 10GB |
| `CARGO_PROFILE_RELEASE_LTO` | release 构建使用 thin LTO |

#### 缓存策略
```yaml
- name: Restore cargo home cache
  uses: actions/cache/restore@v5
  with:
    path: |
      ~/.cargo/bin/
      ~/.cargo/registry/index/
      ~/.cargo/registry/cache/
      ~/.cargo/git/db/
    key: cargo-home-${{ matrix.runner }}-${{ matrix.target }}-${{ matrix.profile }}-${{ steps.lockhash.outputs.hash }}-${{ steps.lockhash.outputs.toolchain_hash }}
```

- 基于 `Cargo.lock` 和 `rust-toolchain.toml` 的 hash 生成缓存 key
- 使用 `restore-keys` 实现部分匹配

#### sccache 配置
```yaml
- name: Configure sccache backend
  run: |
    if [[ -n "${ACTIONS_CACHE_URL:-}" && -n "${ACTIONS_RUNTIME_TOKEN:-}" ]]; then
      echo "SCCACHE_GHA_ENABLED=true" >> "$GITHUB_ENV"
    else
      echo "SCCACHE_GHA_ENABLED=false" >> "$GITHUB_ENV"
      echo "SCCACHE_DIR=${{ github.workspace }}/.sccache" >> "$GITHUB_ENV"
    fi

- name: Enable sccache wrapper
  run: echo "RUSTC_WRAPPER=sccache" >> "$GITHUB_ENV"
```

- 优先使用 GitHub Actions 缓存后端
- 回退到本地磁盘缓存

#### musl 特殊处理
```yaml
- name: Use hermetic Cargo home (musl)
  run: |
    cargo_home="${GITHUB_WORKSPACE}/.cargo-home"
    mkdir -p "${cargo_home}/bin"
    echo "CARGO_HOME=${cargo_home}" >> "$GITHUB_ENV"
    echo "${cargo_home}/bin" >> "$GITHUB_PATH"

- name: Install musl build tools
  run: bash "${GITHUB_WORKSPACE}/.github/scripts/install-musl-build-tools.sh"

- name: Configure rustc UBSan wrapper (musl host)
  run: |
    ubsan="$(ldconfig -p | grep -m1 'libubsan\.so\.1' | sed -E 's/.*=> (.*)$/\1/')"
    cat > "${wrapper}" <<EOF
    #!/usr/bin/env bash
    export LD_PRELOAD="${ubsan}\${LD_PRELOAD:+:\${LD_PRELOAD}}"
    exec "\$1" "\${@:2}"
    EOF
    echo "RUSTC_WRAPPER=${wrapper}" >> "$GITHUB_ENV"
```

- 隔离的 Cargo home 避免与主机冲突
- 安装 musl 工具链和 libcap
- UBSan 包装器处理未定义行为检测

#### cargo-chef 依赖预编译
```yaml
- name: Pre-warm dependency cache (cargo-chef)
  if: ${{ matrix.profile == 'release' }}
  run: |
    RECIPE="${RUNNER_TEMP}/chef-recipe.json"
    cargo chef prepare --recipe-path "$RECIPE"
    cargo chef cook --recipe-path "$RECIPE" --target ${{ matrix.target }} --release --all-features
```

- 仅用于 release 构建
- `cargo chef prepare` 生成依赖配方
- `cargo chef cook` 预编译依赖，利用缓存

#### Clippy 执行
```yaml
- name: cargo clippy
  run: cargo clippy --target ${{ matrix.target }} --all-features --tests --profile ${{ matrix.profile }} --timings -- -D warnings
```

- `--all-features`：启用所有特性
- `--tests`：检查测试代码
- `-D warnings`：警告视为错误
- `--timings`：生成构建时间报告

### Job 6: tests（测试执行）

```yaml
- name: tests
  id: test
  run: cargo nextest run --all-features --no-fail-fast --target ${{ matrix.target }} --cargo-profile ci-test --timings
  env:
    RUST_BACKTRACE: 1
    NEXTEST_STATUS_LEVEL: leak
```

- 使用 `cargo nextest` 替代 `cargo test`（更快、更好的输出）
- `--no-fail-fast`：运行所有测试，不中断
- `--cargo-profile ci-test`：使用 CI 专用 profile
- `NEXTEST_STATUS_LEVEL: leak`：显示泄漏检测状态

#### Linux 命名空间配置
```yaml
- name: Enable unprivileged user namespaces (Linux)
  if: runner.os == 'Linux'
  run: |
    sudo sysctl -w kernel.unprivileged_userns_clone=1
    if sudo sysctl -a 2>/dev/null | grep -q '^kernel.apparmor_restrict_unprivileged_userns'; then
      sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
    fi
```

- 启用非特权用户命名空间（bubblewrap 沙箱需要）
- 禁用 AppArmor 对非特权命名空间的限制

### Job 7: results（结果汇总）

```yaml
needs: [changed, general, cargo_shear, argument_comment_lint, lint_build, tests]
if: always()

- name: Summarize
  run: |
    echo "arglint: ${{ needs.argument_comment_lint.result }}"
    echo "general: ${{ needs.general.result }}"
    echo "shear  : ${{ needs.cargo_shear.result }}"
    echo "lint   : ${{ needs.lint_build.result }}"
    echo "tests  : ${{ needs.tests.result }}"
    
    # 根据变更范围决定检查哪些 job
    if [[ '${{ needs.changed.outputs.argument_comment_lint }}' != 'true' && ... ]]; then
      echo 'No relevant changes -> CI not required.'
      exit 0
    fi
```

- 汇总所有 job 结果
- 根据变更范围智能决定失败条件
- 无关变更时自动通过

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/rust-ci.yml` | 本工作流定义 |
| `codex-rs/Cargo.toml` | Rust 工作区配置 |
| `codex-rs/Cargo.lock` | 依赖锁定 |
| `codex-rs/rust-toolchain.toml` | Rust 工具链配置 |
| `.github/scripts/install-musl-build-tools.sh` | musl 构建工具安装 |
| `tools/argument-comment-lint/` | 自定义 lint 工具 |
| `justfile` | 本地开发命令 |

## 依赖与外部交互

### 外部服务
- GitHub Actions 缓存：cargo 和 sccache 缓存
- crates.io：Rust 包下载

### 自托管运行器
```yaml
runs_on:
  group: codex-runners
  labels: codex-linux-x64
```
- 使用自托管运行器组 `codex-runners`
- 标签：`codex-linux-x64`、`codex-linux-arm64`、`codex-windows-x64`、`codex-windows-arm64`

### 密钥依赖
- 无（所有依赖都是公开的）

## 风险、边界与改进建议

### 风险
1. **自托管运行器依赖**：使用自托管运行器，需要维护基础设施
2. **缓存失效**：缓存 key 设计可能导致缓存未命中
3. **musl 复杂性**：musl 构建配置复杂，维护成本高
4. **nightly 工具链**：argument-comment-lint 依赖 nightly，可能不稳定
5. **矩阵规模**：大量矩阵组合导致 CI 时间长

### 边界条件
- Windows 禁用 sccache（兼容性问题）
- musl 构建使用隔离的 Cargo home
- 需要启用用户命名空间（Linux 测试）

### 改进建议
1. **缓存优化**：评估缓存 hit rate，优化 key 设计
2. **并行优化**：lint_build 和 tests 可以进一步并行
3. **故障隔离**：添加 retry 逻辑处理网络波动
4. **文档完善**：添加更多注释说明复杂配置
5. **本地验证**：增强 `justfile` 命令，便于本地预检查
6. **监控告警**：添加 CI 失败率监控
7. **运行器健康**：添加自托管运行器健康检查
