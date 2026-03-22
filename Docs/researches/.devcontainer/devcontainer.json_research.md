# .devcontainer/devcontainer.json 研究文档

## 场景与职责

该文件是 VS Code Dev Containers 扩展的配置文件，定义了容器化开发环境的完整配置。主要服务于：

1. **VS Code 用户**：提供一键式容器化开发环境配置
2. **开发环境标准化**：确保所有 VS Code 开发者使用一致的容器配置
3. **IDE 集成**：配置 VS Code 在容器内的扩展、设置和默认行为

与 `.devcontainer/Dockerfile` 和 `.devcontainer/README.md` 共同构成完整的容器化开发解决方案。

## 功能点目的

### 1. 容器标识
```json
"name": "Codex"
```
- 在 VS Code 界面中显示的名称
- 便于开发者在多个 Dev Container 项目中识别

### 2. 镜像构建配置
```json
"build": {
  "dockerfile": "Dockerfile",
  "context": "..",
  "platform": "linux/arm64"
}
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `dockerfile` | `"Dockerfile"` | 使用同目录下的 Dockerfile 构建镜像 |
| `context` | `".."` | 构建上下文为项目根目录（Dockerfile 的父目录）|
| `platform` | `"linux/arm64"` | 默认构建 ARM64 架构镜像 |

**context 设置的重要性**：
- 设置为 `".."` 使 Dockerfile 可以访问项目根目录的文件
- 例如：复制项目文件、使用根目录的 `justfile` 等

### 3. 运行时平台强制
```json
"runArgs": ["--platform=linux/arm64"]
```
- 强制容器以 ARM64 架构运行
- 即使宿主机是 x86，也会通过模拟运行 ARM64 容器
- 与 `build.platform` 保持一致，确保构建和运行架构相同

### 4. 容器环境变量
```json
"containerEnv": {
  "RUST_BACKTRACE": "1",
  "CARGO_TARGET_DIR": "${containerWorkspaceFolder}/codex-rs/target-arm64"
}
```

| 变量 | 值 | 用途 |
|------|-----|------|
| `RUST_BACKTRACE` | `"1"` | Rust 崩溃时显示完整堆栈跟踪，便于调试 |
| `CARGO_TARGET_DIR` | `"${containerWorkspaceFolder}/codex-rs/target-arm64"` | 隔离容器内构建输出目录 |

**变量解析**：
- `${containerWorkspaceFolder}`：VS Code 提供的变量，表示容器内工作区根目录（即 `/workspace`）
- 最终路径：`/workspace/codex-rs/target-arm64`

### 5. 远程用户设置
```json
"remoteUser": "ubuntu"
```
- 指定 VS Code 在容器内使用的用户
- 与 Dockerfile 中创建的 `ubuntu` 用户对应（UID 1000）
- 确保文件操作使用正确的用户权限

### 6. VS Code 定制配置
```json
"customizations": {
  "vscode": {
    "settings": {
      "terminal.integrated.defaultProfile.linux": "bash"
    },
    "extensions": ["rust-lang.rust-analyzer", "tamasfe.even-better-toml"]
  }
}
```

#### 编辑器设置
```json
"terminal.integrated.defaultProfile.linux": "bash"
```
- 设置 Linux 环境下的默认终端为 Bash
- 与 Ubuntu 默认 shell 保持一致

#### 自动安装扩展
```json
"extensions": ["rust-lang.rust-analyzer", "tamasfe.even-better-toml"]
```

| 扩展 ID | 用途 |
|---------|------|
| `rust-lang.rust-analyzer` | Rust 官方语言服务器，提供代码补全、跳转、重构等功能 |
| `tamasfe.even-better-toml` | TOML 文件增强支持（Cargo.toml、config.toml 等）|

- 容器首次启动时自动安装这些扩展
- 确保所有开发者拥有相同的 IDE 功能

## 具体技术实现

### 配置结构

```json
{
  // 基础配置
  "name": "...",
  "build": { ... },
  "runArgs": [ ... ],
  
  // 环境配置
  "containerEnv": { ... },
  "remoteUser": "...",
  
  // IDE 集成
  "customizations": {
    "vscode": {
      "settings": { ... },
      "extensions": [ ... ]
    }
  }
}
```

### 与 Dockerfile 的协作

```
devcontainer.json
    ├── build.dockerfile → 引用 Dockerfile
    ├── build.context → 设置构建上下文
    ├── remoteUser → 与 Dockerfile 的 USER 指令对应
    └── containerEnv → 补充 Dockerfile 的 ENV
```

### 变量替换机制

VS Code Dev Containers 支持多种预定义变量：

| 变量 | 示例值 | 说明 |
|------|--------|------|
| `${containerWorkspaceFolder}` | `/workspace` | 容器内工作区绝对路径 |
| `${localWorkspaceFolder}` | `/Users/xxx/codex` | 宿主机工作区绝对路径 |
| `${env:NAME}` | - | 引用宿主机环境变量 |

## 关键代码路径与文件引用

### 直接依赖的文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `Dockerfile` | 构建依赖 | `build.dockerfile` 字段引用 |
| `../justfile` | 上下文依赖 | 构建上下文包含项目根目录的 justfile |
| `../codex-rs/` | 上下文依赖 | Rust 项目代码在构建上下文中 |

### 与项目其他文件的交互

1. **与 `codex-rs/Cargo.toml` 的交互**：
   - `CARGO_TARGET_DIR` 指向 `codex-rs/target-arm64`
   - 与 Cargo 工作区配置配合，隔离构建输出

2. **与 `.vscode/` 目录的交互**：
   - 项目根目录的 `.vscode/` 包含共享的 VS Code 设置
   - Dev Container 内的设置会合并或覆盖这些配置

3. **与 `AGENTS.md` 的交互**：
   - 安装的 `rust-analyzer` 扩展支持 AGENTS.md 中定义的代码规范
   - 如 format! 内联变量、clippy 规则等

### 配置继承链

```
VS Code 默认设置
    ↓
项目 .vscode/settings.json
    ↓
devcontainer.json → customizations.vscode.settings
    ↓
用户 VS Code 设置（部分）
```

## 依赖与外部交互

### 外部依赖

1. **VS Code**：编辑器主体，需要安装 Dev Containers 扩展
2. **Docker Desktop**：提供容器运行时（macOS/Windows）
3. **Docker Engine**：Linux 系统上的容器运行时

### 与 Docker 的交互

```
VS Code Dev Containers 扩展
    ├── 读取 devcontainer.json
    ├── docker build（使用配置中的 build 参数）
    ├── docker run（使用 runArgs 和其他参数）
    └── 建立 VS Code Server 与容器的连接
```

### 与 Rust 工具链的交互

1. **rust-analyzer**：
   - 通过 VS Code 扩展自动安装
   - 需要容器内有可用的 Rust 工具链（由 Dockerfile 提供）
   - 通过 `CARGO_TARGET_DIR` 正确索引编译产物

2. **Cargo**：
   - 使用 `CARGO_TARGET_DIR` 隔离构建输出
   - `RUST_BACKTRACE=1` 确保调试信息完整

### 与 Git 的交互

- 容器内 Git 配置继承自宿主机（VS Code 自动处理）
- 文件权限通过 `remoteUser: ubuntu` 保持一致

## 风险、边界与改进建议

### 当前风险

1. **平台硬编码为 ARM64**：
   - `platform: "linux/arm64"` 和 `runArgs: ["--platform=linux/arm64"]`
   - x64 用户需要手动修改配置
   - 与 README.md 中提到的多架构支持不完全一致

2. **扩展列表可能过时**：
   - 当前仅安装两个扩展
   - 项目可能还有其他推荐的 VS Code 扩展未包含

3. **缺少生命周期钩子**：
   - 没有配置 `postCreateCommand` 或 `postStartCommand`
   - 无法自动执行项目初始化（如 `cargo fetch`）

4. **端口转发未配置**：
   - 如果 Codex 需要运行本地服务器，需要配置 `forwardPorts`
   - 当前配置可能导致端口无法从宿主机访问

### 边界情况

1. **Windows 宿主机**：
   - 需要使用 WSL2 后端
   - 路径格式和权限处理可能与 macOS/Linux 不同

2. **企业代理环境**：
   - 可能需要额外的 `containerEnv` 配置代理变量
   - 文档未说明如何处理

3. **多工作区项目**：
   - 当前配置假设单工作区结构
   - 复杂的 monorepo 结构可能需要调整

4. **Apple Silicon Mac 上的 x64 模拟**：
   - 强制 ARM64 避免性能损耗
   - 但某些情况下可能需要 x64 容器（如测试 x64 特定问题）

### 改进建议

1. **添加平台选择注释**：
```json
{
  // 平台选项：
  // - "linux/arm64": Apple Silicon Mac (推荐)
  // - "linux/amd64": Intel Mac 或需要 x64 模拟
  "platform": "linux/arm64",
  "runArgs": ["--platform=linux/arm64"]
}
```

2. **添加生命周期钩子**：
```json
{
  "postCreateCommand": "cd /workspace/codex-rs && cargo fetch",
  "postStartCommand": "rustup show active-toolchain"
}
```

3. **扩展推荐列表**：
```json
{
  "extensions": [
    "rust-lang.rust-analyzer",
    "tamasfe.even-better-toml",
    "serayuzgur.crates",           // Cargo.toml 依赖管理
    "vadimcn.vscode-lldb",         // 调试支持
    "mutantdino.resourcemonitor"   // 容器资源监控
  ]
}
```

4. **添加端口转发配置**（如需要）：
```json
{
  "forwardPorts": [3000, 8080],
  "portsAttributes": {
    "3000": {
      "label": "Codex Web UI",
      "onAutoForward": "notify"
    }
  }
}
```

5. **添加挂载配置优化**：
```json
{
  "mounts": [
    // 持久化 Cargo 缓存，加速后续启动
    "source=codex-cargo-cache,target=/home/ubuntu/.cargo/registry,type=volume",
    // 可选：挂载 SSH 密钥用于 Git 操作
    "source=${localEnv:HOME}/.ssh,target=/home/ubuntu/.ssh,type=bind,consistency=cached"
  ]
}
```

6. **添加功能特性（Features）**：
```json
{
  "features": {
    // 可选：添加 GitHub CLI
    "ghcr.io/devcontainers/features/github-cli:1": {}
  }
}
```

7. **创建多架构变体**：
   - 创建 `devcontainer.json`（ARM64，默认）
   - 创建 `devcontainer-amd64.json`（x64 变体）
   - 在 README.md 中说明如何选择

```json
// devcontainer-amd64.json
{
  "name": "Codex (x64)",
  "build": {
    "dockerfile": "Dockerfile",
    "context": "..",
    "platform": "linux/amd64"
  },
  "runArgs": ["--platform=linux/amd64"],
  "containerEnv": {
    "RUST_BACKTRACE": "1",
    "CARGO_TARGET_DIR": "${containerWorkspaceFolder}/codex-rs/target-amd64"
  },
  // ... 其他配置相同
}
```

8. **添加健康检查配置**：
```json
{
  "overrideCommand": false,
  "customizations": {
    "vscode": {
      "settings": {
        "dev.containers.defaultExtensionsIfInstalledLocally": [
          "ms-vscode-remote.remote-containers"
        ]
      }
    }
  }
}
```
