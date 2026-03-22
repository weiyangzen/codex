# codex-rs/deny.toml 深度研究文档

## 场景与职责

`codex-rs/deny.toml` 是 `cargo-deny` 工具的配置文件，用于审计 Rust 项目的依赖安全性、许可证合规性和依赖 bans。这是企业级 Rust 项目的标准安全实践，确保供应链安全和法律合规。

### 核心职责

1. **安全审计**: 检查已知漏洞（通过 RustSec Advisory Database）
2. **许可证合规**: 验证所有依赖的许可证是否在允许列表中
3. **依赖管控**: 禁止或警告特定 crate 的使用
4. **来源控制**: 限制依赖的来源（crates.io、GitHub 等）

---

## 功能点目的

### 1. 依赖图配置 (lines 12-51)

```toml
[graph]
targets = []
all-features = false
no-default-features = false
```

**配置说明**:

| 选项 | 值 | 用途 |
|------|-----|------|
| `targets` | `[]` | 不限制目标平台，检查所有 |
| `all-features` | `false` | 默认不启用所有特性 |
| `no-default-features` | `false` | 默认启用默认特性 |

**技术细节**:
- `targets` 可用于交叉编译场景，只检查目标平台的依赖
- 特性控制影响依赖图的大小和检查结果

### 2. 输出配置 (lines 53-60)

```toml
[output]
feature-depth = 1
```

- 控制诊断输出中包含的特性深度
- 深度为 1 表示只显示直接依赖的特性

### 3. 安全告警 (lines 62-86)

```toml
[advisories]
ignore = [
    { id = "RUSTSEC-2024-0388", reason = "derivative is unmaintained; pulled in via starlark v0.13.0..." },
    { id = "RUSTSEC-2025-0057", reason = "fxhash is unmaintained; pulled in via starlark_map/starlark..." },
    { id = "RUSTSEC-2024-0436", reason = "paste is unmaintained; pulled in via ratatui/rmcp/starlark..." },
    { id = "RUSTSEC-2026-0002", reason = "lru 0.12.5 is pulled in via ratatui fork..." },
    { id = "RUSTSEC-2024-0320", reason = "yaml-rust is unmaintained; pulled in via syntect..." },
    { id = "RUSTSEC-2025-0141", reason = "bincode is unmaintained; pulled in via syntect..." },
]
```

**安全例外分析**:

| RUSTSEC ID | 问题 | 依赖路径 | 状态 |
|------------|------|----------|------|
| 2024-0388 | derivative 未维护 | starlark v0.13.0 | 无修复版本 |
| 2025-0057 | fxhash 未维护 | starlark_map/starlark | 无修复版本 |
| 2024-0436 | paste 未维护 | ratatui/rmcp/starlark | 无修复版本 |
| 2026-0002 | lru 0.12.5 | ratatui fork | 待 fork 更新 |
| 2024-0320 | yaml-rust 未维护 | syntect v5.3.0 | 无修复版本 |
| 2025-0141 | bincode 未维护 | syntect v5.3.0 | 无修复版本 |

**风险管理**:
- 所有例外都有详细原因说明
- 大多数是 "unmaintained"（未维护）而非 "vulnerable"（有漏洞）
- 明确标注了修复计划（TODO 注释）

### 4. 许可证配置 (lines 88-181)

#### 允许列表 (lines 95-138)

```toml
allow = [
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "BSL-1.0",
    "CC0-1.0",
    "CDLA-Permissive-2.0",
    "ISC",
    "MIT",
    "MIT-0",
    "MPL-2.0",
    "OpenSSL",
    "Unicode-3.0",
    "Unlicense",
    "Zlib",
]
```

**许可证分类**:

| 类型 | 许可证 | 商业使用 |
|------|--------|----------|
| Permissive | Apache-2.0, MIT, BSD, ISC | ✅ 允许 |
| Permissive | MIT-0, CC0-1.0, Unlicense, Zlib | ✅ 允许 |
| Weak Copyleft | MPL-2.0 | ✅ 允许（文件级） |
| Special | OpenSSL, Unicode-3.0 | ✅ 允许 |

**注释中的依赖映射**:
- 每个许可证后列出了使用该许可证的主要 crate
- 便于审计和追溯

#### 置信度阈值 (lines 139-143)

```toml
confidence-threshold = 0.8
```

- 许可证文本匹配置信度阈值
- 0.8 表示需要 80% 匹配度才认为识别正确
- 低于阈值需要人工审核

### 5. 依赖 Bans (lines 183-254)

```toml
[bans]
multiple-versions = "warn"
wildcards = "allow"
workspace-default-features = "allow"
external-default-features = "allow"
```

**策略说明**:

| 选项 | 值 | 说明 |
|------|-----|------|
| `multiple-versions` | `"warn"` | 同一 crate 多版本时警告 |
| `wildcards` | `"allow"` | 允许 `*` 版本约束 |
| `workspace-default-features` | `"allow"` | 允许工作区成员使用默认特性 |
| `external-default-features` | `"allow"` | 允许外部 crate 使用默认特性 |

**设计决策**:
- `multiple-versions = "warn"`: 提醒但不阻止，因为有时不可避免
- `wildcards = "allow"`: 允许通配符，但需谨慎使用

### 6. 来源控制 (lines 256-280)

```toml
[sources]
unknown-registry = "warn"
unknown-git = "warn"
allow-registry = ["https://github.com/rust-lang/crates.io-index"]
allow-git = []

[sources.allow-org]
github = ["nornagon"]
gitlab = []
bitbucket = []
```

**来源策略**:

| 来源 | 策略 | 说明 |
|------|------|------|
| crates.io | ✅ 允许 | 主 registry |
| 未知 registry | ⚠️ 警告 | 需要审核 |
| 未知 Git | ⚠️ 警告 | 需要审核 |
| GitHub org | ✅ 允许 | `nornagon` |

**允许的 GitHub 组织**:
- `nornagon`: ratatui 和 crossterm 的 fork 维护者

---

## 具体技术实现

### cargo-deny 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│                    cargo-deny 检查流程                       │
├─────────────────────────────────────────────────────────────┤
│  1. 读取 Cargo.lock                                         │
│  2. 下载/更新 advisory-db                                   │
│  3. 检查每个依赖:                                           │
│     a. 安全漏洞 (advisories)                                │
│     b. 许可证合规 (licenses)                                │
│     c. 依赖 bans (bans)                                     │
│     d. 来源检查 (sources)                                   │
│  4. 生成报告                                                │
└─────────────────────────────────────────────────────────────┘
```

### 检查命令

```bash
# 运行所有检查
cargo deny check

# 单独检查
cargo deny check advisories
cargo deny check licenses
cargo deny check bans
cargo deny check sources

# 生成依赖图
cargo deny list
```

### CI 集成

```yaml
# 典型 CI 配置
- name: Check dependencies
  run: |
    cargo install cargo-deny
    cargo deny check
```

---

## 关键代码路径与文件引用

### 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `Cargo.lock` | 输入 | 依赖版本锁定 |
| `Cargo.toml` | 输入 | 依赖声明 |
| `LICENSE` | 参考 | 项目许可证 |
| `.github/workflows/` | 使用者 | CI 可能运行 cargo-deny |

### 外部数据库

| 数据库 | 用途 | 更新频率 |
|--------|------|----------|
| RustSec Advisory DB | 安全漏洞 | 实时 |
| SPDX License List | 许可证识别 | 定期 |
| crates.io index | 依赖信息 | 实时 |

---

## 依赖与外部交互

### 工具链依赖

| 工具 | 用途 |
|------|------|
| cargo-deny | 依赖审计 |
| cargo | 包管理 |
| git | 获取 advisory-db |

### 网络依赖

| 资源 | 用途 |
|------|------|
| https://github.com/rustsec/advisory-db | 安全数据库 |
| https://github.com/rust-lang/crates.io-index | crate 索引 |

### 与 Cargo.toml 的协作

```toml
# Cargo.toml 声明依赖
[dependencies]
serde = "1"

# deny.toml 审计依赖
[licenses]
allow = ["MIT", "Apache-2.0"]  # serde 使用 MIT/Apache-2.0
```

---

## 风险、边界与改进建议

### 当前风险

1. **安全例外累积**
   - 6 个 RUSTSEC 例外，数量较多
   - 部分依赖（starlark、syntect）更新缓慢
   - 需要定期重新评估

2. **许可证识别风险**
   - `confidence-threshold = 0.8` 可能漏检边缘情况
   - 某些 crate 的许可证声明不清晰

3. **Git 依赖风险**
   - `allow-git = []` 理论上禁止所有 Git 依赖
   - 但实际通过 `[patch.crates-io]` 引入 Git 依赖
   - 需要确保 `sources` 检查正确处理补丁

4. **维护负担**
   - 每次添加新依赖需检查许可证
   - 安全数据库更新可能引入新告警

### 边界条件

1. **开发依赖**
   - `cargo-deny` 默认检查所有依赖
   - `[dev-dependencies]` 也受相同规则约束

2. **特性组合**
   - 不同特性可能引入不同依赖
   - `all-features = false` 可能遗漏某些依赖

3. **平台特定依赖**
   - `[target.'cfg(unix)'.dependencies]` 等条件依赖
   - 需要确保所有目标平台都合规

### 改进建议

1. **安全例外清理计划**
   ```toml
   # 建议: 为每个 TODO 添加跟踪 issue
   # TODO(joshka, nornagon): https://github.com/openai/codex/issues/XXX
   ```

2. **自动化检查**
   ```toml
   # 建议: 添加 CI 检查确保 deny.toml 是最新的
   # 当 Cargo.lock 变更时，自动运行 cargo deny check
   ```

3. **许可证文档化**
   ```toml
   # 建议: 添加注释说明为何选择这些许可证
   # Apache-2.0: 主许可证，与项目许可证一致
   # MIT: 广泛兼容，允许商业使用
   # ...
   ```

4. **依赖降级策略**
   ```toml
   # 建议: 考虑将某些 warn 改为 deny
   # 例如: multiple-versions = "deny"（在清理后）
   ```

5. **定期审计**
   ```bash
   # 建议: 添加定期审计脚本
   #!/bin/bash
   cargo deny check 2>&1 | tee deny-report.txt
   # 如果报告变化，创建 issue
   ```

6. **Git 依赖明确化**
   ```toml
   # 建议: 如果允许特定 Git 依赖，明确列出
   allow-git = [
       "https://github.com/nornagon/crossterm",
       "https://github.com/nornagon/ratatui",
       # ...
   ]
   ```

---

## 附录: 许可证参考

### 允许许可证详情

| 许可证 | SPDX ID | OSI 批准 | FSF 自由 |
|--------|---------|----------|----------|
| Apache License 2.0 | Apache-2.0 | ✅ | ✅ |
| BSD 2-Clause | BSD-2-Clause | ✅ | ✅ |
| BSD 3-Clause | BSD-3-Clause | ✅ | ✅ |
| Boost Software License 1.0 | BSL-1.0 | ✅ | ✅ |
| CC0 1.0 Universal | CC0-1.0 | ❌ | ✅ |
| CDLA Permissive 2.0 | CDLA-Permissive-2.0 | ❌ | ✅ |
| ISC License | ISC | ✅ | ✅ |
| MIT License | MIT | ✅ | ✅ |
| MIT No Attribution | MIT-0 | ✅ | ✅ |
| Mozilla Public License 2.0 | MPL-2.0 | ✅ | ✅ |
| OpenSSL License | OpenSSL | ❌ | ✅ |
| Unicode License Agreement | Unicode-3.0 | ✅ | ✅ |
| The Unlicense | Unlicense | ❌ | ✅ |
| zlib License | Zlib | ✅ | ✅ |

### 常见不兼容许可证（未在允许列表）

- GPL-2.0/3.0（强 Copyleft）
- LGPL（弱 Copyleft，需谨慎）
- AGPL（网络 Copyleft）
- 专有许可证（Proprietary）
