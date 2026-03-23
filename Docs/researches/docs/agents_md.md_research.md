# agents_md.md 研究文档

## 场景与职责

agents_md.md 是 Codex CLI 项目中关于 AGENTS.md 功能的说明文档。AGENTS.md 是一种项目级配置文件，用于为 AI 编码助手（如 Codex）提供项目特定的上下文、约定和指导。

**适用场景：**
- 开发者需要了解 AGENTS.md 的作用和使用方式
- 项目维护者想要为 AI 助手配置项目特定的行为
- 启用 `child_agents_md` 功能标志时的附加指导

## 功能点目的

### 1. AGENTS.md 基础功能
- **目的**：为 AI 助手提供项目特定的上下文和指导
- **作用**：补充 README.md，包含 AI 助手需要的额外信息，如构建步骤、测试约定、编码风格等

### 2. 分层代理消息（Hierarchical agents message）
- **功能标志**：`child_agents_md`
- **配置位置**：`config.toml` 的 `[features]` 部分
- **行为**：
  - 启用后，Codex 会在用户指令消息后附加关于 AGENTS.md 范围和优先级的额外指导
  - 即使没有 AGENTS.md 文件存在，也会发出该消息

## 具体技术实现

### 功能标志配置

```toml
[features]
child_agents_md = true
```

### 消息注入机制

```
用户输入
    ↓
系统构建上下文
    ↓
检查 child_agents_md 功能标志
    ↓
如果启用：附加 AGENTS.md 范围和优先级指导
    ↓
发送到 AI 模型
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/agents_md.md` | 本文档 |
| `/home/sansha/Github/codex/AGENTS.md` | 项目根目录的 AGENTS.md（项目级配置） |
| `/home/sansha/Github/codex/codex-rs/` | Rust 代码目录，可能包含功能标志处理 |

### 外部文档引用

- 官方文档：https://developers.openai.com/codex/guides/agents-md

## 依赖与外部交互

### 内部依赖

1. **配置系统**
   - 依赖 `config.toml` 的解析
   - `[features]` 部分的读取

2. **提示词构建系统**
   - 在构建发送到 AI 模型的提示词时注入附加消息

### 外部依赖

1. **OpenAI 开发者文档**
   - 官方 AGENTS.md 指南

## 风险、边界与改进建议

### 潜在风险

1. **信息冗余**
   - 即使没有 AGENTS.md 文件也会发出消息，可能造成提示词冗余
   - 建议：评估消息长度对 token 消耗的影响

2. **功能标志混淆**
   - 用户可能不清楚 `child_agents_md` 的具体作用
   - 建议：在文档中提供更多使用示例

### 边界情况

1. **空项目**
   - 新项目没有 AGENTS.md 时的默认行为

2. **多层 AGENTS.md**
   - 子目录中的 AGENTS.md 与根目录的优先级关系

### 改进建议

1. **文档完善**
   - 添加 AGENTS.md 文件格式示例
   - 说明范围和优先级的具体规则

2. **功能增强**
   - 考虑支持目录级别的 AGENTS.md
   - 添加 AGENTS.md 验证工具

3. **可见性提升**
   - 在 TUI 中显示当前生效的 AGENTS.md 配置
   - 提供 AGENTS.md 调试模式
