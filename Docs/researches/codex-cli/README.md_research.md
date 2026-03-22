# codex-cli/README.md 研究文档

## 场景与职责

`codex-cli/README.md` 是 OpenAI Codex CLI（TypeScript/Node.js 实现）的用户文档。根据文件开头的 **IMPORTANT** 提示：

> "This is the documentation for the _legacy_ TypeScript implementation of the Codex CLI. It has been superseded by the _Rust_ implementation."

该文档目前处于**维护模式**，主要服务于：
1. 仍在使用旧版 TypeScript CLI 的用户
2. 需要了解 Codex CLI 历史功能和配置的用户
3. 贡献者（了解开发流程和贡献指南）

## 功能点目的

### 1. 项目介绍与定位
- **产品定位**："Lightweight coding agent that runs in your terminal"
- **核心价值**：ChatGPT-level reasoning + 代码执行能力 + 版本控制集成
- **关键特性**：
  - Zero setup（仅需 OpenAI API key）
  - Full auto-approval with sandboxing
  - Multimodal（支持截图/图表输入）

### 2. 安全模型文档化
文档详细说明了三种权限模式（Approval Mode）：

| 模式 | 自动允许 | 需批准 |
|------|----------|--------|
| **Suggest** (默认) | 读取文件 | 所有写入、所有 shell 命令 |
| **Auto Edit** | 读取、应用补丁写入 | 所有 shell 命令 |
| **Full Auto** | 读取/写入文件、执行 shell 命令 | 无 |

**平台沙箱机制**：
- **macOS 12+**：Apple Seatbelt (`sandbox-exec`)
- **Linux**：Docker 容器 + iptables/ipset 防火墙
- **Windows**：WSL2（间接支持）

### 3. 安装与配置指南
- **npm 安装**：`npm install -g @openai/codex`
- **多包管理器支持**：npm、yarn、bun、pnpm
- **源码构建**：corepack + pnpm 工作流
- **Nix 支持**：flake.nix 集成

### 4. 配置系统文档
配置文件位置：`~/.codex/`（支持 YAML 和 JSON）

**核心配置项**：
- `model`：AI 模型（默认 `o4-mini`）
- `approvalMode`：权限模式
- `fullAutoErrorMode`：全自动化错误处理
- `notify`：桌面通知开关

**多提供商支持**：
- OpenAI（默认）
- Azure、OpenRouter、Gemini、Ollama
- Mistral、DeepSeek、xAI、Groq、ArceeAI

### 5. 开发工作流
- **Git hooks**：Husky + lint-staged
- **代码质量**：ESLint + Prettier + TypeScript
- **测试**：Vitest
- **提交前检查**：`pnpm test && pnpm run lint && pnpm run typecheck`

### 6. 发布流程
```bash
# 准备发布
pnpm stage-release

# 包含原生二进制（Rust CLI）
pnpm stage-release --native

# 发布到 npm
cd "$RELEASE_DIR"
npm publish
```

## 具体技术实现

### 文档结构分析

```
README.md (736 lines)
├── 标题与安装命令
├── 重要提示（Legacy 声明）
├── 演示 GIF
├── 目录（ToC）
├── 实验性技术声明
├── Quickstart
├── 产品价值主张
├── 安全模型与权限
├── 系统要求
├── CLI 参考
├── Memory & project docs (AGENTS.md)
├── 非交互式/CI 模式
├── 追踪/日志
├── 使用示例（Recipes）
├── 安装指南
├── 配置指南（详细）
├── FAQ
├── 零数据保留（ZDR）
├── 开源基金
├── 贡献指南（详细）
├── 安全与责任 AI
└── 许可证
```

### 关键配置示例

**完整配置（JSON）**：
```json
{
  "model": "o4-mini",
  "provider": "openai",
  "providers": {
    "openai": {
      "name": "OpenAI",
      "baseURL": "https://api.openai.com/v1",
      "envKey": "OPENAI_API_KEY"
    },
    // ... 其他提供商
  },
  "history": {
    "maxSize": 1000,
    "saveHistory": true,
    "sensitivePatterns": []
  }
}
```

**AGENTS.md 层级**：
1. `~/.codex/AGENTS.md` - 个人全局指导
2. `AGENTS.md`（仓库根目录）- 项目共享笔记
3. `AGENTS.md`（当前工作目录）- 子文件夹/功能特定

### 调试配置

**VS Code 调试**：
```bash
pnpm run build  # 生成 cli.js.map
node --inspect-brk ./dist/cli.js
# 然后在 VS Code 中选择 "Debug: Attach to Node Process"
```

**Chrome DevTools**：
- 访问 `chrome://inspect`
- 查找 `localhost:9229`

## 关键代码路径与文件引用

### 文档中引用的关键文件

| 文档引用 | 实际文件 | 说明 |
|----------|----------|------|
| `../.github/demo.gif` | `.github/demo.gif` | 演示动画 |
| `./HUSKY.md` | `codex-cli/HUSKY.md` | Git hooks 文档 |
| `../README.md` | 仓库根 README | 新版 Rust CLI 文档 |
| `codex-cli/scripts/` | `codex-cli/scripts/` | 构建和发布脚本 |

### 配置系统实现

配置读取逻辑（根据文档推断，实际实现在 Rust/TS 代码中）：
```
~/.codex/config.yaml 或 ~/.codex/config.json
    ↓
环境变量（优先级更高）
    ↓
命令行参数（最高优先级）
```

### 相关源码目录

根据 `package.json` 和文档：
```
codex-cli/
├── bin/codex.js          # 入口点（Node.js wrapper）
├── bin/rg                # DotSlash 清单（ripgrep）
├── dist/                 # 构建输出（TypeScript 编译）
├── scripts/              # 构建和工具脚本
│   ├── build_container.sh
│   ├── build_npm_package.py
│   ├── install_native_deps.py
│   ├── run_in_container.sh
│   └── init_firewall.sh
├── package.json
└── README.md
```

## 依赖与外部交互

### 运行时依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| Node.js 16+ | 必需 | JavaScript 运行时 |
| OpenAI API Key | 必需 | AI 服务认证 |
| Git 2.23+ | 可选 | PR 助手功能 |

### 多提供商支持

文档列出了 10+ 个 AI 提供商，每个需要：
- 环境变量：`<PROVIDER>_API_KEY`
- 可选：`<PROVIDER>_BASE_URL`

### 沙箱依赖

**macOS**：
- `sandbox-exec`（系统自带）

**Linux**：
- Docker
- `iptables`/`ipset`
- `run_in_container.sh` 脚本

### 开发依赖

根据开发工作流章节：
- pnpm（包管理）
- Vitest（测试）
- ESLint + Prettier（代码质量）
- Husky（Git hooks）
- TypeScript（类型检查）

## 风险、边界与改进建议

### 当前风险

1. **文档过时风险**
   - 明确标记为 "legacy"，但仍有用户可能混淆新旧版本
   - 建议添加更醒目的警告，指向新版 Rust CLI 文档

2. **安全模式描述不完整**
   - 未详细说明 Linux Docker 沙箱的具体限制
   - 缺少故障排查指南（如防火墙配置失败）

3. **配置格式不一致**
   - 配置文件使用 camelCase（`approvalMode`）
   - 但环境变量使用大写下划线（`OPENAI_API_KEY`）
   - 可能导致用户混淆

4. **多提供商配置复杂**
   - 完整配置示例长达 50+ 行
   - 缺少配置验证工具

### 边界情况

1. **Windows 支持**
   - 仅支持 WSL2，原生 Windows 不支持
   - 文档中说明不够突出

2. **Node.js 版本**
   - 最低要求 Node 16，但推荐 Node 20 LTS
   - 旧版本可能存在兼容性问题

3. **网络限制**
   - Full Auto 模式网络被禁用
   - 某些用例（如需要访问内部 API）可能受限

### 改进建议

#### 1. 文档结构优化
```markdown
<!-- 添加更醒目的 Legacy 警告 -->
> [!WARNING]
> **This documentation is for the legacy TypeScript implementation.**
> For the new Rust implementation, see [root README](../README.md).
> The TypeScript version will receive security updates until [DATE].
```

#### 2. 添加迁移指南
- 从 TypeScript CLI 迁移到 Rust CLI 的步骤
- 配置兼容性说明
- 功能差异对照表

#### 3. 安全配置检查清单
```markdown
## 安全检查清单

在使用 Full Auto 模式前，请确认：
- [ ] 工作目录已初始化 Git 仓库
- [ ] 已审查 `.gitignore` 排除敏感文件
- [ ] 了解当前权限模式的能力边界
- [ ] （Linux）Docker 已正确安装并运行
```

#### 4. 故障排查章节
添加常见问题：
- "Firewall configuration failed" 错误处理
- Docker 权限问题（Linux）
- Seatbelt 配置错误（macOS）
- API key 权限不足

#### 5. 配置验证工具
建议提供：
```bash
# 验证配置文件
npx @openai/codex --validate-config

# 测试提供商连接
npx @openai/codex --test-connection
```

#### 6. 性能优化建议
- 大型代码库的内存配置
- 网络超时调整
- 历史记录清理

### 与新版 Rust CLI 的协调

建议在该文档中添加：
1. 功能对比表（TypeScript vs Rust）
2. 迁移时间线
3. 问题反馈渠道（区分新旧版本）

### 社区贡献优化

1. **Issue 模板**：区分 TypeScript 和 Rust 版本问题
2. **PR 标签**：添加 `legacy-cli` 标签
3. **文档版本化**：使用 Docusaurus 或类似工具管理多版本文档
