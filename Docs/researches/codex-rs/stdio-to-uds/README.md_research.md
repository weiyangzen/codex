# README.md 研究文档

## 场景与职责

`README.md` 是 `codex-stdio-to-uds` crate 的用户文档，面向开发者和终端用户解释该工具的存在意义、使用方法和底层原理。该文档位于 crate 根目录，是用户了解该组件的第一入口。

## 功能点目的

1. **问题陈述**：解释为什么需要这个工具（MCP 传输机制的第三种选择）
2. **价值主张**：阐述 UDS 相比 stdio 和 HTTP 的独特优势
3. **使用示例**：展示如何在 Codex CLI 中配置使用
4. **技术背景**：说明 Windows 支持的特殊处理方式

## 具体技术实现

### 文档结构分析

```markdown
1. 标题 - 包名
2. 背景 - MCP 传统传输机制（stdio/HTTP）
3. 价值 - UDS 的两大优势
4. 用法 - Codex CLI 配置示例
5. 技术限制 - Windows UDS 支持现状
```

### 核心概念解释

#### MCP 传输机制演进

| 机制 | 特点 | 适用场景 |
|------|------|----------|
| stdio | 简单、进程绑定 | 短期运行的命令行工具 |
| HTTP | 网络可达、状态less | 分布式部署 |
| **UDS** | **本地、权限可控、可附加到长运行进程** | **本地守护进程/服务** |

#### UDS 优势详解

1. **长运行进程附加**：
   - UDS 由文件系统路径标识，独立于进程生命周期
   - HTTP 服务器可以监听 UDS 而非 TCP 端口
   - 客户端（Codex）可随时连接/断开，不影响服务器

2. **权限控制**：
   - UDS 文件受标准 Unix 文件权限控制
   - 可通过 `chmod`/`chown` 限制访问用户/组
   - 比 TCP（任何可连接主机）更安全的本地通信

### 使用示例解析

```bash
codex --config mcp_servers.example={command="codex-stdio-to-uds",args=["/tmp/mcp.sock"]}
```

这行配置：
- 定义了一个名为 `example` 的 MCP 服务器
- 使用 `codex-stdio-to-uds` 作为包装器
- 将 stdio 流桥接到 `/tmp/mcp.sock` 的 UDS

数据流向：
```
Codex CLI --stdio--> codex-stdio-to-uds --UDS--> 实际 MCP 服务器
```

### Windows 兼容性说明

文档指出一个已知限制：
- Rust 标准库尚未在 Windows 上支持 UDS
- Windows 10 版本 1809（2018年10月）已添加 AF_UNIX 支持
- 上游跟踪 issue: [rust#56533](https://github.com/rust-lang/rust/issues/56533)

**解决方案**：使用 `uds_windows` crate 作为跨平台兼容层

## 关键代码路径与文件引用

| 引用 | 说明 |
|------|------|
| `https://github.com/rust-lang/rust/issues/56533` | Rust 标准库 Windows UDS 支持跟踪 issue |
| `https://crates.io/crates/uds_windows` | Windows UDS polyfill crate |

### 相关实现文件

| 文件 | 内容 |
|------|------|
| `src/lib.rs` | 包含 `run()` 函数，实现实际的 stdio↔UDS 桥接 |
| `src/main.rs` | 命令行参数解析和错误处理 |
| `Cargo.toml` | 定义 `uds_windows` 为 Windows 条件依赖 |

## 依赖与外部交互

### 外部系统

- **Codex CLI**：主要用户，通过 `--config` 参数配置使用该工具
- **MCP 服务器**：目标服务，监听 UDS 并提供功能

### 生态位

```
┌─────────────────┐
│   Codex CLI     │
│  (MCP Client)   │
└────────┬────────┘
         │ stdio
         ▼
┌─────────────────┐
│ codex-stdio-to- │  <-- 本文档描述的工具
│     uds         │
└────────┬────────┘
         │ UDS
         ▼
┌─────────────────┐
│  MCP Server     │
│ (over UDS)      │
└─────────────────┘
```

## 风险、边界与改进建议

### 风险

1. **Windows 支持依赖第三方**：`uds_windows` 的维护状态直接影响 Windows 用户体验
2. **文档示例可能过时**：Codex CLI 的配置语法可能演进，示例需要同步更新

### 边界

- **非独立工具**：该工具设计为 Codex CLI 的配套组件，单独使用价值有限
- **单 socket 限制**：每次调用只能桥接一个 socket，多服务器需要多实例
- **无重连逻辑**：socket 断开后进程退出，无自动重连机制

### 改进建议

1. **补充完整配置示例**：
   ```bash
   # 当前示例较简略，可扩展为：
   codex --config 'mcp_servers.myserver={
       command="codex-stdio-to-uds",
       args=["/var/run/myserver.sock"]
   }'
   ```

2. **添加故障排查章节**：
   - socket 文件权限问题
   - Windows 特定注意事项
   - 如何验证连接成功

3. **性能特征说明**：
   - 是否适合高吞吐场景
   - 内存占用情况
   - 与直接 stdio 的性能差异

4. **架构图**：添加 ASCII 架构图展示数据流向

5. **更新跟踪**：当 rust#56533 解决后，可移除 `uds_windows` 依赖，文档应同步更新
