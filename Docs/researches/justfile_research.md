# justfile 文件研究文档

## 场景与职责

justfile 是 [Just](https://github.com/casey/just) 命令运行器的配置文件，为 OpenAI Codex 项目提供：
- **开发工作流自动化**: 封装常用开发命令（构建、测试、格式化）
- **跨平台一致性**: 统一的命令接口，隐藏平台差异
- **任务依赖管理**: 定义任务间的依赖关系
- **文档化**: 命令即文档，降低新开发者上手成本

## 功能点目的

### 1. 命令分类
| 类别 | 命令 | 用途 |
|------|------|------|
| **开发** | `codex`, `exec`, `file-search` | 运行应用 |
| **代码质量** | `fmt`, `fix`, `clippy` | 代码格式和检查 |
| **测试** | `test` | 运行测试套件 |
| **Bazel** | `bazel-codex`, `bazel-test`, `bazel-lock-update` | Bazel 构建 |
| **协议** | `write-config-schema`, `write-app-server-schema` | 生成协议文件 |
| **工具** | `mcp-server-run`, `argument-comment-lint` | 运行工具 |

### 2. 工作目录设置
```just
set working-directory := "codex-rs"
```
- 所有命令默认在 `codex-rs/` 目录执行
- 与项目结构一致（Rust 代码在子目录）

### 3. 位置参数支持
```just
set positional-arguments
```
- 允许将参数传递给底层命令

## 具体技术实现

### 核心命令详解

#### 1. 应用运行
```just
# 默认运行 codex TUI
alias c := codex
codex *args:
    cargo run --bin codex -- "$@"

# 执行模式
exec *args:
    cargo run --bin codex -- exec "$@"

# 文件搜索
file-search *args:
    cargo run --bin codex-file-search -- "$@"
```

**使用示例**:
```bash
just codex "解释这个代码库"
just exec "运行测试"
just file-search "query"
```

#### 2. 代码格式化
```just
fmt:
    cargo fmt -- --config imports_granularity=Item 2>/dev/null
```
- `imports_granularity=Item`: 每个导入项单独一行
- `2>/dev/null`: 抑制错误输出

#### 3. 代码修复
```just
fix *args:
    cargo clippy --fix --tests --allow-dirty "$@"
```
- `--allow-dirty`: 允许在脏工作区运行
- 自动修复 Clippy 警告

#### 4. 测试
```just
test:
    cargo nextest run --no-fail-fast
```
- 使用 `cargo-nextest` 替代默认测试运行器
- `--no-fail-fast`: 即使测试失败也继续运行所有测试

**为什么选择 nextest**:
- 更快的测试执行
- 更好的输出格式
- 更可靠的并行测试

#### 5. Bazel 集成
```just
[no-cd]
bazel-codex *args:
    bazel run //codex-rs/cli:codex --run_under="cd $PWD &&" -- "$@"
```

**关键设计**:
- `[no-cd]`: 不切换工作目录（保持在项目根）
- `--run_under="cd $PWD &&"`: 确保 Bazel 在当前目录运行

```just
[no-cd]
bazel-lock-update:
    bazel mod deps --lockfile_mode=update

[no-cd]
bazel-lock-check:
    ./scripts/check-module-bazel-lock.sh
```

#### 6. 协议生成
```just
write-config-schema:
    cargo run -p codex-core --bin codex-write-config-schema

write-app-server-schema *args:
    cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- "$@"
```

**用途**:
- `write-config-schema`: 生成 `config.schema.json`
- `write-app-server-schema`: 生成 app-server 协议文件

#### 7. 日志查看
```just
log *args:
    if [ "${1:-}" = "--" ]; then shift; fi; cargo run -p codex-state --bin logs_client -- "$@"
```

**使用示例**:
```bash
just log                    # 查看所有日志
just log -- --tail 100      # 查看最后 100 条
```

### 高级特性

#### 条件参数处理
```just
log *args:
    if [ "${1:-}" = "--" ]; then shift; fi; ...
```
- 处理 `--` 参数分隔符
- 允许灵活的参数传递

## 关键代码路径与文件引用

### 相关文件
| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/justfile` | 本文件 |
| `/home/sansha/Github/codex/codex-rs/Cargo.toml` | Rust 工作区配置 |
| `/home/sansha/Github/codex/scripts/check-module-bazel-lock.sh` | Bazel 锁定检查脚本 |
| `/home/sansha/Github/codex/MODULE.bazel` | Bazel 模块配置 |

### 工具依赖
| 工具 | 用途 | 安装方式 |
|------|------|---------|
| just | 命令运行器 | `cargo install just` |
| cargo-nextest | 测试运行器 | `cargo install cargo-nextest` |
| cargo | Rust 构建 | rustup |
| bazel | 替代构建系统 | bazelisk |

### CI/CD 集成
```yaml
# .github/workflows/rust-ci.yml
- name: Format
  run: just fmt
  
- name: Clippy
  run: just clippy
  
- name: Test
  run: just test
```

## 依赖与外部交互

### 工具链关系
```
justfile
├── Cargo/Rust ──────────────────┐
│   ├── cargo build              │
│   ├── cargo test               │
│   ├── cargo fmt                ├── 主要开发工具
│   └── cargo clippy             │
├── Bazel ───────────────────────┤
│   ├── bazel build              │
│   ├── bazel test               ├── 替代构建系统
│   └── bazel run                │
└── 外部工具 ────────────────────┘
    ├── cargo-nextest
    └── argument-comment-lint
```

### 与 AGENTS.md 的关系
AGENTS.md 中明确要求：
```markdown
- Run `just fmt` (in `codex-rs` directory) automatically after you have finished making Rust code changes
- Run `just fix -p <project>` to fix any linter issues
```

### 与 package.json 的关系
| 文件 | 用途 | 范围 |
|------|------|------|
| `justfile` | Rust/Codex 开发 | 主要开发工作流 |
| `package.json` | Node.js/格式化 | 仓库维护任务 |

## 风险、边界与改进建议

### 风险

#### 1. 工具缺失
```
风险: 新开发者未安装 just 或 cargo-nextest
影响: 命令无法运行
缓解: 在 docs/install.md 中明确列出依赖
```

#### 2. 路径假设
```
风险: 工作目录设置为 codex-rs，但某些命令需要根目录
影响: Bazel 命令使用 [no-cd] 解决，但其他命令可能有问题
缓解: 明确标记需要根目录的命令
```

#### 3. 参数传递复杂性
```
风险: 复杂的 shell 参数处理容易出错
示例: log 命令中的 if [ "${1:-}" = "--" ]
缓解: 考虑使用更简单的参数模式
```

### 边界

#### 功能边界
- 不管理 Node.js 依赖（由 package.json/pnpm 处理）
- 不管理 Python 工具（如有）
- 不替代 shell 脚本用于复杂逻辑

#### 平台边界
- 主要面向 Unix-like 系统
- Windows 支持依赖 Git Bash 或 WSL

### 改进建议

#### 1. 添加工具检查
```just
# 检查必需工具
_check-tools:
    #!/usr/bin/env bash
    command -v cargo >/dev/null 2>&1 || { echo "cargo not found"; exit 1; }
    command -v just >/dev/null 2>&1 || { echo "just not found"; exit 1; }

# 在关键命令前检查
fmt: _check-tools
    cargo fmt -- --config imports_granularity=Item
```

#### 2. 添加帮助信息
```just
# 默认显示帮助
default:
    @just --list

# 详细的命令说明
help:
    @echo "Codex Development Commands"
    @echo ""
    @echo "Development:"
    @echo "  just codex [args]     - Run codex TUI"
    @echo "  just exec [args]      - Run codex exec"
    @echo ""
    @echo "Code Quality:"
    @echo "  just fmt              - Format code"
    @echo "  just fix [args]       - Fix lint issues"
    @echo "  just test             - Run tests"
```

#### 3. 添加环境设置
```just
# 安装开发依赖
install-dev:
    rustup component add rustfmt clippy
    cargo install just cargo-nextest

# 验证环境
doctor:
    #!/usr/bin/env bash
    echo "Checking development environment..."
    echo "Rust: $(rustc --version)"
    echo "Cargo: $(cargo --version)"
    echo "Just: $(just --version)"
    cargo nextest --version 2>/dev/null || echo "cargo-nextest: not installed"
```

#### 4. 改进测试命令
```just
# 支持不同测试模式
test *args:
    cargo nextest run --no-fail-fast "$@"

test-unit *args:
    cargo nextest run --lib "$@"

test-integration *args:
    cargo nextest run --tests "$@"

test-e2e *args:
    cargo test --test '*' "$@"
```

#### 5. 添加文档生成
```just
# 生成并打开文档
docs:
    cargo doc --no-deps --open

# 生成配置文档
docs-config: write-config-schema
    @echo "Config schema updated at codex-rs/core/config.schema.json"
```

#### 6. 添加发布辅助
```just
# 发布前检查
pre-release:
    just fmt
    just fix
    just test
    just clippy
    @echo "Pre-release checks passed!"

# 版本 bump（示例）
bump-version version:
    # 更新 Cargo.toml 版本
    # 更新 CHANGELOG
    # 创建 git 标签
```

#### 7. 改进 Bazel 命令
```just
[no-cd]
bazel-build *args:
    bazel build //... "$@"

[no-cd]
bazel-clean:
    bazel clean --expunge

[no-cd]
bazel-query pattern:
    bazel query "{{pattern}}"
```

#### 8. 添加清理命令
```just
# 清理构建产物
clean:
    cargo clean
    rm -rf target/
    @echo "Cleaned build artifacts"

# 深度清理（包括缓存）
clean-all: clean
    rm -rf ~/.cargo/registry/cache
    rm -rf ~/.cache/bazel-*
    @echo "Cleaned all caches"
```

### 维护建议

#### 命令命名规范
| 类型 | 命名 | 示例 |
|------|------|------|
| 动词 | 动作 | `fmt`, `test`, `build` |
| 名词 | 对象 | `docs`, `logs` |
| 复合 | 动作-对象 | `write-config-schema` |

#### 文档同步
- 更新 justfile 时同步更新 docs/install.md
- 在 AGENTS.md 中引用 just 命令
- 考虑生成 justfile 文档（`just --list`）

#### CI 一致性
确保 CI 使用的命令与 justfile 一致：
```yaml
# 推荐：CI 使用 just
- run: just fmt --check
- run: just test

# 不推荐：CI 直接使用 cargo
- run: cargo fmt --check
```
