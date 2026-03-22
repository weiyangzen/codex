# CHANGELOG.md 研究文档

## 场景与职责

`CHANGELOG.md` 是项目的变更日志文件，用于记录项目的版本历史、功能变更、bug 修复和其他重要更新。该文件位于项目根目录，是用户和开发者了解项目演进的重要入口。

Codex 项目的 `CHANGELOG.md` 采用了一种简洁的方式，将用户引导到 GitHub Releases 页面查看详细的变更历史，而不是在仓库中维护详细的变更日志。

## 功能点目的

### 1. 引导至 Releases 页面

```markdown
The changelog can be found on the [releases page](https://github.com/openai/codex/releases).
```

**目的**：告知用户详细的变更日志位于 GitHub Releases 页面。

**技术背景**：
- GitHub Releases 提供了结构化的版本发布信息
- 支持附件（如二进制文件、压缩包）
- 支持分类（如 "Features", "Bug Fixes", "Breaking Changes"）
- 便于用户订阅发布通知

**优势**：
- 减少仓库中的重复信息
- 利用 GitHub 的原生功能
- 便于维护者发布版本时同时更新 Release 说明

## 具体技术实现

### 文件格式

`CHANGELOG.md` 使用 Markdown 格式，内容极其简洁：

```markdown
The changelog can be found on the [releases page](https://github.com/openai/codex/releases).
```

### 与 GitHub Releases 的关系

```
CHANGELOG.md (仓库内)
    └── 链接到 ───> GitHub Releases (GitHub 平台)
                        ├── v1.0.0
                        │   ├── 发布说明
                        │   ├── 附件
                        │   └── 标签
                        ├── v0.9.0
                        └── ...
```

### 与 .gitignore 的关系

```gitignore
# .gitignore
CHANGELOG.ignore.md
```

`.gitignore` 中排除了 `CHANGELOG.ignore.md`，这可能是用于生成或过滤变更日志的临时文件。

## 关键代码路径与文件引用

### 相关文件

1. **.gitignore**
   - 排除 `CHANGELOG.ignore.md`
   - 可能是变更日志生成工具的临时文件

2. **cliff.toml**
   - 可能是 git-cliff 的配置文件
   - git-cliff 是一个变更日志生成工具

3. **.github/workflows/** (发布工作流)
   - `rust-release.yml`
   - `rust-release-prepare.yml`
   - `rust-release-windows.yml`
   - 这些工作流可能创建 GitHub Releases

4. **GitHub Releases**
   - 实际的变更日志位置
   - https://github.com/openai/codex/releases

### 发布流程

```
1. 开发者创建标签（如 v1.0.0）
2. GitHub Actions 工作流触发
3. 构建发布二进制文件
4. 创建 GitHub Release
5. 填写发布说明（手动或自动生成）
6. 用户通过 CHANGELOG.md 链接访问 Releases
```

## 依赖与外部交互

### GitHub Releases

**功能**：
- 版本发布管理
- 发布说明（Release Notes）
- 二进制附件
- 自动生成的变更日志（基于 PR 标签）

**访问方式**：
- Web：https://github.com/openai/codex/releases
- API：`GET /repos/openai/codex/releases`
- RSS/Atom 订阅

### 可能的变更日志工具

**git-cliff**（如果 cliff.toml 存在）：
```toml
# cliff.toml 配置
[changelog]
header = "# Changelog\n\n"
body = """
{% for commit in commits %}
- {{ commit.message }}
{% endfor %}
"""
```

**GitHub 自动生成**：
- 基于 PR 标签自动生成发布说明
- 支持分类：Features, Bug fixes, Breaking changes 等

### 与版本控制的关系

```
Git Tags
├── v1.0.0 ───> GitHub Release v1.0.0
├── v0.9.0 ───> GitHub Release v0.9.0
└── ...
```

## 风险、边界与改进建议

### 潜在风险

1. **外部依赖**
   - 变更日志托管在 GitHub 平台
   - 如果迁移到其他平台，链接会失效

2. **信息同步**
   - 需要确保 Releases 页面及时更新
   - 如果发布流程不完善， Releases 可能滞后

3. **离线访问**
   - 克隆仓库后无法查看详细的变更历史
   - 需要网络连接访问 GitHub

4. **搜索和索引**
   - 搜索引擎可能无法索引 Releases 内容
   - 仓库内的搜索无法找到变更信息

### 边界情况

1. **预发布版本**
   - GitHub 支持 pre-release 标记
   - 需要明确区分稳定版和预发布版

2. **安全修复**
   - 安全相关的变更可能需要特别标注
   - GitHub 支持安全公告（Security Advisories）

3. **破坏性变更**
   - 需要清晰的迁移指南
   - Releases 页面可以包含详细说明

### 改进建议

1. **添加版本摘要**
   ```markdown
   # Changelog

   For detailed release notes, see the [releases page](https://github.com/openai/codex/releases).

   ## Recent Highlights

   ### v1.0.0 (Latest)
   - Major release with TUI support
   - See releases page for details

   ### v0.9.0
   - Initial public release
   ```

2. **添加变更日志生成说明**
   ```markdown
   ## Generating Changelog

   This project uses [git-cliff](https://git-cliff.org/) for changelog generation.
   See `cliff.toml` for configuration.
   ```

3. **添加版本策略说明**
   ```markdown
   ## Versioning

   This project follows [Semantic Versioning](https://semver.org/).

   - MAJOR: Breaking changes
   - MINOR: New features (backward compatible)
   - PATCH: Bug fixes (backward compatible)
   ```

4. **考虑维护简要变更日志**
   ```markdown
   ## Notable Changes

   ### 2024
   - Q4: v1.0.0 release with full TUI support
   - Q3: Beta release with core functionality

   ### 2025
   - Q1: Added Windows support
   ```

5. **添加贡献说明**
   ```markdown
   ## Contributing

   When submitting PRs, please use conventional commit messages:
   - `feat:` for new features
   - `fix:` for bug fixes
   - `breaking:` for breaking changes
   ```

### 使用示例

```bash
# 查看本地变更日志
cat CHANGELOG.md

# 访问在线变更日志
open https://github.com/openai/codex/releases

# 使用 GitHub CLI 查看发布
gh release list
gh release view v1.0.0
```

### 与其他项目的对比

| 项目 | 变更日志方式 | 说明 |
|------|-------------|------|
| React | CHANGELOG.md + Releases | 详细的 MD 文件 |
| Kubernetes | CHANGELOG | 详细的目录 |
| Rust | RELEASES.md | 详细的 MD 文件 |
| Codex | 链接到 Releases | 简洁方式 |

**Codex 方式的优势**：
- 维护成本低
- 避免重复信息
- 利用 GitHub 原生功能

**Codex 方式的劣势**：
- 离线无法访问
- 搜索不便
- 依赖外部平台
