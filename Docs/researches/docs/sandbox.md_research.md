# sandbox.md 研究文档

## 场景与职责

sandbox.md 是 Codex CLI 项目中关于沙盒（Sandbox）和批准（Approvals）功能的文档入口。该文档非常简洁，仅作为指向官方详细安全文档的链接入口。

**适用场景：**
- 用户需要了解 Codex 的安全沙盒机制
- 开发者配置沙盒规则
- 系统管理员评估安全风险

## 功能点目的

### 1. 沙盒和批准入口
- **目的**：提供沙盒和安全批准文档的快速入口
- **方式**：链接到 OpenAI 开发者门户的详细安全文档

### 2. 安全指引
- 引导用户到官方文档获取沙盒和批准的完整信息
- 涵盖安全模型、批准流程、沙盒技术

## 具体技术实现

### 文档结构

```markdown
## Sandbox & approvals

For information about Codex sandboxing and approvals, see [this documentation](https://developers.openai.com/codex/security).
```

### 链接目标

- **URL**: https://developers.openai.com/codex/security
- **内容**：详细的沙盒和安全文档

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/sandbox.md` | 本文档 |
| `/home/sansha/Github/codex/docs/execpolicy.md` | 执行策略文档 |
| `/home/sansha/Github/codex/codex-rs/core/src/` | 核心代码目录 |

### 相关代码文件（推测）

基于项目结构和 AGENTS.md 的内容，沙盒相关代码可能位于：
- `codex-rs/core/src/sandbox/` - 沙盒实现
- `codex-rs/core/src/sandbox/seatbelt.rs` - macOS Seatbelt 沙盒
- `codex-rs/core/src/approval.rs` 或类似文件 - 批准流程

### 沙盒技术（根据 AGENTS.md 推测）

根据 AGENTS.md 的内容：
- **macOS**: Seatbelt (`/usr/bin/sandbox-exec`)
- **Linux**: Landlock, seccomp（推测）
- **环境变量**: `CODEX_SANDBOX=seatbelt`

## 依赖与外部交互

### 外部依赖

1. **OpenAI 开发者门户**
   - 详细安全文档

2. **操作系统沙盒机制**
   - macOS Seatbelt
   - Linux Landlock/seccomp
   - Windows 沙盒 API（推测）

### 可能的沙盒功能（推测）

基于常见安全模型，沙盒可能提供：

1. **文件系统隔离**
   - 只读访问
   - 受限写入路径
   - 工作目录限制

2. **网络隔离**
   - 完全禁用网络
   - 受限网络访问
   - 代理支持

3. **进程限制**
   - 可执行命令白名单
   - 资源限制（CPU、内存）
   - 超时控制

4. **批准流程**
   - 操作前确认
   - 风险分级
   - 自动批准规则

## 风险、边界与改进建议

### 潜在风险

1. **文档过于简略**
   - 当前文档仅包含一个链接，离线时无法查看
   - 建议：添加基本的安全概念说明

2. **链接失效风险**
   - 外部链接可能变更
   - 建议：定期检查链接有效性

3. **安全意识不足**
   - 用户可能不了解安全风险
   - 建议：添加安全警告和最佳实践

### 边界情况

1. **平台差异**
   - 不同操作系统的沙盒能力差异
   - 跨平台一致性挑战

2. **企业环境**
   - 与现有安全基础设施的集成
   - 合规要求

3. **性能影响**
   - 沙盒对性能的影响
   - 资源开销

### 改进建议

1. **安全概览**
   - 添加安全模型概述
   - 说明不同沙盒级别

2. **配置示例**
   - 提供沙盒配置示例
   - 常见场景的推荐设置

3. **故障排除**
   - 沙盒相关问题的诊断
   - 常见错误和解决方案

4. **审计日志**
   - 记录沙盒事件
   - 提供安全审计报告

5. **最佳实践**
   - 安全使用指南
   - 风险缓解建议

6. **平台特定说明**
   - 不同操作系统的沙盒配置
   - 平台限制说明
