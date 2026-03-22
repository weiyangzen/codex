# codex-rs/skills/src/assets/samples 目录研究文档

## 概述

本目录是 Codex CLI 项目的**系统级 Skill（技能）样本库**，包含三个内置的系统技能：`openai-docs`、`skill-creator` 和 `skill-installer`。这些技能在编译时被嵌入到二进制中，在运行时自动解压到用户的 `$CODEX_HOME/skills/.system` 目录，为 Codex 提供开箱即用的功能扩展。

---

## 场景与职责

### 核心定位

该目录是 **Codex Skill 系统的基石**，承担着以下关键职责：

1. **预置系统技能**：提供 Codex 运行所必需的基础能力
2. **技能模板参考**：作为用户创建自定义技能的规范示例
3. **渐进式披露设计**：展示 Skill 系统的三层加载架构（Metadata → SKILL.md → Bundled Resources）

### 使用场景

| 场景 | 说明 |
|------|------|
| 首次启动 | Codex 启动时自动将样本解压到 `.system` 目录 |
| 版本更新 | 通过指纹标记检测样本变化，自动更新系统技能 |
| 离线使用 | 无需网络即可使用系统技能 |
| 技能开发 | 开发者参考样本结构创建新技能 |

---

## 功能点目的

### 1. openai-docs（OpenAI 文档技能）

**目的**：提供权威的 OpenAI 开发者文档查询能力

**核心功能**：
- 通过 MCP (Model Context Protocol) 与 OpenAI 开发者文档服务器交互
- 提供模型选择建议（`latest-model.md`）
- 支持 GPT-5.4 升级指导（`upgrading-to-gpt-5p4.md`）
- 提供提示词优化指南（`gpt-5p4-prompting-guide.md`）

**触发条件**：用户询问 OpenAI 产品/API 相关问题、模型选择、升级指导

### 2. skill-creator（技能创建器）

**目的**：指导用户创建有效的 Codex Skill

**核心功能**：
- 提供 Skill 创建的最佳实践和原则
- 包含初始化脚本 `init_skill.py` 生成技能模板
- 提供 `generate_openai_yaml.py` 生成 UI 元数据
- 提供 `quick_validate.py` 验证技能结构

**设计哲学**：
- **Concise is Key**：上下文窗口是公共资源，只添加必要信息
- **渐进式披露**：三层加载系统（Metadata → SKILL.md → Resources）
- **自由度匹配**：根据任务脆弱性选择文本/伪代码/脚本

### 3. skill-installer（技能安装器）

**目的**：从 GitHub 仓库安装社区技能

**核心功能**：
- `list-skills.py`：列出可安装的技能（默认从 `openai/skills` 的 `.curated` 目录）
- `install-skill-from-github.py`：支持从任意 GitHub 仓库安装技能
- 支持两种安装方式：直接下载 ZIP / Git sparse checkout
- 支持私有仓库（通过 `GITHUB_TOKEN`/`GH_TOKEN`）

---

## 具体技术实现

### 编译时嵌入机制

**关键代码路径**：`codex-rs/skills/src/lib.rs`

```rust
// 使用 include_dir 宏在编译时嵌入整个样本目录
const SYSTEM_SKILLS_DIR: Dir = include_dir::include_dir!("$CARGO_MANIFEST_DIR/src/assets/samples");
```

**构建脚本**：`codex-rs/skills/build.rs`

```rust
// 监控样本目录变化，触发重新编译
println!("cargo:rerun-if-changed={}", samples_dir.display());
```

### 运行时安装流程

**关键代码路径**：`codex-rs/skills/src/lib.rs:47-78`

```rust
pub fn install_system_skills(codex_home: &Path) -> Result<(), SystemSkillsError> {
    // 1. 计算嵌入式样本的指纹
    let expected_fingerprint = embedded_system_skills_fingerprint();
    
    // 2. 检查标记文件，避免不必要的重复安装
    if marker_matches(&marker_path, expected_fingerprint) {
        return Ok(()); // 已是最新，跳过
    }
    
    // 3. 清理旧版本
    if dest_system.exists() {
        fs::remove_dir_all(dest_system.as_path())?;
    }
    
    // 4. 写入新版本的嵌入式目录
    write_embedded_dir(&SYSTEM_SKILLS_DIR, &dest_system)?;
    
    // 5. 更新标记文件
    fs::write(marker_path.as_path(), format!("{expected_fingerprint}\n"))?;
}
```

**指纹计算逻辑**：
- 遍历所有嵌入的文件和目录
- 使用 `DefaultHasher` 计算每个文件内容的哈希
- 加入 salt "v1" 防止版本混淆
- 最终生成 16 进制指纹字符串

### Skill 加载架构

**关键代码路径**：`codex-rs/core/src/skills/loader.rs`

**三层加载系统**：

| 层级 | 内容 | 加载时机 | 大小限制 |
|------|------|----------|----------|
| Metadata | `name` + `description` | 始终加载 | ~100 词 |
| SKILL.md Body | 完整 Markdown 说明 | Skill 触发后 | <5k 词 |
| Bundled Resources | scripts/references/assets | 按需加载 | 无限制（脚本可直接执行） |

**文件结构规范**：

```
skill-name/
├── SKILL.md              # 必需：YAML frontmatter + Markdown 正文
├── agents/
│   └── openai.yaml       # 推荐：UI 元数据（display_name, icon 等）
├── scripts/              # 可选：可执行脚本
├── references/           # 可选：参考文档
└── assets/               # 可选：资源文件（图标、模板等）
```

### Skill 元数据解析

**YAML Frontmatter 格式**：

```yaml
---
name: skill-name
description: "Skill 描述，包含使用场景和触发条件"
metadata:
  short-description: "短描述（25-64字符）"
---
```

**agents/openai.yaml 格式**：

```yaml
interface:
  display_name: "UI 显示名称"
  short_description: "短描述"
  icon_small: "./assets/icon-small.svg"
  icon_large: "./assets/icon-large.png"
  brand_color: "#3B82F6"
  default_prompt: "默认提示词"

dependencies:
  tools:
    - type: "mcp"
      value: "server-name"
      description: "工具描述"
      transport: "streamable_http"
      url: "https://..."

policy:
  allow_implicit_invocation: true  # 是否允许隐式调用
```

### Skill 作用域（Scope）

**关键代码路径**：`codex-rs/core/src/skills/loader.rs:218-245`

| Scope | 来源 | 优先级 |
|-------|------|--------|
| `Repo` | 项目 `.codex/skills` 或 `.agents/skills` | 最高 |
| `User` | `$CODEX_HOME/skills` 或 `$HOME/.agents/skills` | 中 |
| `System` | 嵌入式系统技能（`.system`） | 低 |
| `Admin` | `/etc/codex/skills` | 最低 |

---

## 关键代码路径与文件引用

### 样本目录文件清单

```
codex-rs/skills/src/assets/samples/
├── openai-docs/                          # OpenAI 文档技能
│   ├── SKILL.md                          # 技能主文档（69行）
│   ├── agents/openai.yaml                # UI 元数据 + MCP 依赖声明
│   ├── references/
│   │   ├── latest-model.md               # 模型选择指南
│   │   ├── upgrading-to-gpt-5p4.md       # GPT-5.4 升级指南
│   │   └── gpt-5p4-prompting-guide.md    # 提示词优化指南
│   └── assets/                           # 图标资源
├── skill-creator/                        # 技能创建器
│   ├── SKILL.md                          # 技能创建指南（416行）
│   ├── agents/openai.yaml
│   ├── references/openai_yaml.md         # openai.yaml 格式规范
│   └── scripts/
│       ├── init_skill.py                 # 初始化技能模板
│       ├── generate_openai_yaml.py       # 生成 UI 元数据
│       └── quick_validate.py             # 验证技能结构
└── skill-installer/                      # 技能安装器
    ├── SKILL.md                          # 安装指南（58行）
    ├── agents/openai.yaml
    └── scripts/
        ├── github_utils.py               # GitHub API 工具
        ├── list-skills.py                # 列出可安装技能
        └── install-skill-from-github.py  # 从 GitHub 安装技能
```

### 核心调用链

```
Codex 启动
  └── SkillsManager::new()
      └── install_system_skills(codex_home)
          └── write_embedded_dir(SYSTEM_SKILLS_DIR, dest)
              └── 解压嵌入的样本到 ~/.codex/skills/.system/

Skill 加载
  └── SkillsManager::skills_for_cwd()
      └── load_skills_from_roots(roots)
          └── discover_skills_under_root()
              └── parse_skill_file(SKILL.md)
                  └── load_skill_metadata(agents/openai.yaml)
```

### 关键文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/skills/src/lib.rs` | 系统技能嵌入与安装逻辑 |
| `codex-rs/skills/build.rs` | 构建时监控样本目录变化 |
| `codex-rs/core/src/skills/manager.rs` | Skill 管理器，协调加载 |
| `codex-rs/core/src/skills/loader.rs` | Skill 扫描与解析逻辑 |
| `codex-rs/core/src/skills/model.rs` | Skill 元数据模型定义 |
| `codex-rs/core/src/skills/system.rs` | 系统技能安装接口 |

---

## 依赖与外部交互

### 内部依赖

```
codex-skills crate
├── include_dir          # 编译时目录嵌入
├── codex-utils-absolute-path  # 绝对路径处理
└── thiserror            # 错误处理

codex-core crate (skills 模块)
├── codex-skills         # 系统技能安装
├── codex-protocol       # SkillScope, Product 等协议类型
├── codex-app-server-protocol  # ConfigLayerSource
├── serde_yaml           # YAML 解析
└── toml                 # TOML 配置解析
```

### 外部交互

| 交互方 | 方式 | 用途 |
|--------|------|------|
| OpenAI Developer Docs MCP | HTTP Streamable | openai-docs 技能查询文档 |
| GitHub API | HTTP REST | skill-installer 列出/下载技能 |
| Git 命令行 | subprocess | skill-installer sparse checkout |
| 文件系统 | fs ops | 技能安装与加载 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 技能安装根目录（默认 `~/.codex`） |
| `GITHUB_TOKEN` / `GH_TOKEN` | 访问私有 GitHub 仓库 |

---

## 风险、边界与改进建议

### 当前风险

1. **样本膨胀风险**
   - 所有样本在编译时嵌入二进制，增加发布包体积
   - 当前样本包含 Python 脚本和文档，体积可控但需监控

2. **版本兼容风险**
   - 指纹标记使用简单哈希，可能因文件系统顺序产生不一致
   - 升级时完全替换 `.system` 目录，用户无法保留修改

3. **安全风险**
   - 系统技能以 `SkillScope::System` 加载，权限较高
   - skill-installer 执行外部脚本需要网络权限

4. **测试覆盖边界**
   - 样本内容变更不会触发 Rust 单元测试失败
   - Python 脚本缺乏自动化测试

### 边界限制

| 限制项 | 当前值 | 说明 |
|--------|--------|------|
| 最大扫描深度 | 6 层 | `MAX_SCAN_DEPTH` |
| 每根目录最大目录数 | 2000 | `MAX_SKILLS_DIRS_PER_ROOT` |
| Skill 名称最大长度 | 64 字符 | `MAX_NAME_LEN` |
| 描述最大长度 | 1024 字符 | `MAX_DESCRIPTION_LEN` |
| 短描述长度范围 | 25-64 字符 | UI 显示优化 |

### 改进建议

1. **样本模块化**
   - 将大文档（如 `gpt-5p4-prompting-guide.md`，433 行）拆分为更小的引用文件
   - 考虑按需加载远程文档，减少二进制体积

2. **版本管理增强**
   - 为每个样本添加版本号字段
   - 支持增量更新而非全量替换

3. **测试增强**
   - 添加 Python 脚本的单元测试
   - 添加样本结构验证的集成测试
   - 在 CI 中验证所有样本可通过 `quick_validate.py`

4. **安全加固**
   - 对 skill-installer 下载的脚本进行签名验证
   - 限制系统技能的权限范围

5. **文档改进**
   - 添加样本开发指南（如何修改系统技能）
   - 明确样本与运行时技能的同步机制

6. **国际化准备**
   - 当前样本均为英文，未来可考虑多语言支持
   - SKILL.md 结构应预留 i18n 扩展点

---

## 附录：关键数据流图

```
┌─────────────────────────────────────────────────────────────────┐
│                      编译时 (Build Time)                         │
│  ┌─────────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │ samples/ 目录   │───▶│ include_dir │───▶│ 二进制嵌入      │ │
│  │ (技能样本)      │    │ 宏处理      │    │ (SYSTEM_SKILLS) │ │
│  └─────────────────┘    └─────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      运行时 (Runtime)                            │
│  ┌─────────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │ 二进制中的样本  │───▶│ 指纹比对    │───▶│ ~/.codex/skills │ │
│  │ (SYSTEM_SKILLS) │    │ (marker)    │    │ /.system/       │ │
│  └─────────────────┘    └─────────────┘    └─────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │ SKILL.md 解析   │◀───│ SkillLoader │◀───│ 技能根目录扫描  │ │
│  │ (YAML+Markdown) │    │             │    │ (多作用域)      │ │
│  └─────────────────┘    └─────────────┘    └─────────────────┘ │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │ SkillMetadata   │───▶│ 技能注入    │───▶│ LLM 上下文      │ │
│  │ (内存结构)      │    │ (injection) │    │ (触发使用)      │ │
│  └─────────────────┘    └─────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/skills/src/assets/samples 目录及其调用链*
