# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 `codex-rs/tui_app_server/tests/suite/` 目录的模块聚合文件，负责将分散的集成测试模块组织为统一的测试套件。该文件位于测试目录的入口点，遵循 Rust 的模块系统约定（目录下的 `mod.rs` 或 `suite.rs` 作为模块根）。

该文件属于 `tui_app_server` crate 的集成测试基础设施，与 `tests/all.rs` 配合使用，后者通过 `mod suite;` 引入整个测试套件。

## 功能点目的

### 模块聚合

将以下 5 个独立的集成测试模块聚合为统一的测试套件：

1. **`model_availability_nux`** - 测试模型可用性 NUX（New User Experience）提示的计数逻辑，确保在 resume 会话时不会重复消耗计数
2. **`no_panic_on_startup`** - 回归测试，验证当 rules 配置异常时（如 rules 应为目录但实际为文件），应用不会 panic 而是优雅地报告错误
3. **`status_indicator`** - 测试状态指示器组件的 ANSI 转义序列处理，确保不会将原始转义字节写入后备缓冲区
4. **`vt100_history`** - VT100 终端模拟测试，验证历史记录插入、文本换行、emoji/CJK 字符处理、ANSI 样式保留等功能
5. **`vt100_live_commit`** - 测试实时输出流的行提交逻辑，验证当缓冲区溢出时的正确提交行为

## 具体技术实现

### 模块声明

```rust
// Aggregates all former standalone integration tests as modules.
mod model_availability_nux;
mod no_panic_on_startup;
mod status_indicator;
mod vt100_history;
mod vt100_live_commit;
```

采用简单的 `mod` 声明方式，每个子模块对应 `suite/` 目录下的同名 `.rs` 文件。

### 条件编译

部分测试模块使用条件编译特性：

- `vt100_history` 和 `vt100_live_commit` 使用 `#![cfg(feature = "vt100-tests")]` 特性门控，允许在不需要 VT100 模拟的测试场景中跳过

## 关键代码路径与文件引用

### 文件位置

```
codex-rs/tui_app_server/tests/
├── all.rs                    # 测试入口，引入 suite 模块
├── test_backend.rs           # VT100Backend 测试后端
├── manager_dependency_regression.rs  # 其他回归测试
└── suite/
    ├── mod.rs               # 本文件（模块聚合）
    ├── model_availability_nux.rs
    ├── no_panic_on_startup.rs
    ├── status_indicator.rs
    ├── vt100_history.rs
    └── vt100_live_commit.rs
```

### 依赖关系

```
all.rs
  └── suite (mod.rs)
       ├── model_availability_nux
       │   └── 依赖: codex_utils_pty, codex_utils_cargo_bin
       ├── no_panic_on_startup
       │   └── 依赖: codex_utils_pty, codex_utils_cargo_bin
       ├── status_indicator
       │   └── 依赖: codex_ansi_escape
       ├── vt100_history
       │   └── 依赖: VT100Backend, insert_history, custom_terminal
       └── vt100_live_commit
           └── 依赖: VT100Backend, live_wrap, insert_history
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_utils_pty` | PTY 进程生成和管理（用于集成测试） |
| `codex_utils_cargo_bin` | 定位编译后的二进制文件和资源 |
| `codex_ansi_escape` | ANSI 转义序列处理 |
| `vt100` | VT100 终端模拟（通过 `test_backend`） |

### 内部模块依赖

- `VT100Backend` (`test_backend.rs`) - 模拟 VT100 终端行为的测试后端
- `insert_history` (`src/insert_history.rs`) - 历史记录插入逻辑
- `live_wrap` (`src/live_wrap.rs`) - 实时文本换行
- `custom_terminal` (`src/custom_terminal.rs`) - 自定义终端实现

## 风险、边界与改进建议

### 当前风险

1. **平台限制**: `model_availability_nux` 和 `no_panic_on_startup` 测试在 Windows 上被跳过（PTY 限制），这可能导致平台相关 bug 未被捕获

2. **测试隔离性**: 集成测试依赖外部二进制文件（`codex` 可执行文件），如果二进制未编译或路径不正确，测试会被静默跳过

3. **特性门控复杂性**: `vt100-tests` 特性需要显式启用，CI 配置需要确保该特性在适当阶段被测试

### 边界情况

1. **模块加载顺序**: Rust 的模块加载是并行的，测试之间没有显式的执行顺序保证
2. **资源竞争**: 多个测试可能同时尝试生成 PTY 进程，需要确保系统资源充足

### 改进建议

1. **增加模块文档**: 为每个子模块添加简短的 doc 注释，说明测试目的
   ```rust
   /// Tests for model availability NUX counter behavior.
   mod model_availability_nux;
   ```

2. **统一平台处理**: 考虑将 Windows 跳过逻辑提取到共享的测试工具宏中，减少重复代码

3. **测试分类**: 考虑使用 Rust 的 `#[ignore]` 属性对慢速/不稳定测试进行分类，而不是仅依赖特性门控

4. **依赖注入**: 考虑为测试提供 mock 的 app server 客户端，减少对真实二进制文件的依赖

5. **增加覆盖率监控**: VT100 相关的测试仅覆盖特定场景，建议增加更多边界情况测试（如极端宽度、特殊 Unicode 组合字符等）
