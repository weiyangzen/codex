# NOTICE 文件研究文档

## 场景与职责

NOTICE 文件是 Apache 2.0 许可证项目中的标准法律声明文件，用于：
- 声明项目版权归属
- 记录第三方代码的引用和许可证信息
- 满足开源许可证的归属要求
- 保护项目免受版权侵权索赔

## 功能点目的

### 1. 版权声明
- **OpenAI Codex**: Copyright 2025 OpenAI
- 明确项目的原始版权归属

### 2. 第三方代码归属
| 来源项目 | 许可证 | 版权信息 | 用途 |
|---------|--------|---------|------|
| Ratatui | MIT | Florian Dehau (2016-2022), The Ratatui Developers (2023-2025) | TUI 渲染库 |
| Meriyah | ISC | KFlash and others (2019+) | JavaScript 解析器 |

### 3. 法律合规
- 确保符合 MIT 和 ISC 许可证的归属要求
- 提供透明度和可追溯性
- 降低法律风险

## 具体技术实现

### 文件结构
```
NOTICE
├── 项目版权声明 (OpenAI)
├── 第三方项目 1 (Ratatui)
│   ├── 项目链接
│   ├── 许可证类型
│   └── 版权持有者
└── 第三方项目 2 (Meriyah)
    ├── 项目链接
    ├── 许可证类型
    └── 版权持有者
```

### 关键内容

```text
OpenAI Codex
Copyright 2025 OpenAI

This project includes code derived from [Ratatui](...), licensed under MIT.
Copyright (c) 2016-2022 Florian Dehau
Copyright (c) 2023-2025 The Ratatui Developers

This project includes Meriyah parser assets from [meriyah](...), licensed under ISC.
Copyright (c) 2019 and later, KFlash and others.
```

## 关键代码路径与文件引用

### 相关文件
| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/NOTICE` | 本文件 |
| `/home/sansha/Github/codex/LICENSE` | Apache 2.0 主许可证 |
| `/home/sansha/Github/codex/codex-rs/tui/` | 使用 Ratatui 的 TUI 代码 |

### Ratatui 使用位置
```
codex-rs/tui/src/
├── lib.rs              # TUI 库入口
├── app.rs              # 应用主逻辑
├── chatwidget.rs       # 聊天组件
└── ...                 # 其他 UI 组件
```

Cargo.toml 依赖声明：
```toml
ratatui = { workspace = true, features = [
    "scrolling-regions",
    "unstable-backend-writer",
    "unstable-rendered-line-info",
    "unstable-widget-ref",
] }
```

## 依赖与外部交互

### 许可证兼容性
| 许可证 | 与 Apache 2.0 兼容性 | 要求 |
|--------|---------------------|------|
| MIT | ✅ 兼容 | 保留版权声明 |
| ISC | ✅ 兼容 | 保留版权声明 |

### 依赖关系图
```
Codex (Apache 2.0)
├── Ratatui (MIT) ──────┐
│   └── crossterm       │
│   └── unicode-width   │
│                       │
└── Meriyah (ISC) ──────┘
    └── (JavaScript parser assets)
```

## 风险、边界与改进建议

### 风险
1. **不完整归属**: 如果添加了新的第三方依赖但未更新 NOTICE 文件
2. **许可证变更**: 第三方项目许可证变更可能导致合规问题
3. **衍生作品认定**: 代码修改程度可能影响归属要求的解释

### 边界
- 仅声明直接包含的第三方代码
- 不声明传递依赖（依赖的依赖）
- 不声明 Cargo 自动管理的 crates.io 依赖

### 改进建议

#### 1. 自动化检查
```bash
# 建议添加 CI 检查脚本
#!/bin/bash
# 检查 Cargo.toml 中的依赖是否在 NOTICE 中有声明
cargo license --json | jq '.[] | select(.license != "Apache-2.0" and .license != "MIT" and .license != "ISC")'
```

#### 2. 扩展 NOTICE 内容
建议添加：
- 完整的依赖清单（可生成）
- 每个依赖的具体使用方式
- 修改记录（如果对第三方代码有修改）

#### 3. 维护流程
- 在添加新依赖时强制检查 NOTICE
- 定期审计依赖许可证变更
- 使用 `cargo-deny` 等工具进行许可证合规检查

#### 4. 文档改进
```markdown
## 建议的 NOTICE 扩展格式

### 直接依赖
| 包名 | 版本 | 许可证 | 用途 |
|------|------|--------|------|
| ratatui | 0.29.0 | MIT | TUI 渲染 |
| ... | ... | ... | ... |

### 资产/资源
| 资源 | 来源 | 许可证 |
|------|------|--------|
| Meriyah parser | meriyah | ISC |
```

### 相关工具
- `cargo-license`: 生成依赖许可证报告
- `cargo-deny`: 许可证合规检查
- `fossa-cli`: 全面的许可证扫描
