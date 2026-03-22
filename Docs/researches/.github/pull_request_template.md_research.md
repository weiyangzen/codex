# pull_request_template.md 研究文档

## 场景与职责

`pull_request_template.md` 是 GitHub Pull Request 模板文件，位于 `.github/pull_request_template.md`。该文件定义了外部贡献者创建 PR 时必须遵循的格式和内容要求，确保 PR 描述包含必要的信息，便于维护者审查。

### 项目贡献政策背景

Codex 项目采用**邀请制贡献模式**：
- **不接受未经邀请的外部代码贡献**
- 外部贡献者只能在被团队成员明确邀请后才能提交 PR
- 未经邀请的 PR 将被直接关闭，不做审查

这一政策在 `docs/contributing.md` 中有详细说明。

### 模板的核心职责

1. **前置筛选**: 在 PR 创建阶段即提醒贡献者阅读贡献指南
2. **信息标准化**: 确保 PR 包含必要的描述信息
3. **流程引导**: 引导贡献者链接到相关的 issue 或功能请求

## 功能点目的

### 1. 贡献政策声明

模板开头明确声明外部贡献要求：
```markdown
# External (non-OpenAI) Pull Request Requirements
```

直接表明这是针对非 OpenAI 员工的贡献指南。

### 2. 贡献指南链接

强制要求贡献者在创建 PR 前阅读贡献文档：
```markdown
Before opening this Pull Request, please read the dedicated "Contributing" markdown file:
https://github.com/openai/codex/blob/main/docs/contributing.md
```

这是 PR 被审查的前提条件。

### 3. PR 描述要求

要求贡献者提供详细、高质量的变更描述：
```markdown
If your PR conforms to our contribution guidelines, replace this text with a detailed and high quality description of your changes.
```

### 4. Issue 关联要求

要求提供相关 issue 或功能请求的链接：
```markdown
Include a link to a bug report or enhancement request.
```

这是追踪变更背景和必要性的关键信息。

## 具体技术实现

### 文件位置与格式

```
.github/pull_request_template.md
```

- **文件名**: `pull_request_template.md`（GitHub 识别的标准文件名）
- **位置**: `.github/` 目录下
- **格式**: Markdown

### GitHub 模板机制

当贡献者在 GitHub 上创建 PR 时：
1. GitHub 自动检测 `.github/pull_request_template.md`
2. 将文件内容预填充到 PR 描述框中
3. 贡献者需要编辑替换模板内容

### 模板内容结构

```markdown
# 标题（政策声明）
[贡献指南链接和要求]

# PR 描述要求
[详细描述变更内容]

# Issue 关联要求
[链接到相关 issue]
```

### 与贡献指南的关系

模板与 `docs/contributing.md` 形成互补：

| 文件 | 作用时机 | 内容深度 |
|-----|---------|---------|
| `pull_request_template.md` | PR 创建时 | 简要提醒 + 格式要求 |
| `docs/contributing.md` | 开发前/PR 创建前 | 详细政策 + 工作流程 |

### 模板工作流程

```
贡献者准备提交 PR
    ↓
创建 PR 时看到模板内容
    ↓
阅读并遵循模板指引
    ├── 阅读 docs/contributing.md
    ├── 确认已被邀请贡献
    ├── 编写详细 PR 描述
    └── 链接相关 issue
    ↓
提交 PR
    ↓
维护者审查
    ├── 检查是否遵循模板
    ├── 验证 issue 链接
    └── 评估变更描述质量
```

## 关键代码路径与文件引用

### 模板文件位置
```
.github/pull_request_template.md
```

### 相关文件

| 文件路径 | 说明 |
|---------|------|
| `docs/contributing.md` | 详细贡献指南，模板中引用的文档 |
| `.github/ISSUE_TEMPLATE/*.yml` | Issue 模板，与 PR 模板配合使用 |
| `.github/workflows/cla.yml` | CLA 签署检查工作流 |
| `.github/workflows/ci.yml` | CI 检查工作流 |

### 依赖关系图

```
.github/pull_request_template.md
    ├── 引用 → docs/contributing.md
    │           ├── 贡献政策说明
    │           ├── 开发工作流程
    │           ├── 代码提交规范
    │           └── CLA 签署要求
    ├── 触发 → .github/workflows/ci.yml
    │           └── PR 创建时运行检查
    └── 关联 → .github/ISSUE_TEMPLATE/
                └── 功能请求/bug 报告模板
```

### 与 Issue 模板的关系

项目配置了多种 Issue 模板：
- `1-codex-app.yml`: Codex App 相关问题
- `2-extension.yml`: 扩展相关问题
- `3-cli.yml`: CLI 相关问题
- `4-bug-report.yml`: 通用 Bug 报告
- `5-feature-request.yml`: 功能请求
- `6-docs-issue.yml`: 文档问题

PR 模板要求链接到这些模板创建的 issue。

## 依赖与外部交互

### GitHub 平台集成

1. **PR 创建界面**
   - GitHub 自动识别 `.github/pull_request_template.md`
   - 在 Web 界面预填充模板内容

2. **PR 审查流程**
   - 维护者通过模板快速判断 PR 是否符合基本要求
   - 未遵循模板的 PR 可被直接关闭

### 与 CLA 签署的交互

`.github/workflows/cla.yml` 在 PR 创建时运行：
- 检查贡献者是否已签署 CLA
- 未签署者会收到自动评论提醒
- 与 PR 模板共同构成贡献门槛

### 与 CI 的交互

`.github/workflows/ci.yml` 在 PR 创建时触发：
- 运行代码检查
- 执行测试套件
- 验证 PR 质量

### 与贡献指南的交互

模板强制链接到 `docs/contributing.md`，其中包含：
- 外部贡献邀请制政策
- 开发工作流程
- 代码提交规范
- 模型元数据更新指南
- 审查流程
- 社区价值观
- CLA 签署流程

## 风险、边界与改进建议

### 潜在风险

1. **模板被忽视**
   - 贡献者可能直接删除模板内容而不阅读
   - 风险：未经邀请的 PR 仍然被提交
   - 缓解：结合自动化检查（如 CLA bot）

2. **信息不足**
   - 模板仅提供框架，依赖贡献者自行填充
   - 风险：PR 描述质量参差不齐
   - 缓解：维护者需要明确质量标准

3. **政策传达不清**
   - 模板标题 "External (non-OpenAI)" 可能让部分贡献者困惑
   - 风险：OpenAI 员工也可能看到此模板

4. **链接失效**
   - 模板中硬编码了 GitHub URL
   - 如果仓库迁移或重命名，链接将失效

### 边界情况

1. **命令行创建 PR**
   - 通过 `gh pr create` 命令行创建 PR 时不会自动填充模板
   - 贡献者需要手动参考模板

2. **Fork 仓库**
   - 从 fork 创建 PR 时，GitHub 使用目标仓库的模板
   - 确保模板更新会应用到所有 PR

3. **多模板支持**
   - 当前只有一个通用模板
   - 不同类型的变更（bug 修复、功能添加、文档更新）可能需要不同模板

4. **国际化**
   - 模板仅提供英文版本
   - 非英语母语贡献者可能理解困难

### 改进建议

1. **添加检查清单**
   ```markdown
   ## 提交前检查清单
   - [ ] 我已阅读贡献指南
   - [ ] 我是被邀请的贡献者
   - [ ] 我已链接相关 issue
   - [ ] 我已运行本地测试
   - [ ] 我的代码遵循项目风格
   ```

2. **分类模板**
   创建多个模板文件：
   ```
   .github/PULL_REQUEST_TEMPLATE/
   ├── bug_fix.md
   ├── feature.md
   └── docs.md
   ```
   让贡献者根据变更类型选择合适模板。

3. **自动化验证**
   添加 GitHub Action 检查：
   - 验证 PR 描述不为空
   - 验证包含 issue 链接（如适用）
   - 自动评论提醒未遵循模板的 PR

4. **改进政策说明**
   ```markdown
   > ⚠️ **重要**: 此项目仅接受被邀请的外部贡献。
   > 未经邀请的 PR 将被关闭。请先提交 issue 讨论。
   ```
   使用更醒目的格式强调政策。

5. **添加变更类型标签**
   ```markdown
   ## 变更类型
   - [ ] Bug 修复
   - [ ] 新功能
   - [ ] 文档更新
   - [ ] 性能优化
   - [ ] 代码重构
   ```

6. **添加测试说明**
   ```markdown
   ## 测试
   - [ ] 我已添加/更新测试
   - [ ] 所有测试通过
   - [ ] 我已手动验证变更
   ```

7. **破坏性变更声明**
   ```markdown
   ## 破坏性变更
   - [ ] 此变更包含破坏性修改
   - [ ] 我已更新相关文档
   ```

8. **截图/示例**
   ```markdown
   ## 截图或示例
   <!-- 如适用，添加截图或代码示例 -->
   ```

9. **相对链接**
   使用相对链接而非绝对 URL：
   ```markdown
   [贡献指南](./docs/contributing.md)
   ```
   这样即使仓库迁移也能正常工作。

10. **多语言支持**
    考虑添加主要语言的模板翻译，或至少提供翻译链接。

### 相关文档

- [GitHub PR 模板文档](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository)
- [GitHub Issue 模板](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository)
- [Codex 贡献指南](./docs/contributing.md)
- [Contributor Covenant](https://www.contributor-covenant.org/)（行为准则）
