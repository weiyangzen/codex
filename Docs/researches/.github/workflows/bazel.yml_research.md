# bazel.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流负责在多个平台（macOS、Linux）上执行 Bazel 构建和测试。作为实验性工作流，它提供了除 Cargo 之外的另一种构建方式，利用 Bazel 的远程缓存和执行能力加速构建过程。

## 功能点目的

1. **多平台构建验证**：在 macOS (x86_64/arm64) 和 Linux (x86_64/arm64, glibc/musl) 上验证构建
2. **远程构建支持**：集成 BuildBuddy 提供远程缓存和执行能力
3. **并发控制**：通过 concurrency 配置避免重复运行，节省 CI 资源
4. **测试失败诊断**：自动收集并展示失败测试的日志

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
- PR 触发：所有 Pull Request
- Push 触发：main 分支的推送
- 手动触发：支持 workflow_dispatch 手动执行

### 并发控制策略
```yaml
concurrency:
  group: concurrency-group::${{ github.workflow }}::${{ github.event.pull_request.number > 0 && format('pr-{0}', github.event.pull_request.number) || github.ref_name }}${{ github.ref_name == 'main' && format('::{0}', github.run_id) || ''}}
  cancel-in-progress: ${{ github.ref_name != 'main' }}
```
- 按 PR 编号或分支名分组
- main 分支追加 run_id 确保不取消 main 分支的构建
- 非 main 分支取消进行中的旧构建

### 构建矩阵配置
```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      # macOS
      - os: macos-15-xlarge
        target: aarch64-apple-darwin
      - os: macos-15-xlarge
        target: x86_64-apple-darwin
      # Linux
      - os: ubuntu-24.04
        target: x86_64-unknown-linux-gnu
      - os: ubuntu-24.04
        target: x86_64-unknown-linux-musl
```
- 支持 4 个主要目标平台（ARM64 macOS、x86_64 macOS、x86_64 Linux glibc/musl）
- ARM Linux 构建已注释掉（2026-02-27 标记为不稳定）
- Windows 支持待实现

### DotSlash 安装与配置
```yaml
- name: Install DotSlash
  uses: facebook/install-dotslash@v2
- name: Make DotSlash available in PATH (Unix)
  if: runner.os != 'Windows'
  run: cp "$(which dotslash)" /usr/local/bin
```
- 某些集成测试依赖 DotSlash 安装（参见 PR #7617）
- Unix 系统复制到 `/usr/local/bin` 确保在 Bazel 沙箱中可用

### MODULE.bazel.lock 校验
```yaml
- name: Check MODULE.bazel.lock is up to date
  if: matrix.os == 'ubuntu-24.04' && matrix.target == 'x86_64-unknown-linux-gnu'
  run: ./scripts/check-module-bazel-lock.sh
```
- 仅在 Linux x86_64 上执行锁文件校验
- 调用脚本检查 `bazel mod deps --lockfile_mode=error`

### Bazel 测试执行与日志收集
```yaml
print_failed_bazel_test_logs() {
  local console_log="$1"
  local testlogs_dir
  testlogs_dir="$(bazel $BAZEL_STARTUP_ARGS info bazel-testlogs 2>/dev/null || echo bazel-testlogs)"
  
  local failed_targets=()
  while IFS= read -r target; do
    failed_targets+=("$target")
  done < <(
    grep -E '^FAIL: //' "$console_log" \
      | sed -E 's#^FAIL: (//[^ ]+).*#\1#' \
      | sort -u
  )
  
  for target in "${failed_targets[@]}"; do
    local rel_path="${target#//}"
    rel_path="${rel_path/:/\/}"
    local test_log="${testlogs_dir}/${rel_path}/test.log"
    echo "::group::Bazel test log tail for ${target}"
    tail -n 200 "$test_log"
    echo "::endgroup::"
  done
}
```
- 解析 Bazel 控制台输出提取失败目标
- 从 `bazel-testlogs` 目录读取对应测试日志
- 使用 GitHub Actions 的 `::group::` 折叠输出

### BuildBuddy 远程执行配置
```yaml
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
  bazel $BAZEL_STARTUP_ARGS \
    --noexperimental_remote_repo_contents_cache \
    --bazelrc=.github/workflows/ci.bazelrc \
    "${bazel_args[@]}" \
    "--remote_header=x-buildbuddy-api-key=$BUILDBUDDY_API_KEY"
else
  # Fork/社区 PR：禁用远程服务
  bazel $BAZEL_STARTUP_ARGS \
    --noexperimental_remote_repo_contents_cache \
    "${bazel_args[@]}" \
    --remote_cache= \
    --remote_executor=
fi
```
- 有 API Key 时使用 BuildBuddy 远程缓存和执行
- 无 API Key 时（Fork PR）清空远程端点，仅本地执行
- 禁用 `experimental_remote_repo_contents_cache` 避免 Bazel 9 的 overlay materialization 问题

### Windows 特殊处理
```yaml
- name: Configure Bazel startup args (Windows)
  if: runner.os == 'Windows'
  run: |
    "BAZEL_STARTUP_ARGS=--output_user_root=C:\\" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
```
- 使用短路径 `C:\\` 避免 Windows 路径长度限制问题

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/ci.bazelrc` | CI 专用 Bazel 配置 |
| `.github/workflows/Dockerfile.bazel` | Bazel 构建环境镜像定义 |
| `scripts/check-module-bazel-lock.sh` | 锁文件校验脚本 |
| `MODULE.bazel` | Bazel 模块定义 |
| `MODULE.bazel.lock` | Bazel 依赖锁文件 |
| `.bazelrc` | 根目录 Bazel 配置 |

## 依赖与外部交互

### 外部服务
1. **BuildBuddy** (remote.buildbuddy.io)：远程缓存和执行
2. **GitHub Actions 运行器**：
   - macos-15-xlarge (Apple Silicon)
   - ubuntu-24.04 / ubuntu-24.04-arm
   - windows-latest (待启用)

### 依赖的工具
- Bazelisk (通过 `bazelbuild/setup-bazelisk@v3`)
- DotSlash (通过 `facebook/install-dotslash@v2`)
- Node.js (通过 `actions/setup-node@v6`)

### 密钥依赖
- `secrets.BUILDBUDDY_API_KEY`：BuildBuddy 远程执行 API 密钥

## 风险、边界与改进建议

### 风险
1. **ARM Linux 构建不稳定**：已注释掉 ARM Linux 目标，需要后续修复
2. **缓存未启用**：注释中提到缓存命中率低且上传成本高，当前禁用
3. **Windows 支持缺失**：Windows 工具链问题待解决
4. **Fork PR 构建时间长**：无 BuildBuddy API Key 时完全本地执行，构建时间显著增加

### 边界条件
- 需要 `BUILDBUDDY_API_KEY` 才能使用远程执行
- macOS 沙箱可能优先使用旧版 Homebrew Node.js
- Windows 路径长度限制需要特殊处理

### 改进建议
1. **启用缓存**：调查并修复缓存命中率问题，减少构建时间
2. **ARM Linux 支持**：诊断并修复 ARM Linux 构建不稳定问题
3. **Windows 支持**：完成 Windows 工具链配置
4. **并行优化**：利用 `--jobs` 参数提高并行度
5. **缓存分层**：区分依赖缓存和构建产物缓存，优化缓存策略
