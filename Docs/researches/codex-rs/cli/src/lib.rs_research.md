# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-cli` crate 的库入口文件，定义了 CLI 子命令共享的数据结构和公共接口。它作为 CLI 二进制文件的库支持层，主要服务于：

1. **命令结构定义**: 定义沙箱相关命令的参数结构
2. **模块导出**: 导出登录和调试沙箱子模块
3. **配置集成**: 与 `codex_utils_cli` 的配置覆盖系统集成

## 功能点目的

### 1. 沙箱命令结构体
定义三种沙箱技术的命令行参数结构：

- `SeatbeltCommand`: macOS Seatbelt 沙箱命令
- `LandlockCommand`: Linux Landlock 沙箱命令  
- `WindowsCommand`: Windows 受限令牌沙箱命令

### 2. 模块导出
- `debug_sandbox`: 沙箱调试功能实现
- `login`: 登录相关功能
- `exit_status`: 退出状态处理（私有）

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Parser)]
pub struct SeatbeltCommand {
    /// 低摩擦沙箱自动执行别名（网络禁用，可写入 cwd 和 TMPDIR）
    #[arg(long = "full-auto", default_value_t = false)]
    pub full_auto: bool,

    /// 捕获 macOS 沙箱拒绝日志
    #[arg(long = "log-denials", default_value_t = false)]
    pub log_denials: bool,

    /// 配置覆盖（内部使用，不显示在帮助中）
    #[clap(skip)]
    pub config_overrides: CliConfigOverrides,

    /// 要在沙箱下运行的命令参数
    #[arg(trailing_var_arg = true)]
    pub command: Vec<String>,
}
```

三个命令结构体字段基本相同，区别仅在于：
- `SeatbeltCommand` 额外有 `log_denials` 字段（macOS 特有功能）
- 所有结构体都包含 `full_auto` 和 `config_overrides`

### 配置覆盖集成

```rust
use codex_utils_cli::CliConfigOverrides;

#[clap(skip)]
pub config_overrides: CliConfigOverrides,
```

`CliConfigOverrides` 允许通过 `-c key=value` 语法覆盖配置文件设置。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/cli/src/lib.rs` (52 行)

### 导出的模块
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs` - 沙箱调试实现
- `/home/sansha/Github/codex/codex-rs/cli/src/login.rs` - 登录功能
- `/home/sansha/Github/codex/codex-rs/cli/src/exit_status.rs` - 退出状态处理

### 依赖关系
```
lib.rs
    ├── pub mod debug_sandbox
    ├── mod exit_status (私有)
    └── pub mod login

main.rs
    ├── use codex_cli::LandlockCommand
    ├── use codex_cli::SeatbeltCommand
    ├── use codex_cli::WindowsCommand
    └── use codex_cli::login::*
```

## 依赖与外部交互

### 外部依赖
- `clap::Parser`: 派生宏用于命令行解析
- `codex_utils_cli::CliConfigOverrides`: 配置覆盖类型

### 内部模块交互
- `debug_sandbox`: 实现 `SeatbeltCommand`/`LandlockCommand`/`WindowsCommand` 的处理逻辑
- `login`: 提供登录相关公共函数

## 风险、边界与改进建议

### 风险点

1. **结构体重复**: 三个命令结构体高度相似，存在代码重复
2. **平台条件编译分散**: 平台相关逻辑分散在多个文件中
3. **扩展性**: 新增沙箱类型需要修改多个地方

### 边界情况

1. `trailing_var_arg = true` 允许捕获所有剩余参数作为命令
2. `#[clap(skip)]` 字段不会出现在帮助输出中
3. 空命令向量在运行时检查，不在类型系统层面约束

### 改进建议

1. **泛化抽象**: 使用泛型或 trait 统一三种命令结构体

```rust
// 建议改进
#[derive(Debug, Parser)]
pub struct SandboxCommand<S: SandboxType> {
    #[arg(long = "full-auto", default_value_t = false)]
    pub full_auto: bool,
    
    #[clap(skip)]
    pub config_overrides: CliConfigOverrides,
    
    #[arg(trailing_var_arg = true)]
    pub command: Vec<String>,
    
    #[clap(skip)]
    _phantom: std::marker::PhantomData<S>,
}

pub trait SandboxType {
    const NAME: &'static str;
}
```

2. **验证增强**: 在解析时验证命令非空

```rust
#[derive(Debug, Parser)]
pub struct SeatbeltCommand {
    // ...
    #[arg(trailing_var_arg = true, required = true)]
    pub command: Vec<String>,
}
```

3. **文档完善**: 为每个字段添加更详细的文档注释

4. **测试支持**: 添加构造辅助函数便于测试

```rust
impl SeatbeltCommand {
    pub fn new(command: Vec<String>) -> Self {
        Self {
            full_auto: false,
            log_denials: false,
            config_overrides: CliConfigOverrides::default(),
            command,
        }
    }
}
```

### 架构考虑

当前设计保持简单，将平台差异推迟到 `debug_sandbox.rs` 处理。这种设计：
- **优点**: 简单直观，易于理解
- **缺点**: 类型系统无法保证平台兼容性（如在 Linux 上构造 SeatbeltCommand）

替代方案是使用条件编译：
```rust
#[cfg(target_os = "macos")]
pub struct SeatbeltCommand { ... }
```

但这会增加 `main.rs` 中的条件编译复杂度。
