# BUILD.bazel 研究文档

## 场景与职责

`codex-rs/utils/image/BUILD.bazel` 是 Bazel 构建系统的构建配置文件，负责定义 `codex-utils-image` crate 的构建规则。该 crate 是 Codex 项目中专门用于图像处理的工具库。

## 功能点目的

该 BUILD 文件的核心目的是：
1. **声明 Rust crate 构建目标**：通过 `codex_rust_crate` 宏定义库构建规则
2. **统一构建配置**：与 Cargo.toml 保持一致的 crate 名称 `codex_utils_image`
3. **集成 Bazel 工作区**：使图像处理库能够被其他 Bazel 目标依赖

## 具体技术实现

### 构建规则定义

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "image",
    crate_name = "codex_utils_image",
)
```

**关键参数说明：**
- `name = "image"`：Bazel 目标名称，用于在 BUILD 文件中引用
- `crate_name = "codex_utils_image"`：Rust crate 的标识名称，与 Cargo.toml 中的 `name` 字段对应

### codex_rust_crate 宏行为

根据 `defs.bzl` 中的宏定义，`codex_rust_crate` 会自动：

1. **库目标生成**：如果 `src/` 目录存在，创建 `rust_library` 目标
2. **源码发现**：默认使用 `src/**/*.rs` 作为源码（可通过 `crate_srcs` 覆盖）
3. **构建脚本支持**：自动检测并处理 `build.rs`（如果存在）
4. **测试目标**：自动生成单元测试和集成测试目标
5. **依赖解析**：从 `@crates` 工作区解析所有 crate 依赖

### 依赖管理

该 crate 的依赖通过 `Cargo.toml` 定义，Bazel 通过 `all_crate_deps()` 自动解析：
- `base64`：Base64 编码
- `image`：图像处理（支持 jpeg/png/gif/webp）
- `codex-utils-cache`：内部缓存工具
- `mime_guess`：MIME 类型猜测
- `thiserror`：错误处理
- `tokio`：异步运行时

## 关键代码路径与文件引用

### 相关文件

| 文件路径 | 说明 |
|---------|------|
| `//:defs.bzl` | 定义 `codex_rust_crate` 宏的 Bazel 扩展文件 |
| `Cargo.toml` | Cargo 包配置，Bazel 依赖解析的源 |
| `src/lib.rs` | 库主源码文件 |
| `src/error.rs` | 错误定义模块 |

### Bazel 目标引用

```
//codex-rs/utils/image:image          - 库目标
//codex-rs/utils/image:image-unit-tests - 单元测试目标
```

## 依赖与外部交互

### 内部依赖

```
codex-rs/utils/image
├── 依赖: codex-rs/utils/cache (BlockingLruCache, sha1_digest)
└── 被依赖: codex-rs/core (view_image handler)
└── 被依赖: codex-rs/protocol (models.rs 中的图像处理)
└── 被依赖: codex-rs/tui (clipboard_paste)
```

### 外部 crate 依赖

通过 workspace 统一管理：
- `base64`：标准 Base64 编码引擎
- `image`：`image` crate 提供图像解码/编码/处理
- `mime_guess`：基于文件扩展名的 MIME 类型检测
- `thiserror`：派生宏简化错误类型定义
- `tokio`：异步文件系统操作支持

## 风险、边界与改进建议

### 风险点

1. **缓存键冲突风险**：使用 SHA-1 摘要作为缓存键，虽然概率极低但存在哈希碰撞可能
2. **内存限制**：LRU 缓存固定容量为 32，大图像可能导致内存压力
3. **格式支持限制**：GIF 仅支持非动画（代码注释明确说明）

### 边界条件

1. **最大尺寸限制**：
   - `MAX_WIDTH = 2048`
   - `MAX_HEIGHT = 768`
   - 超出此范围的图像会被缩放

2. **支持的图像格式**：
   - PNG、JPEG、GIF（非动画）、WebP
   - 其他格式会被转换为 PNG

3. **Bazel/Cargo 双构建系统**：
   - 需要保持 Cargo.toml 和 BUILD.bazel 同步
   - 依赖变更后需运行 `just bazel-lock-update`

### 改进建议

1. **缓存容量可配置**：考虑通过环境变量或配置参数暴露缓存容量设置
2. **监控指标**：添加缓存命中率、图像处理耗时等指标暴露
3. **渐进式 JPEG 支持**：评估是否需要支持渐进式 JPEG 编码以优化传输
4. **WebP 有损压缩**：当前使用无损 WebP，可考虑根据场景选择有损/无损
5. **Bazel 构建优化**：如果 crate 增长，考虑添加 `compile_data` 或 `rustc_flags_extra` 优化
