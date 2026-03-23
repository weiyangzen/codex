# lib.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`lib.rs` 是 `codex-linux-sandbox` crate 的**库入口点**，负责模块组织和平台适配。它是整个 Linux 沙箱功能的根模块，提供统一的对外接口。

### 1.2 核心职责
- **模块组织**：声明并条件编译所有子模块
- **平台适配**：区分 Linux 和非 Linux 平台的编译
- **接口导出**：暴露 `run_main` 函数作为统一入口

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                 codex-linux-sandbox crate                    │
├─────────────────────────────────────────────────────────────┤
│  lib.rs  ★ 当前文件                                          │
│  ├── 模块声明与条件编译                                       │
│  └── run_main() 接口导出                                      │
├─────────────────────────────────────────────────────────────┤
│  main.rs                                                    │
│  └── 二进制入口，调用 lib::run_main()                         │
├─────────────────────────────────────────────────────────────┤
│  子模块（Linux 专用）                                         │
│  ├── bwrap.rs       - bubblewrap 参数生成                     │
│  ├── landlock.rs    - seccomp/landlock 进程限制               │
│  ├── launcher.rs    - bwrap 执行启动器                        │
│  ├── linux_run_main.rs - 主逻辑实现                          │
│  ├── proxy_routing.rs  - 代理路由管理                         │
│  └── vendored_bwrap.rs - 内嵌 bwrap FFI                      │
└─────────────────────────────────────────────────────────────┘
```

## 2. 功能点目的

### 2.1 条件编译策略

模块使用 `#[cfg(target_os = "linux")]` 属性实现平台条件编译：

| 条件 | 内容 | 目的 |
|------|------|------|
| `#[cfg(target_os = "linux")]` | 所有子模块声明 | 仅在 Linux 平台编译沙箱代码 |
| `#[cfg(not(target_os = "linux"))]` | panic 实现 | 非 Linux 平台提供清晰错误 |

### 2.2 模块声明

```rust
#[cfg(target_os = "linux")]
mod bwrap;
#[cfg(target_os = "linux")]
mod landlock;
#[cfg(target_os = "linux")]
mod launcher;
#[cfg(target_os = "linux")]
mod linux_run_main;
#[cfg(target_os = "linux")]
mod proxy_routing;
#[cfg(target_os = "linux")]
mod vendored_bwrap;
```

每个子模块都有详细的文档注释说明其职责。

### 2.3 统一入口函数

```rust
#[cfg(target_os = "linux")]
pub fn run_main() -> ! {
    linux_run_main::run_main();
}

#[cfg(not(target_os = "linux"))]
pub fn run_main() -> ! {
    panic!("codex-linux-sandbox is only supported on Linux");
}
```

**设计特点**：
- 发散返回类型 `!`：函数不会正常返回（要么 exec，要么 panic）
- 平台透明：调用方无需关心平台差异
- 清晰错误：非 Linux 平台给出明确错误信息

## 3. 具体技术实现

### 3.1 文档注释

文件顶部的模块文档说明了 Linux 沙箱的整体架构：

```rust
//! Linux sandbox helper entry point.
//!
//! On Linux, `codex-linux-sandbox` applies:
//! - in-process restrictions (`no_new_privs` + seccomp), and
//! - bubblewrap for filesystem isolation.
```

这对应于：
- `landlock.rs`：in-process restrictions
- `bwrap.rs` + `launcher.rs`：bubblewrap for filesystem isolation

### 3.2 条件编译实现

Rust 的条件编译通过 `cfg` 属性实现：

```rust
// Linux 平台：编译所有子模块
#[cfg(target_os = "linux")]
mod bwrap;
// ... 其他模块

// 非 Linux 平台：仅提供 panic 实现
#[cfg(not(target_os = "linux"))]
pub fn run_main() -> ! {
    panic!("...");
}
```

### 3.3 模块可见性

所有子模块使用默认可见性（私有），通过 `pub fn run_main()` 暴露唯一公共接口。这实现了良好的封装：

```
外部调用者
    │
    ▼
run_main() [pub]
    │
    ▼
linux_run_main::run_main() [private]
    │
    ├── bwrap::... [private]
    ├── landlock::... [private]
    ├── launcher::... [private]
    └── ...
```

## 4. 关键代码路径与文件引用

### 4.1 调用关系

```
外部调用者（如 codex-core）
    │
    ▼
lib.rs::run_main()
    ├── Linux: linux_run_main::run_main()
    └── 非 Linux: panic!

main.rs（二进制入口）
    │
    ▼
lib.rs::run_main()
```

### 4.2 文件引用

| 文件 | 关系 | 说明 |
|------|------|------|
| `main.rs` | 调用者 | 二进制入口，调用 `run_main()` |
| `linux_run_main.rs` | 被调用者 | Linux 平台实际实现 |
| `bwrap.rs` | 子模块 | 被 `linux_run_main` 使用 |
| `landlock.rs` | 子模块 | 被 `linux_run_main` 使用 |
| `launcher.rs` | 子模块 | 被 `linux_run_main` 使用 |
| `proxy_routing.rs` | 子模块 | 被 `linux_run_main` 使用 |
| `vendored_bwrap.rs` | 子模块 | 被 `launcher` 使用 |

## 5. 依赖与外部交互

### 5.1 内部依赖

模块之间形成层次依赖：

```
lib.rs
└── linux_run_main.rs
    ├── bwrap.rs
    ├── landlock.rs
    ├── launcher.rs
    │   └── vendored_bwrap.rs
    └── proxy_routing.rs
```

### 5.2 外部依赖

此文件本身不直接引入外部 crate 依赖，所有依赖在子模块中声明。

### 5.3 平台依赖

| 平台 | 行为 |
|------|------|
| Linux | 编译完整沙箱功能 |
| macOS | 编译失败（panic） |
| Windows | 编译失败（panic） |
| 其他 Unix | 编译失败（panic） |

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 编译时平台检测
- **风险**：`target_os` 是编译时检测，不支持运行时检测
- **影响**：交叉编译时可能产生意外结果
- **缓解**：这是 Rust 的标准行为，通常符合预期

#### 6.1.2 非 Linux 平台的用户体验
- **风险**：非 Linux 平台编译成功但运行时 panic
- **影响**：用户体验不佳（编译时未发现错误）
- **评估**：这是设计选择，允许代码在条件编译下编译

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| Linux 平台 | 正常编译所有模块 |
| 非 Linux 平台 | 编译通过，运行时 panic |
| 模块缺失 | 编译错误 |

### 6.3 改进建议

#### 6.3.1 编译时错误而非运行时 panic
- **建议**：使用 `compile_error!` 在非 Linux 平台产生编译错误
- **实现**：
```rust
#[cfg(not(target_os = "linux"))]
compile_error!("codex-linux-sandbox is only supported on Linux");
```
- **权衡**：这会阻止在非 Linux 平台上的任何编译，可能影响交叉编译场景

#### 6.3.2 添加模块文档
- **建议**：为每个子模块添加更详细的文档注释
- **当前**：仅有顶层模块文档
- **价值**：帮助开发者理解模块关系

#### 6.3.3 导出类型
- **建议**：考虑导出关键类型（如 `SandboxPolicy` 相关）
- **当前**：仅导出 `run_main` 函数
- **评估**：可能需要根据外部使用需求调整

#### 6.3.4 版本信息
- **建议**：添加版本信息常量
- **实现**：
```rust
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
```
- **价值**：便于调试和兼容性检查

### 6.4 维护注意事项

1. **模块添加**：新增子模块时需要添加条件编译属性
2. **平台扩展**：如需支持其他平台（如 BSD），需要调整条件编译
3. **接口稳定性**：`run_main()` 是公共 API，修改需谨慎
4. **文档同步**：确保模块文档与实际功能保持一致

### 6.5 代码简洁性

此文件保持极简设计（仅 27 行），这是良好的实践：
- 单一职责：仅负责模块组织和接口导出
- 易于理解：新开发者可以快速把握整体结构
- 维护简单：变更通常只涉及添加/删除模块声明
