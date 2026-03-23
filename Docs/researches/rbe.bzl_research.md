# rbe.bzl 研究文档

## 场景与职责

`rbe.bzl` 是 Bazel 的 Starlark 扩展文件，定义了 **Remote Build Execution (RBE)** 平台配置规则。该文件实现了 `rbe_platform_repository` 仓库规则，用于在 Bazel 构建系统中配置远程执行环境。

在 Codex 项目中，此文件服务于以下场景：
- **远程构建执行**：将构建任务分发到远程执行器，加速大型编译
- **跨平台构建标准化**：通过容器镜像确保构建环境的一致性
- **CI/CD 集成**：支持 BuildBuddy 等远程执行服务
- **多架构支持**：自动检测主机架构并配置对应的远程平台

## 功能点目的

### 1. 架构检测与平台配置

```python
def _rbe_platform_repo_impl(rctx):
    arch = rctx.os.arch
    if arch in ["x86_64", "amd64"]:
        cpu = "x86_64"
        exec_arch = "amd64"
        image_sha = "0a8e56bfaa3b2e5279db0d3bb2d62b44ba5e5d63a37d97eb8790f49da570af70"
    elif arch in ["aarch64", "arm64"]:
        cpu = "aarch64"
        exec_arch = "arm64"
        image_sha = "136487cc4b7cf6f1021816ca18ed00896daed98404ea91dc4d6dd9e9d1cf9564"
    else:
        fail("Unsupported host arch for rbe platform: {}".format(arch))
```

**目的**：
- 自动检测主机架构（x86_64/amd64 或 aarch64/arm64）
- 为不同架构配置对应的 Docker 镜像 SHA256 校验值
- 确保远程执行环境与本地开发环境架构匹配

### 2. Bazel 平台定义生成

```python
rctx.file("BUILD.bazel", """\
platform(
    name = "rbe_platform",
    constraint_values = [
        "@platforms//cpu:{cpu}",
        "@platforms//os:linux",
        "@bazel_tools//tools/cpp:clang",
        "@llvm//constraints/libc:gnu.2.28",
    ],
    exec_properties = {{
        "container-image": "docker://docker.io/mbolin491/codex-bazel@sha256:{image_sha}",
        "Arch": "{arch}",
        "OSFamily": "Linux",
    }},
    visibility = ["//visibility:public"],
)
""")
```

**目的**：
- 生成标准的 Bazel `platform` 目标，供工具链选择
- 定义执行约束（CPU、OS、编译器、libc 版本）
- 配置容器镜像地址，确保远程执行环境包含必要工具（git、python3、dotslash 等）

### 3. 仓库规则暴露

```python
rbe_platform_repository = repository_rule(
    implementation = _rbe_platform_repo_impl,
    doc = "Sets up a platform for remote builds with an Arch exec_property matching the host.",
)
```

**目的**：
- 将实现封装为可复用的 Bazel 仓库规则
- 允许在 `MODULE.bazel` 中通过 `use_repo_rule` 调用
- 提供文档说明，便于开发者理解用途

## 具体技术实现

### 关键数据结构

| 变量 | 类型 | 说明 |
|------|------|------|
| `arch` | `string` | 主机架构标识（来自 `rctx.os.arch`） |
| `cpu` | `string` | Bazel 平台 CPU 约束值（x86_64 或 aarch64） |
| `exec_arch` | `string` | 执行属性中的架构标识（amd64 或 arm64） |
| `image_sha` | `string` | Docker 镜像 SHA256 校验值 |

### 架构映射表

| 主机架构 | CPU 约束 | 执行架构 | 镜像 SHA256 |
|----------|----------|----------|-------------|
| x86_64 / amd64 | x86_64 | amd64 | 0a8e56bfaa3b2e5279db0d3bb2d62b44ba5e5d63a37d97eb8790f49da570af70 |
| aarch64 / arm64 | aarch64 | arm64 | 136487cc4b7cf6f1021816ca18ed00896daed98404ea91dc4d6dd9e9d1cf9564 |

### 平台约束详解

```python
constraint_values = [
    "@platforms//cpu:{cpu}",          # CPU 架构约束
    "@platforms//os:linux",            # 操作系统约束
    "@bazel_tools//tools/cpp:clang",   # C++ 编译器约束
    "@llvm//constraints/libc:gnu.2.28", # libc 版本约束
]
```

**约束作用**：
- 确保只有匹配这些约束的操作才能在远程平台执行
- 与本地工具链约束区分，实现选择性远程执行

### 执行属性详解

```python
exec_properties = {
    "container-image": "docker://docker.io/mbolin491/codex-bazel@sha256:{image_sha}",
    "Arch": "{arch}",
    "OSFamily": "Linux",
}
```

| 属性 | 说明 |
|------|------|
| `container-image` | 远程执行器拉取的容器镜像，使用 SHA256 确保不可变性 |
| `Arch` | 架构标识，供远程执行器调度参考 |
| `OSFamily` | 操作系统家族，用于平台匹配 |

## 关键代码路径与文件引用

### 调用方（使用者）

| 文件 | 代码 | 说明 |
|------|------|------|
| `/home/sansha/Github/codex/MODULE.bazel` | `rbe_platform_repository = use_repo_rule("//:rbe.bzl", "rbe_platform_repository")` | 导入仓库规则 |
| `/home/sansha/Github/codex/MODULE.bazel` | `rbe_platform_repository(name = "rbe_platform")` | 实例化远程平台仓库 |
| `/home/sansha/Github/codex/BUILD.bazel` | `alias(name = "rbe", actual = "@rbe_platform")` | 创建便捷别名 |
| `/home/sansha/Github/codex/.bazelrc` | `common:remote --extra_execution_platforms=//:rbe` | 配置远程执行平台 |

### 依赖的外部规则

| 规则/仓库 | 来源 | 用途 |
|-----------|------|------|
| `@platforms` | Bazel 官方 | 标准平台约束定义 |
| `@bazel_tools` | Bazel 内置 | 内置工具链约束 |
| `@llvm` | `MODULE.bazel` | LLVM 工具链和 libc 约束 |

### 相关配置文件

| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/.bazelrc` | 包含远程执行配置（`common:remote` 配置节） |
| `/home/sansha/Github/codex/MODULE.bazel` | 定义外部依赖和仓库规则实例化 |
| `/home/sansha/Github/codex/BUILD.bazel` | 创建 `rbe` 别名和本地平台定义 |

## 依赖与外部交互

### 外部依赖

```
rbe.bzl
├── @platforms//cpu:*          (CPU 架构约束)
├── @platforms//os:linux       (操作系统约束)
├── @bazel_tools//tools/cpp:clang  (编译器约束)
├── @llvm//constraints/libc:gnu.2.28  (libc 版本约束)
└── docker.io/mbolin491/codex-bazel  (容器镜像)
```

### 容器镜像详情

- **镜像仓库**: `docker.io/mbolin491/codex-bazel`
- **标签**: `latest`（通过 SHA256 固定）
- **基础**: Ubuntu-based
- **预装工具**: git, python3, dotslash, 及其他集成测试所需工具
- **验证地址**: https://hub.docker.com/layers/mbolin491/codex-bazel/latest/images/sha256:{sha}

### 远程执行服务

根据 `.bazelrc` 配置：

```
common:remote --remote_executor=grpcs://remote.buildbuddy.io
common:remote --jobs=800
```

- **服务**: BuildBuddy (remote.buildbuddy.io)
- **协议**: gRPC with TLS (grpcs://)
- **并发度**: 800 个并行作业

### 执行流程

```
本地 Bazel 构建
    ↓
检查目标平台约束
    ↓
匹配 //:rbe (别名) → @rbe_platform//:rbe_platform
    ↓
读取 exec_properties
    ↓
向 BuildBuddy 发送执行请求
    ↓
BuildBuddy 拉取容器镜像
    ↓
在容器中执行构建动作
    ↓
返回结果和缓存产物
```

## 风险、边界与改进建议

### 风险点

1. **容器镜像可用性**
   - 镜像托管在 Docker Hub 个人仓库 (`mbolin491`)
   - 若仓库被删除或镜像被覆盖，远程构建将失败
   - **缓解**: 使用 SHA256 校验确保镜像不可变

2. **架构支持限制**
   - 仅支持 x86_64 和 aarch64，不支持 riscv64 等其他架构
   - 新架构支持需修改源码并发布新镜像

3. **网络依赖**
   - 远程执行依赖 BuildBuddy 服务的可用性
   - 网络分区或服务商故障将导致构建失败

4. **镜像维护**
   - 镜像中的工具版本（git、python3 等）可能过时
   - 安全漏洞修复需要重新构建和发布镜像

### 边界情况

1. **架构检测歧义**
   ```python
   # 代码中同时处理 x86_64/amd64 和 aarch64/arm64
   # 但不同操作系统可能报告不同的架构名称
   if arch in ["x86_64", "amd64"]:  # 覆盖常见变体
   ```

2. **本地回退**
   - 远程执行失败时，Bazel 可配置回退到本地执行
   - 但 `.bazelrc` 中 `common:remote` 配置可能强制远程执行

3. **缓存一致性**
   - 远程执行结果缓存于 BuildBuddy
   - 本地磁盘缓存（`~/.cache/bazel-disk-cache`）与远程缓存需保持一致

### 改进建议

1. **镜像托管迁移**
   ```python
   # 建议迁移到组织级仓库
   "container-image": "docker://ghcr.io/openai/codex-bazel@sha256:{image_sha}",
   ```

2. **多镜像版本支持**
   ```python
   # 支持通过属性指定镜像版本
   def _rbe_platform_repo_impl(rctx):
       image_version = rctx.attr.image_version  # 允许自定义
   ```

3. **健康检查与降级**
   ```python
   # 在仓库规则中添加镜像可用性检查
   # 失败时提供清晰的错误信息和降级建议
   ```

4. **自动化镜像更新**
   - 建立 CI 流程自动构建和发布 RBE 镜像
   - 使用 Renovate 或 Dependabot 监控基础镜像更新

5. **文档完善**
   ```python
   rbe_platform_repository = repository_rule(
       implementation = _rbe_platform_repo_impl,
       doc = """
       Sets up a platform for remote builds with an Arch exec_property matching the host.
       
       Args:
           name: Unique name for the repository.
           # 建议添加可配置参数
           image_sha: Optional override for container image SHA256.
       """,
       # attrs = {...}  # 暴露可配置属性
   )
   ```

6. **安全加固**
   - 评估使用私有镜像仓库并配置认证
   - 定期扫描容器镜像的安全漏洞
   - 考虑启用镜像签名验证
