# shell-tool-mcp/README.md 研究文档

## 场景与职责

`README.md` 是 `@openai/codex-shell-tool-mcp` 包的官方文档，面向：

1. **终端用户**：使用 Codex CLI 的开发者
2. **运维人员**：配置 MCP 服务器的系统管理员
3. **安全审计人员**：评估沙箱安全性的安全工程师

核心职责：
- 解释 MCP 服务器的用途和工作原理
- 提供安装和配置指南
- 说明安全模型（沙箱、权限提升、规则系统）
- 描述与 Codex CLI 的集成方式

## 功能点目的

### 1. 项目概述

**核心价值主张**：
- 提供一个 MCP 服务器，暴露 `shell` 工具
- 在**沙箱化的 Bash 实例**中运行命令
- 通过拦截 `execve(2)` 系统调用实现精确控制

**关键差异化特性**：
- 传统方式：依赖 `$PATH` 解析，可能被别名/函数劫持
- 本方案：直接拦截 `execve(2)`，始终知道完整程序路径

### 2. 安全模型

#### 三层决策机制

| 决策类型 | 行为 | 使用场景 |
|----------|------|----------|
| `allow` | 权限提升，在沙箱外运行 | 信任的命令（如 `ls`, `cat`） |
| `prompt` | MCP 征求人类批准 | 敏感操作（如 `rm`, `git push`） |
| `forbidden` | 拒绝执行，返回 exit code 1 | 危险命令（如 `rm -rf /`） |

#### 规则配置（.rules 文件）

```toml
# 示例 .rules 配置
[[rules]]
pattern = "^git push"
decision = "prompt"
message = "即将推送代码到远程仓库"
```

### 3. 使用方式

#### 临时使用（命令行）

```bash
codex --disable shell_tool \
  --config 'mcp_servers.bash={command = "npx", args = ["-y", "@openai/codex-shell-tool-mcp"]}'
```

关键点：
- `--disable shell_tool`：禁用默认 shell 工具，避免冲突
- `--config`：动态注入 MCP 服务器配置

#### 永久配置（~/.codex/config.toml）

```toml
[features]
shell_tool = false

[mcp_servers.shell-tool]
command = "npx"
args = ["-y", "@openai/codex-shell-tool-mcp"]
```

### 4. MCP 客户端要求

**能力声明**（Capability）：
```json
{
  "capabilities": {
    "experimental": {
      "codex/sandbox-state": {
        "version": "1.0.0"
      }
    }
  }
}
```

**沙箱状态更新协议**：
```json
{
  "id": "req-42",
  "method": "codex/sandbox-state/update",
  "params": {
    "sandboxPolicy": {
      "type": "workspace-write",
      "writable_roots": ["/home/user/code/codex"],
      "network_access": false,
      "exclude_tmpdir_env_var": false,
      "exclude_slash_tmp": false
    }
  }
}
```

### 5. 包内容说明

当前发布内容：
- 多平台补丁版 Bash 二进制文件
- 多平台补丁版 Zsh 二进制文件
- 支持 glibc 基线：Ubuntu 24.04/22.04/20.04, Debian 12/11, CentOS-like 9
- 支持 macOS 版本：15/14/13

**注意**：不包含 Rust MCP 服务器二进制文件（由 codex-cli 或其他组件提供）

## 具体技术实现

### Bash 选择逻辑

```
启动流程：
1. MCP 服务器启动
2. 检测平台（Linux/macOS）和架构（x64/arm64）
3. 读取 /etc/os-release（Linux）或 Darwin 版本（macOS）
4. 调用 bashSelection.ts 选择最合适的 Bash 变体
5. 设置 EXEC_WRAPPER 环境变量
6. 启动补丁版 Bash
```

### execve 拦截机制

```
命令执行流程：
1. 用户在 Bash 中输入命令（如 `ls -la`）
2. Bash 准备调用 execve("/bin/ls", ["ls", "-la"], envp)
3. 补丁版 Bash 检测到 EXEC_WRAPPER 设置
4. 调用 execve_wrapper 而非直接执行
5. execve_wrapper 通过 socket 与 MCP 服务器通信
6. MCP 服务器根据 .rules 决定：Run / Escalate / Deny
7. 执行决策并返回结果
```

### 相关 Rust 组件

位于 `codex-rs/shell-escalation/`：
- `execve_wrapper.rs`：包装器实现
- `escalate_protocol.rs`：通信协议
- `escalate_server.rs`：服务器端处理
- `escalation_policy.rs`：权限策略

## 关键代码路径与文件引用

| 组件 | 路径 | 职责 |
|------|------|------|
| Bash 选择 | `src/bashSelection.ts` | 根据 OS 选择合适 Bash 变体 |
| 平台检测 | `src/platform.ts` | 解析 target triple |
| OS 信息 | `src/osRelease.ts` | 读取 /etc/os-release |
| 类型定义 | `src/types.ts` | TypeScript 类型 |
| 常量定义 | `src/constants.ts` | 支持的 OS 变体列表 |
| 入口点 | `src/index.ts` | CLI 入口，输出 Bash 路径 |
| execve 包装器 | `codex-rs/shell-escalation/src/unix/execve_wrapper.rs` | Rust 侧包装器 |
| 升级协议 | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs` | 通信协议定义 |
| Bash 补丁 | `patches/bash-exec-wrapper.patch` | Bash 源码补丁 |

## 依赖与外部交互

### 运行时依赖

| 依赖 | 用途 | 版本要求 |
|------|------|----------|
| Node.js | 运行 MCP 服务器 | >= 18 |
| npx | 包执行器 | 随 npm 提供 |
| 补丁版 Bash | 沙箱化 shell | 捆绑在 vendor/ |
| 补丁版 Zsh | 替代 shell | 捆绑在 vendor/ |

### 外部系统集成

1. **Codex CLI**：
   - 作为 MCP 客户端连接到此服务器
   - 发送 `codex/sandbox-state/update` 请求
   - 处理 MCP elicitation（人工确认）

2. **操作系统**：
   - Linux：读取 `/etc/os-release`
   - macOS：读取 `uname -r` 的 Darwin 版本
   - 两者：通过 Unix socket 通信

3. **MCP 协议**：
   - 遵循 Model Context Protocol 规范
   - 支持 experimental 能力声明
   - 支持 elicitation（征求用户输入）

## 风险、边界与改进建议

### 当前风险

1. **版本匹配要求**：
   - README 强调 "CLI version matches the MCP server version"
   - 版本不匹配可能导致协议不兼容
   - 需要手动确保版本同步

2. **实验性状态**：
   - 明确标记为 "still experimental"
   - API 可能变化，生产环境使用需谨慎

3. **平台支持限制**：
   - 仅支持 Linux 和 macOS
   - Windows 不支持（无 execve 概念）
   - 特定发行版/版本组合才受支持

4. **沙箱边界**：
   - Bash 本身在沙箱中，但 `allow` 决策会提升权限
   - 如果 .rules 配置过于宽松，安全性降低

### 边界情况

1. **OS 检测失败**：
   - 如果 `/etc/os-release` 不存在或格式异常
   - 回退到第一个支持的变体（ubuntu-24.04）

2. **架构不匹配**：
   - 如果运行在未预编译的架构上
   - 会抛出 "Unsupported platform" 错误

3. **Socket 通信失败**：
   - 如果 `CODEX_ESCALATE_SOCKET` 未设置或无效
   - execve_wrapper 无法与 MCP 通信

### 改进建议

1. **文档改进**：
   - 添加 .rules 文件的完整语法文档
   - 提供常见用例的配置示例
   - 说明如何调试沙箱问题

2. **版本管理**：
   - 实现版本协商机制，避免硬性匹配要求
   - 添加版本不匹配的警告日志

3. **错误处理**：
   - 提供更详细的错误信息（如哪个规则匹配）
   - 添加诊断模式（verbose logging）

4. **扩展支持**：
   - 考虑支持更多 Linux 发行版
   - 考虑 Windows 的替代方案（WSL2？）

5. **安全增强**：
   - 默认拒绝（deny-by-default）模式选项
   - 规则审计日志
   - 命令执行历史记录

6. **测试覆盖**：
   - 当前测试仅覆盖 Bash 选择逻辑
   - 建议添加集成测试（模拟完整执行流程）
