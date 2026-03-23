# release-checklist.md 研究文档

## 场景与职责

`release-checklist.md` 是 Bubblewrap 项目的发布流程检查清单，用于指导维护者在发布新版本时执行标准化的发布步骤。该文档确保发布过程的一致性和可重复性，减少人为错误。

### 核心职责

1. **标准化发布流程**：定义从准备到发布的完整步骤
2. **确保发布质量**：包含测试和验证环节
3. **文档化发布历史**：要求更新 NEWS 文件和标签消息
4. **安全发布**：使用 `git evtag sign` 进行加密签名

## 功能点目的

### 1. 发布前准备

```markdown
* Collect release notes in `NEWS`
* Update version number in `meson.build` and release date in `NEWS`
* Commit the changes
```

**目的**：
- 记录变更历史，方便用户了解新版本内容
- 确保版本号一致性（代码、构建系统、文档）
- 通过提交记录发布准备状态

**相关文件**：
- `NEWS`（或 `NEWS.md`）：发布说明
- `meson.build`：版本号定义（第 4 行：`version : '0.11.0'`）

### 2. 构建验证

```markdown
* `meson dist -C ${builddir}`
* Do any final smoke-testing, e.g. update a package, install and test it
```

**目的**：
- 生成发布 tarball
- 验证构建系统能正确生成可分发包
- 进行最终的功能验证

**命令说明**：
- `meson dist`：创建包含所有必要文件的发布包
- `${builddir}`：构建目录变量，如 `_build`

### 3. 标签和签名

```markdown
* `git evtag sign v$VERSION`
    * Include the release notes from `NEWS` in the tag message
```

**目的**：
- 使用 `git-evtag` 创建增强的 Git 标签
- 对标签进行 GPG 签名，确保发布完整性
- 在标签消息中包含发布说明

**工具说明**：
- `git-evtag`：Git 扩展，提供增强的标签签名（包含树哈希）
- 相比标准 `git tag -s`，`git-evtag` 包含更多元数据

### 4. 推送和发布

```markdown
* `git push --atomic origin main v$VERSION`
* https://github.com/containers/bubblewrap/releases/new
    * Fill in the new version's tag in the "Tag version" box
    * Title: `$VERSION`
    * Copy the release notes into the description
    * Upload the tarball that you built with `meson dist`
    * Get the `sha256sum` of the tarball and append it to the description
    * `Publish release`
```

**目的**：
- 原子性推送代码和标签（`--atomic`）
- 在 GitHub 创建正式 Release
- 提供校验和供用户验证下载完整性

**GitHub Release 内容**：
- 标题：版本号
- 描述：发布说明
- 附件：meson dist 生成的 tarball
- 校验和：SHA256 哈希值

## 具体技术实现

### 发布流程图

```
准备阶段
    │
    ├── 收集发布说明 → NEWS
    ├── 更新版本号 → meson.build
    └── 提交变更 → git commit
    │
构建阶段
    │
    ├── 生成发布包 → meson dist
    └── 冒烟测试 → 安装/验证
    │
签名阶段
    │
    ├── 创建签名标签 → git evtag sign
    └── 编写标签消息 → 包含 NEWS
    │
发布阶段
    │
    ├── 推送到远程 → git push --atomic
    ├── 创建 GitHub Release
    ├── 上传 tarball
    └── 添加 SHA256 校验和
```

### 版本号管理

**位置**：`meson.build` 第 4 行
```meson
project(
  'bubblewrap',
  'c',
  version : '0.11.0',  # ← 更新此处
  ...
)
```

**版本号格式**：语义化版本（Semantic Versioning）
- `MAJOR.MINOR.PATCH`
- 示例：`0.11.0`

### 发布包内容

`meson dist` 生成的 tarball 包含：
- 所有源代码文件
- 构建系统文件（meson.build, meson_options.txt）
- 文档（README.md, LICENSE, 等）
- 测试套件
- 预生成的手册页（如果构建过）

**排除内容**：
- 构建产物（*.o, bwrap 二进制文件）
- Git 元数据（.git 目录）
- CI 配置文件（可选）

## 关键代码路径与文件引用

### 相关文件

| 文件 | 用途 | 在发布中的角色 |
|------|------|----------------|
| `meson.build` | 构建配置 | 包含版本号 |
| `NEWS.md` | 发布说明 | 记录变更历史 |
| `release-checklist.md` | 本文件 | 发布流程指南 |
| `.github/workflows/` | CI 配置 | 自动化测试 |

### 工具依赖

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| meson | 构建系统 | 包管理器/pip |
| git-evtag | 增强标签签名 | 单独安装 |
| GPG | 签名验证 | 通常预装 |
| sha256sum | 校验和计算 | coreutils |

## 依赖与外部交互

### 外部服务

1. **GitHub**：
   - 代码托管
   - Release 发布平台
   - URL: https://github.com/containers/bubblewrap

2. **GPG 密钥服务器**（可选）：
   - 分发公钥用于签名验证

### 密钥管理

发布者需要：
- GPG 私钥用于签名标签
- 配置 Git 使用正确的密钥：
  ```bash
  git config user.signingkey YOUR_KEY_ID
  ```

### 用户验证

用户可以通过以下方式验证发布：

```bash
# 验证 Git 标签
git verify-tag v0.11.0

# 验证 tarball 校验和
sha256sum -c bubblewrap-0.11.0.tar.xz.sha256

# 验证 GPG 签名（如果提供 .asc 文件）
gpg --verify bubblewrap-0.11.0.tar.xz.asc
```

## 风险、边界与改进建议

### 风险

1. **版本号不一致**：
   - 风险：meson.build 和 NEWS 中的版本号不匹配
   - 缓解：添加 CI 检查验证版本一致性

2. **测试不充分**：
   - 风险：冒烟测试过于模糊
   - 缓解：定义具体的测试清单

3. **密钥丢失或泄露**：
   - 风险：GPG 私钥丢失导致无法签名
   - 缓解：使用硬件安全密钥，维护密钥备份

4. **网络问题**：
   - 风险：推送失败导致部分发布完成
   - 缓解：`--atomic` 确保原子性

5. **校验和错误**：
   - 风险：手动复制校验和可能出错
   - 缓解：使用命令生成并自动复制

### 边界

1. **手动流程**：
   - 大部分步骤需要人工执行
   - 容易遗漏步骤

2. **单点故障**：
   - 依赖特定维护者的 GPG 密钥
   - 没有提及密钥备份或恢复流程

3. **平台依赖**：
   - 假设使用 GitHub 作为托管平台
   - 命令假设 Linux/Unix 环境

### 改进建议

1. **自动化脚本**：创建 `release.sh` 脚本自动化大部分步骤

2. **CI 集成**：添加 GitHub Actions 工作流自动创建 Release

3. **版本验证**：添加预提交钩子验证版本号一致性

4. **多维护者支持**：定义密钥备份和恢复流程

5. **发布检查清单工具**：开发交互式工具引导发布流程
