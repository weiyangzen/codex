# platform.ts 研究文档

## 场景与职责

`platform.ts` 是 shell-tool-mcp 包的平台抽象层，负责将 Node.js 的运行时平台标识（`process.platform` 和 `process.arch`）映射为 Rust 风格的 target triple 字符串。该模块是连接 Node.js 运行时与预编译二进制文件命名约定的桥梁。

**核心职责：**
1. 将 `NodeJS.Platform` 和 `NodeJS.Architecture` 组合解析为 target triple
2. 支持 Linux（musl libc）和 macOS 两大平台
3. 支持 x64 和 arm64 两种架构
4. 对不支持的平台/架构组合抛出明确错误

## 功能点目的

### `resolveTargetTriple(platform, arch)` - 平台三元组解析

**目的：** 将 Node.js 抽象的平台标识转换为具体的二进制目标标识。

**支持的映射：**

| Platform | Architecture | Target Triple |
|----------|--------------|---------------|
| `linux` | `x64` | `x86_64-unknown-linux-musl` |
| `linux` | `arm64` | `aarch64-unknown-linux-musl` |
| `darwin` | `x64` | `x86_64-apple-darwin` |
| `darwin` | `arm64` | `aarch64-apple-darwin` |

**设计决策：**
- **musl vs glibc**：Linux 构建使用 musl libc 而非 glibc，实现更好的跨发行版兼容性
- **架构命名**：遵循 Rust 约定（`x86_64`/`aarch64`）而非 Node.js 约定（`x64`/`arm64`）
- **严格匹配**：不支持的组合直接抛出错误，避免静默使用错误二进制

## 具体技术实现

### 算法流程

```typescript
if (platform === "linux") {
  if (arch === "x64") return "x86_64-unknown-linux-musl";
  if (arch === "arm64") return "aarch64-unknown-linux-musl";
} else if (platform === "darwin") {
  if (arch === "x64") return "x86_64-apple-darwin";
  if (arch === "arm64") return "aarch64-apple-darwin";
}
throw new Error(`Unsupported platform: ${platform} (${arch})`);
```

### 错误处理策略

- **早期失败**：在路径构造前即检测不支持的平台
- **明确错误信息**：包含 platform 和 arch 值，便于调试
- **无默认回退**：避免在未知平台上运行可能不兼容的二进制

### 类型安全

```typescript
export function resolveTargetTriple(
  platform: NodeJS.Platform,
  arch: NodeJS.Architecture,
): string {
```

使用 Node.js 内置类型定义：
- `NodeJS.Platform`: `'aix' | 'android' | 'darwin' | 'freebsd' | 'haiku' | 'linux' | ...`
- `NodeJS.Architecture`: `'arm' | 'arm64' | 'ia32' | 'loong64' | 'mips' | 'mipsel' | 'ppc' | ...`

## 关键代码路径与文件引用

### 消费者

| 消费者 | 调用方式 | 用途 |
|--------|----------|------|
| `src/index.ts` | `resolveTargetTriple(process.platform, process.arch)` | 构造 vendor 子目录路径 |

### 类型定义来源

- **全局类型**：`NodeJS.Platform` 和 `NodeJS.Architecture` 来自 `@types/node`
- **编译时检查**：TypeScript 确保传入值符合枚举

### 与构建系统的关联

Target triple 必须与 `vendor/` 目录结构一致：
```
vendor/
├── x86_64-unknown-linux-musl/    # Linux x64
├── aarch64-unknown-linux-musl/   # Linux ARM64
├── x86_64-apple-darwin/          # macOS Intel
└── aarch64-apple-darwin/         # macOS Apple Silicon
```

## 依赖与外部交互

### Node.js 运行时

- **输入来源**：`process.platform` 和 `process.arch`
- **值稳定性**：这两个属性在进程生命周期内恒定，由 Node.js 启动时确定

### 跨平台考量

| 平台 | 支持状态 | 说明 |
|------|----------|------|
| Linux x64 | ✅ 支持 | 主流服务器和桌面 |
| Linux ARM64 | ✅ 支持 | 云实例（AWS Graviton）、ARM 服务器 |
| macOS Intel | ✅ 支持 | 旧款 Mac |
| macOS Apple Silicon | ✅ 支持 | M1/M2/M3 Mac |
| Windows | ❌ 不支持 | 未实现映射 |
| FreeBSD | ❌ 不支持 | 未实现映射 |
| Linux ARMv7 | ❌ 不支持 | 32 位 ARM，未实现 |
| Linux x86 (32-bit) | ❌ 不支持 | 已淘汰，未实现 |

### musl libc 选择理由

```
x86_64-unknown-linux-musl
         │      │    │
         │      │    └── libc 实现：musl（而非 gnu）
         │      └── 厂商：unknown（通用）
         └── 架构：x86_64
```

- **静态链接**：musl 支持完全静态链接，无外部依赖
- **跨发行版兼容**：不依赖宿主 glibc 版本
- **体积更小**：musl 二进制通常比 glibc 版本更小
- **容器友好**：适合 Alpine 等轻量级基础镜像

## 风险、边界与改进建议

### 已知风险

1. **架构别名处理**
   - Node.js 使用 `x64`，但 Rust/LLVM 使用 `x86_64`
   - Node.js 使用 `arm64`，但 Rust/LLVM 使用 `aarch64`
   - 当前硬编码映射，若 Node.js 新增别名需手动更新

2. **平台检测延迟**
   - `process.platform` 在 Windows 上为 `"win32"`，即使 64 位系统
   - 这符合 Node.js 设计，但可能让期望 `"win64"` 的开发者困惑

3. **无运行时验证**
   - 返回的 target triple 不验证对应目录是否存在
   - 验证延迟到 `index.ts` 或 `bashSelection.ts`

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| `platform === "win32"` | 抛出错误 | ✅ 明确失败 |
| `arch === "ia32"`（32位 x86） | 抛出错误 | ✅ 明确失败 |
| `arch === "arm"`（32位 ARM） | 抛出错误 | ✅ 明确失败 |
| `platform === "freebsd"` | 抛出错误 | ✅ 明确失败 |
| 无效字符串（类型系统无法捕获） | 抛出错误 | ✅ 运行时保护 |

### 改进建议

1. **支持更多平台**
   ```typescript
   // 添加 Windows 支持（若未来提供 Windows 构建）
   if (platform === "win32") {
     if (arch === "x64") return "x86_64-pc-windows-msvc";
     if (arch === "arm64") return "aarch64-pc-windows-msvc";
   }
   ```

2. **添加架构别名映射**
   ```typescript
   // 更健壮的架构检测
   const normalizedArch = {
     x64: "x86_64",
     amd64: "x86_64",
     arm64: "aarch64",
     aarch64: "aarch64",
   }[arch] || arch;
   ```

3. **运行时能力检测**
   ```typescript
   import { existsSync } from "node:fs";
   
   export function resolveTargetTriple(
     platform: NodeJS.Platform,
     arch: NodeJS.Architecture,
     vendorPath: string,
   ): string {
     const triple = /* ... */;
     if (!existsSync(join(vendorPath, triple))) {
       throw new Error(`No binaries available for ${triple}`);
     }
     return triple;
   }
   ```

4. **文档化不支持的平台**
   ```typescript
   throw new Error(
     `Unsupported platform: ${platform} (${arch}). ` +
     `Supported: Linux (x64, arm64), macOS (x64, arm64)`
   );
   ```

5. **考虑 Rosetta 2 场景**
   ```typescript
   // 在 Apple Silicon Mac 上，Node 可能以 x64 模式运行（Rosetta）
   // 但应优先使用原生 ARM64 二进制
   if (platform === "darwin" && arch === "x64") {
     // 检测是否实际在 ARM64 硬件上
     const { machine } = require("node:os");
     if (machine() === "arm64") {
       console.warn("Running under Rosetta 2, consider using ARM64 Node.js");
     }
   }
   ```

6. **提取常量**
   ```typescript
   // 将映射关系提取为可测试的数据结构
   export const SUPPORTED_TRIPLES = [
     { platform: "linux", arch: "x64", triple: "x86_64-unknown-linux-musl" },
     { platform: "linux", arch: "arm64", triple: "aarch64-unknown-linux-musl" },
     { platform: "darwin", arch: "x64", triple: "x86_64-apple-darwin" },
     { platform: "darwin", arch: "arm64", triple: "aarch64-apple-darwin" },
   ] as const;
   ```

### 测试缺口

- 无直接单元测试（函数过于简单）
- 未测试错误路径（不支持的 platform/arch）
- 未验证返回的 target triple 格式正确性
- 建议添加：
  ```typescript
  describe("resolveTargetTriple", () => {
    it.each([
      ["linux", "x64", "x86_64-unknown-linux-musl"],
      ["linux", "arm64", "aarch64-unknown-linux-musl"],
      ["darwin", "x64", "x86_64-apple-darwin"],
      ["darwin", "arm64", "aarch64-apple-darwin"],
    ])("%s/%s → %s", (platform, arch, expected) => {
      expect(resolveTargetTriple(platform as any, arch as any)).toBe(expected);
    });

    it("throws on unsupported platform", () => {
      expect(() => resolveTargetTriple("win32" as any, "x64" as any))
        .toThrow("Unsupported platform");
    });
  });
  ```
