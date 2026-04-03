# ReadOnlyAccess.ts 研究文档

## 场景与职责

`ReadOnlyAccess.ts` 定义了沙箱只读访问权限的数据结构，用于配置 Codex 在执行命令时对文件系统的只读访问策略。这是沙箱安全模型的核心组件，控制代理能够读取哪些文件和目录。

## 功能点目的

该类型用于：
1. **受限读取**：限制代理只能访问显式指定的根目录
2. **平台默认**：可选包含平台特定的默认可读路径（如系统库）
3. **完全访问**：提供无限制的磁盘读取选项（危险模式）
4. **安全隔离**：防止代理访问敏感文件系统区域

## 具体技术实现

### 数据结构定义

```typescript
import type { AbsolutePathBuf } from "../AbsolutePathBuf";

export type ReadOnlyAccess = 
  | { "type": "restricted", includePlatformDefaults: boolean, readableRoots: Array<AbsolutePathBuf> }
  | { "type": "fullAccess" };
```

### 变体详解

#### Restricted（受限访问）

| 字段 | 类型 | 说明 |
|------|------|------|
| type | "restricted" | 标识为受限访问模式 |
| includePlatformDefaults | boolean | 是否包含平台默认可读路径 |
| readableRoots | AbsolutePathBuf[] | 显式指定的可读根目录列表 |

#### FullAccess（完全访问）

| 字段 | 类型 | 说明 |
|------|------|------|
| type | "fullAccess" | 标识为完全访问模式，无读取限制 |

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Display, Default, JsonSchema, TS)]
#[strum(serialize_all = "kebab-case")]
#[serde(tag = "type", rename_all = "kebab-case")]
#[ts(tag = "type")]
pub enum ReadOnlyAccess {
    /// 限制读取到显式指定的根目录集合
    Restricted {
        /// 包含基本进程执行所需的内置平台读取根目录
        #[serde(default = "default_include_platform_defaults")]
        include_platform_defaults: bool,
        /// 应该可读的额外绝对根目录
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        readable_roots: Vec<AbsolutePathBuf>,
    },

    /// 允许无限制的文件读取
    #[default]
    FullAccess,
}
```

### 辅助方法

```rust
impl ReadOnlyAccess {
    /// 检查是否具有完整的磁盘读取访问权限
    pub fn has_full_disk_read_access(&self) -> bool {
        matches!(self, ReadOnlyAccess::FullAccess)
    }

    /// 检查是否应该包含平台默认值
    pub fn include_platform_defaults(&self) -> bool {
        matches!(
            self,
            ReadOnlyAccess::Restricted {
                include_platform_defaults: true,
                ..
            }
        )
    }

    /// 获取受限读取访问的可读根目录
    /// 对于 FullAccess，返回空列表
    pub fn get_readable_roots_with_cwd(&self, cwd: &Path) -> Vec<AbsolutePathBuf> {
        // 实现包含 cwd 和 readable_roots 的逻辑
    }
}
```

### 平台默认路径

在 macOS 上，平台默认可能包括：
- `/usr/lib`
- `/System/Library`
- 其他系统运行所需路径

在 Linux 上，通过 Landlock 或 bwrap 配置。

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReadOnlyAccess.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 沙箱实现
- Linux 沙箱：`codex-rs/linux-sandbox/src/bwrap.rs`
- Linux 测试：`codex-rs/linux-sandbox/tests/suite/landlock.rs`
- Windows 沙箱：`codex-rs/windows-sandbox-rs/src/setup_orchestrator.rs`
- Seatbelt (macOS)：`codex-rs/core/src/seatbelt.rs`

### 配置集成
- 配置类型：`codex-rs/core/src/config/types.rs`
- 配置模块：`codex-rs/core/src/config/mod.rs`

### 执行策略
- 执行模块：`codex-rs/exec/src/lib.rs`
- 测试客户端：`codex-rs/app-server-test-client/src/lib.rs`

## 依赖与外部交互

### 上游依赖
- 用户配置：从 config.toml 或命令行参数读取
- 平台检测：根据操作系统确定默认路径

### 下游消费
- SandboxPolicy：作为 `SandboxPolicy::ReadOnly` 和 `SandboxPolicy::WorkspaceWrite` 的组成部分
- 沙箱执行器：配置 Landlock/bwrap/Seatbelt 的读取权限

### 使用场景

```rust
// 受限访问示例
let access = ReadOnlyAccess::Restricted {
    include_platform_defaults: true,
    readable_roots: vec!["/home/user/project".into()],
};

// 完全访问示例（危险）
let access = ReadOnlyAccess::FullAccess;
```

## 风险、边界与改进建议

### 边界情况
1. **空根目录**：readableRoots 为空时，仅依赖平台默认值
2. **路径验证**：AbsolutePathBuf 确保路径是绝对路径
3. **重复路径**：get_readable_roots_with_cwd 会去重

### 潜在风险
1. **FullAccess 风险**：完全访问模式可能导致安全风险
2. **平台差异**：不同操作系统的平台默认值不同
3. **路径遍历**：需要确保受限模式下无法通过 .. 绕过限制

### 改进建议
1. **默认安全**：考虑将默认从 FullAccess 改为 Restricted
2. **路径验证**：添加更多路径规范化验证
3. **审计日志**：记录 FullAccess 的使用情况
4. **UI 警告**：在启用 FullAccess 时显示安全警告
5. **作用域限制**：考虑添加时间或操作次数限制
