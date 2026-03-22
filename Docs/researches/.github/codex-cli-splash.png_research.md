# .github/codex-cli-splash.png 研究文档

## 场景与职责

`.github/codex-cli-splash.png` 是 OpenAI Codex CLI 项目的**品牌展示图片**，用于在 GitHub 仓库首页（README.md）中直观展示 Codex CLI 的终端界面外观和核心功能。该图片是项目的门面资产，承担以下职责：

1. **品牌识别**：作为 Codex CLI 的视觉标识，展示产品的终端界面风格
2. **功能预览**：通过截图形式向潜在用户展示 CLI 的交互方式和界面布局
3. **文档增强**：在 README 中提供视觉吸引力，帮助用户快速理解产品形态
4. **营销传播**：在 npm 包页面、GitHub 社交预览等场景下展示产品形象

### 历史演变

该图片经历了多次迭代更新：

| 时间 | Commit | 变更内容 |
|------|--------|----------|
| 2025-04-16 | `59a180dd` (Initial commit) | 初始版本使用 `.github/demo.gif` (19.7MB 动画) |
| 2025-08-07 | `e07776ccc` | 首次引入 `codex-cli-splash.png` (422,175 bytes)，同时新增 `codex-cli-login.png` 和 `codex-cli-permissions.png` |
| 2025-08-27 | `459363e17` | README 重构，优化图片展示 |
| 2026-01-02 | `ab753387c` | 精简文档，删除 `demo.gif`、`codex-cli-login.png` 和 `codex-cli-permissions.png`，仅保留 `codex-cli-splash.png` |
| 2026-01-31 | `e77744428` | 修复 npm README 图片链接，将相对路径改为 GitHub 绝对 URL |
| 2026-02-12 | `1de251c40` | **最新更新**：优化图片，大小从 838,131 bytes 缩减至 246,331 bytes（压缩率 70.6%）|

## 功能点目的

### 1. 视觉展示目的

- **终端界面展示**：展示 Codex CLI 的 TUI（Terminal User Interface）外观，包括：
  - 命令输入区域
  - AI 响应展示区域
  - 文件变更提示（如 `M` 表示修改）
  - 状态栏和底部信息

- **品牌一致性**：图片风格与 OpenAI 品牌保持一致，使用简洁的终端配色

### 2. 技术目的

- **静态资源替代**：替代早期过大的 `demo.gif` (19.7MB)，显著减少仓库克隆大小
- **快速加载**：优化后的 PNG 图片（246KB）确保 GitHub 页面快速加载
- **跨平台兼容**：PNG 格式确保在所有浏览器和 Markdown 渲染器中正常显示

### 3. 文档集成目的

当前在 `README.md` 中的引用方式：

```markdown
<p align="center">
  <img src="https://github.com/openai/codex/blob/main/.github/codex-cli-splash.png" alt="Codex CLI splash" width="80%" />
</p>
```

- 使用 `width="80%"` 确保响应式布局
- 使用绝对 URL 确保在 npm 包页面也能正常显示

## 具体技术实现

### 图片规格

```
文件格式：PNG (Portable Network Graphics)
分辨率：1898 x 1190 像素
色彩模式：8-bit/color RGBA
压缩：non-interlaced
文件大小：246,331 bytes (约 240KB)
```

### 存储位置与版本控制

```
仓库路径：.github/codex-cli-splash.png
Git LFS：否（直接存储在 Git 中）
```

### 大文件管理策略

由于该文件超过 500KB 阈值（历史版本曾达 838KB），项目通过以下机制管理：

#### 1. Blob Size Policy 工作流

文件：`.github/workflows/blob-size-policy.yml`

```yaml
name: blob-size-policy
on:
  pull_request: {}

jobs:
  check:
    name: Blob size policy
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Determine PR comparison range
        id: range
        run: |
          set -euo pipefail
          echo "base=$(git rev-parse HEAD^1)" >> "$GITHUB_OUTPUT"
          echo "head=$(git rev-parse HEAD^2)" >> "$GITHUB_OUTPUT"

      - name: Check changed blob sizes
        env:
          BASE_SHA: ${{ steps.range.outputs.base }}
          HEAD_SHA: ${{ steps.range.outputs.head }}
        run: |
          python3 scripts/check_blob_size.py \
            --base "$BASE_SHA" \
            --head "$HEAD_SHA" \
            --max-bytes 512000 \
            --allowlist .github/blob-size-allowlist.txt
```

#### 2. 豁免列表

文件：`.github/blob-size-allowlist.txt`

```
# Paths are matched exactly, relative to the repository root.
# Keep this list short and limited to intentional large checked-in assets.

.github/codex-cli-splash.png
MODULE.bazel.lock
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json
codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json
codex-rs/tui/tests/fixtures/oss-story.jsonl
codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl
```

该图片被明确列入豁免列表，允许其超过 512KB 的默认大小限制。

#### 3. 检查脚本

文件：`scripts/check_blob_size.py`

核心逻辑：
- 默认最大文件大小：500KB (`DEFAULT_MAX_BYTES = 500 * 1024`)
- 检查新增/修改的文件（`--diff-filter=AM`）
- 支持通过 `--allowlist` 指定豁免文件
- 生成 GitHub Actions 步骤摘要（Step Summary）

### 图片优化历史

2026-02-12 的更新 (`1de251c40`) 将图片从 838,131 bytes 优化至 246,331 bytes：

```bash
# 优化前
$ git show 1de251c40^:.github/codex-cli-splash.png | wc -c
838131

# 优化后
$ git show 1de251c40:.github/codex-cli-splash.png | wc -c
246331

# 压缩率：(838131 - 246331) / 838131 ≈ 70.6%
```

## 关键代码路径与文件引用

### 直接引用

| 文件 | 引用方式 | 用途 |
|------|----------|------|
| `README.md` | `<img src="https://github.com/openai/codex/blob/main/.github/codex-cli-splash.png" ...>` | 主仓库展示 |

### 相关配置文件

| 文件 | 关联关系 | 说明 |
|------|----------|------|
| `.github/blob-size-allowlist.txt` | 豁免列表 | 允许该文件超过大小限制 |
| `.github/workflows/blob-size-policy.yml` | CI 工作流 | 检查 PR 中的大文件 |
| `scripts/check_blob_size.py` | 检查脚本 | 实现文件大小检查逻辑 |

### Git 历史相关 Commit

```
1de251c40 - update terminal image (2026-02-12)
ab753387c - Replaced user documentation with links to developers docs site (#8662) (2026-01-02)
459363e17 - README / docs refactor (#2724) (2025-08-27)
e07776ccc - update readme (#1948) (2025-08-07) - 首次引入
```

## 依赖与外部交互

### 内部依赖

1. **README.md**：图片的主要消费者，用于项目首页展示
2. **CI/CD 系统**：通过 `blob-size-policy.yml` 工作流监控文件变更

### 外部依赖

1. **GitHub CDN**：图片通过 `https://github.com/openai/codex/blob/main/.github/codex-cli-splash.png` 提供访问
2. **npm 包页面**：README 中的绝对 URL 确保图片在 npmjs.com 上正常显示

### 生成来源

该图片是**手动生成的截图**，非自动构建产物。根据项目实践：
- 截图来自 Codex CLI TUI 的实际运行界面
- 通常由开发团队手动捕获并优化
- 更新频率较低，仅在重大 UI 变更时更新

### 相关 TUI 代码（图片内容来源）

图片展示的界面来自以下 Rust TUI 代码：

| 模块 | 文件路径 | 功能 |
|------|----------|------|
| TUI App | `codex-rs/tui/src/app.rs` | 主应用逻辑 |
| Chat Widget | `codex-rs/tui/src/chatwidget.rs` | 聊天界面渲染 |
| History Cell | `codex-rs/tui/src/history_cell.rs` | 历史记录单元格展示 |
| Text Formatting | `codex-rs/tui/src/text_formatting.rs` | 文本格式化（含路径截断）|

## 风险、边界与改进建议

### 当前风险

#### 1. 文件大小风险
- **现状**：当前 246KB 已低于 500KB 阈值，但历史版本曾达 838KB
- **风险**：未来更新若未优化，可能再次触发大小检查警告
- **缓解**：已列入豁免列表，但应保持优化习惯

#### 2. 缓存失效风险
- **现状**：GitHub CDN 对 raw 文件有缓存
- **风险**：更新图片后，外部引用（如第三方文档）可能显示旧版本
- **缓解**：使用 commit 特定的 URL 或添加 cache-busting 参数

#### 3. 单点依赖风险
- **现状**：README 中仅依赖这一张图片展示产品界面
- **风险**：图片损坏或链接失效会导致首页展示异常
- **缓解**：GitHub/npm 双平台验证，使用可靠的 GitHub 托管 URL

### 边界情况

#### 1. 图片格式边界
- 当前使用 PNG 格式，适合 UI 截图
- 若未来需要动画展示，需考虑：
  - 使用外部托管（如 GitHub Assets）避免仓库膨胀
  - 或转换为 WebP/AVIF 等更现代格式

#### 2. 分辨率边界
- 当前 1898x1190 适合桌面展示
- 在移动设备上可能显示过小
- README 中已使用 `width="80%"` 缓解

#### 3. 版本兼容性边界
- 图片展示的是特定版本的 UI
- 若 CLI 界面有重大改版，图片可能过时
- 需要与产品发布节奏同步更新

### 改进建议

#### 1. 自动化优化（推荐）

添加 CI 步骤，在 PR 修改图片时自动优化：

```yaml
# .github/workflows/optimize-assets.yml
name: Optimize Assets
on:
  pull_request:
    paths:
      - '.github/*.png'
      - '.github/*.jpg'

jobs:
  optimize:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Optimize PNG
        uses: calibreapp/image-actions@main
        with:
          githubToken: ${{ secrets.GITHUB_TOKEN }}
          compressOnly: true
```

#### 2. 多分辨率支持

考虑提供响应式图片：

```markdown
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="...">
  <img src="https://github.com/openai/codex/blob/main/.github/codex-cli-splash.png" 
       alt="Codex CLI splash" width="80%" />
</picture>
```

#### 3. 文档化更新流程

建议创建 `docs/assets.md` 文档，规范：
- 截图捕获标准（终端尺寸、配色方案、示例命令）
- 图片优化工具推荐（如 ImageOptim、oxipng）
- 更新审批流程

#### 4. 替代方案评估

| 方案 | 优点 | 缺点 |
|------|------|------|
| 保持现状 (PNG in repo) | 简单可靠，版本控制 | 仓库体积增长 |
| GitHub Releases Assets | 不增加仓库大小 | 版本管理复杂 |
| 外部 CDN (如 Cloudinary) | 自动优化，全球加速 | 外部依赖，成本 |
| SVG 矢量图 | 无限缩放，极小体积 | 无法展示实际界面 |

**建议**：当前方案（优化后的 PNG + 豁免列表）是平衡简单性和性能的最佳选择。

#### 5. 监控与告警

建议添加定期检查：
- 监控图片加载性能（Lighthouse CI）
- 检查外部引用是否 404
- 定期评估是否需要更新截图以反映最新 UI

---

## 附录：相关文件清单

### 核心文件
- `.github/codex-cli-splash.png` - 本研究对象
- `README.md` - 主要引用方

### 配置与策略
- `.github/blob-size-allowlist.txt` - 大文件豁免列表
- `.github/workflows/blob-size-policy.yml` - 大小检查工作流
- `scripts/check_blob_size.py` - 检查脚本实现

### 历史相关文件（已删除）
- `.github/demo.gif` (19.7MB) - 初始动画，已删除
- `.github/codex-cli-login.png` - 登录界面截图，已删除
- `.github/codex-cli-permissions.png` - 权限界面截图，已删除

### TUI 源码（图片内容来源）
- `codex-rs/tui/src/app.rs`
- `codex-rs/tui/src/chatwidget.rs`
- `codex-rs/tui/src/history_cell.rs`
- `codex-rs/tui/src/text_formatting.rs`
- `codex-rs/tui/src/selection_list.rs`
