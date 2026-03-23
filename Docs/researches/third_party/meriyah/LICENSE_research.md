# third_party/meriyah/LICENSE 研究文档

## 场景与职责

### 文件定位

`third_party/meriyah/LICENSE` 是 OpenAI Codex 项目中用于记录第三方依赖 **Meriyah** 许可证信息的合规性文件。该文件位于项目的 `third_party/meriyah/` 目录下，仅包含 ISC 许可证全文。

### Meriyah 在项目中的角色

Meriyah 是一个高性能的 JavaScript 解析器（parser），在 Codex 项目中被用于 **JavaScript REPL (js_repl)** 功能模块。具体职责包括：

1. **JavaScript 代码解析**：将用户输入的 JavaScript 代码解析为 AST（抽象语法树）
2. **语法分析**：支持 ES 模块语法、现代 JavaScript 特性（ES2020+）
3. **代码插桩辅助**：为 REPL 的变量绑定持久化功能提供 AST 级别的代码分析能力

### 使用场景

```
用户输入 JS 代码 → js_repl kernel → Meriyah 解析 AST → 代码插桩 → VM 执行
```

## 功能点目的

### 许可证合规性

该 LICENSE 文件的存在目的是满足开源许可证的合规性要求：

1. **版权声明**：明确记录 Meriyah 的版权归属（KFlash 及其他贡献者，2019 及之后）
2. **许可证类型**：ISC License（宽松的开源许可证，类似于 MIT）
3. **再分发合规**：Codex 项目将 Meriyah 的 UMD 构建产物内嵌在二进制中，需要保留许可证声明

### ISC 许可证要点

- 允许使用、复制、修改、分发，无论是否收费
- 唯一条件：必须在所有副本中包含版权声明和许可声明
- 免责声明：软件按"原样"提供，作者不承担任何责任

## 具体技术实现

### 文件内容结构

```
ISC License

Copyright (c) 2019 and later, KFlash and others.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
```

### Meriyah 在 js_repl 中的技术集成

#### 1. 代码嵌入方式

Meriyah 以 **UMD 构建产物** 的形式内嵌在 Rust 二进制中：

```rust
// codex-rs/core/src/tools/js_repl/mod.rs
const MERIYAH_UMD: &str = include_str!("meriyah.umd.min.js");
```

运行时动态写入临时目录：

```rust
async fn write_kernel_script(&self) -> Result<PathBuf, std::io::Error> {
    let dir = self.tmp_dir.path();
    let kernel_path = dir.join("js_repl_kernel.js");
    let meriyah_path = dir.join("meriyah.umd.min.js");
    tokio::fs::write(&kernel_path, KERNEL_SOURCE).await?;
    tokio::fs::write(&meriyah_path, MERIYAH_UMD).await?;  // 写入 Meriyah
    Ok(kernel_path)
}
```

#### 2. 在 kernel.js 中的使用

```javascript
// codex-rs/core/src/tools/js_repl/kernel.js
const meriyahPromise = import("./meriyah.umd.min.js").then(
  (m) => m.default ?? m,
);

async function buildModuleSource(code) {
  const meriyah = await meriyahPromise;
  const ast = meriyah.parseModule(code, {
    next: true,        // 支持 ES 新特性
    module: true,      // 解析为 ES 模块
    ranges: true,      // 包含节点范围信息
    loc: false,        // 不包含位置信息
    disableWebCompat: true,
  });
  // ... AST 处理逻辑
}
```

#### 3. 解析器配置参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `next` | `true` | 支持 ES2020+ 新特性 |
| `module` | `true` | 按 ES 模块解析 |
| `ranges` | `true` | 包含 start/end 位置 |
| `loc` | `false` | 不包含行列号 |
| `disableWebCompat` | `true` | 禁用 Web 兼容性模式 |

#### 4. 版本信息

当前集成的 Meriyah 版本：**v7.0.0**

来源：`npm package meriyah@7.0.0 (dist/meriyah.umd.min.js)`

构建产物大小：约 134KB（压缩后）

## 关键代码路径与文件引用

### 直接引用该 LICENSE 的文件

1. **NOTICE**（项目根目录）
   ```
   This project includes Meriyah parser assets from [meriyah](https://github.com/meriyah/meriyah), licensed under the ISC license.
   Copyright (c) 2019 and later, KFlash and others.
   ```

2. **meriyah.umd.min.js**（头部注释）
   ```javascript
   /*! Meriyah v7.0.0
    * Source: npm package meriyah@7.0.0 (dist/meriyah.umd.min.js)
    * License: ISC (see third_party/meriyah/LICENSE)
    */
   ```

3. **docs/js_repl.md**（文档引用）
   ```markdown
   Licensing is tracked in:
   - `third_party/meriyah/LICENSE`
   - `NOTICE`
   ```

### 相关文件路径

```
third_party/meriyah/LICENSE                          # 本文件
├── codex-rs/core/src/tools/js_repl/meriyah.umd.min.js  # UMD 构建产物
├── codex-rs/core/src/tools/js_repl/kernel.js           # 使用 Meriyah 的 JS kernel
├── codex-rs/core/src/tools/js_repl/mod.rs              # Rust 端集成代码
├── docs/js_repl.md                                     # 使用文档
└── NOTICE                                              # 项目级归属声明
```

### 构建与更新流程

根据 `docs/js_repl.md` 中的说明：

```bash
# 更新 Meriyah 版本的标准流程
tmp="$(mktemp -d)"
cd "$tmp"
npm pack meriyah@7.0.0
tar -xzf meriyah-7.0.0.tgz
cp package/dist/meriyah.umd.min.js /path/to/repo/codex-rs/core/src/tools/js_repl/meriyah.umd.min.js
cp package/LICENSE.md /path/to/repo/third_party/meriyah/LICENSE
```

## 依赖与外部交互

### 上游依赖

- **Meriyah 项目**：https://github.com/meriyah/meriyah
- **npm 包**：`meriyah@7.0.0`
- **许可证**：ISC License

### 下游使用者

| 模块 | 用途 |
|------|------|
| `js_repl` kernel | JavaScript 代码解析与 AST 分析 |
| `buildModuleSource()` | 解析用户代码，提取变量绑定 |
| `collectBindings()` | 遍历 AST 收集变量声明 |
| `instrumentCurrentBindings()` | 基于 AST 进行代码插桩 |

### 与 Node.js VM 的关系

```
┌─────────────────────────────────────────────────────────────┐
│                      js_repl Kernel                          │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐ │
│  │ User Code   │───▶│ Meriyah      │───▶│ AST Analysis    │ │
│  │ (String)    │    │ parseModule  │    │ & Instrument    │ │
│  └─────────────┘    └──────────────┘    └─────────────────┘ │
│                                                  │          │
│  ┌─────────────┐    ┌──────────────┐            ▼          │
│  │ VM Context  │◀───│ SourceText   │◀─── Instrumented     │
│  │ (vm.Module) │    │ Module       │    Source Code       │
│  └─────────────┘    └──────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险分析

#### 1. 许可证合规风险

| 风险等级 | 描述 | 缓解措施 |
|----------|------|----------|
| 低 | ISC 许可证要求保留版权声明 | 已正确放置 LICENSE 文件，NOTICE 文件已声明 |
| 低 | 源代码修改后的许可证变更 | 当前使用未修改的官方构建产物 |

#### 2. 技术风险

| 风险 | 影响 | 说明 |
|------|------|------|
| Meriyah 解析失败 | 高 | 某些边缘 JavaScript 语法可能解析失败，导致整个 js_repl 执行失败 |
| 版本过时 | 中 | v7.0.0 可能不支持最新的 TC39 提案语法 |
| 性能瓶颈 | 低 | 大型代码块的 AST 构建可能耗时，但通常可接受 |

#### 3. 安全风险

- **AST 注入风险**：Meriyah 本身不执行代码，仅解析，风险较低
- **原型链污染**：解析器配置 `disableWebCompat: true` 减少了攻击面

### 边界条件

1. **语法支持边界**：
   - 支持：ES2020+ 标准语法
   - 不支持：Stage 0-2 实验性提案（除非 Meriyah 已支持）
   - 不支持：JSX（Meriyah 支持，但 js_repl 未启用）

2. **代码大小边界**：
   - 单次解析的代码大小受 Node.js VM 内存限制
   - 无显式代码大小限制，但超大代码块可能导致性能下降

3. **并发边界**：
   - Meriyah 实例在 kernel.js 中单例使用
   - 无并发解析冲突风险（kernel 串行处理请求）

### 改进建议

#### 1. 许可证管理改进

```markdown
- 建议添加 `third_party/meriyah/README.md` 记录：
  - 当前版本号
  - 更新历史
  - 与上游的 diff（如有本地修改）
  
- 建议自动化检查：在 CI 中验证 LICENSE 文件与 meriyah.umd.min.js 中的版本声明一致
```

#### 2. 技术改进

| 优先级 | 建议 | 理由 |
|--------|------|------|
| 中 | 建立 Meriyah 版本更新机制 | 当前 v7.0.0 发布于 2024 年，需跟踪安全更新 |
| 低 | 添加解析失败降级处理 | 当 Meriyah 解析失败时，可尝试其他解析器或给出友好错误 |
| 低 | 考虑使用 WASM 版本 | 如有性能需求，可考虑 Meriyah 的 WASM 构建 |

#### 3. 文档改进

- 在 LICENSE 文件头部添加注释说明：
  ```
  # This is the upstream license for Meriyah JavaScript parser
  # Used in: codex-rs/core/src/tools/js_repl/
  # Version: 7.0.0
  # Source: https://github.com/meriyah/meriyah
  ```

#### 4. 监控与可观测性

- 建议添加 metrics：
  - Meriyah 解析耗时
  - 解析失败率
  - AST 节点数量分布

### 更新检查清单

当更新 Meriyah 版本时，需验证：

- [ ] `meriyah.umd.min.js` 已替换为新版本
- [ ] `third_party/meriyah/LICENSE` 已同步更新
- [ ] `NOTICE` 文件中的版权信息已更新（如有变更）
- [ ] `meriyah.umd.min.js` 头部版本注释已更新
- [ ] `docs/js_repl.md` 中的版本号已更新
- [ ] js_repl 集成测试通过
- [ ] 手动验证基本 JavaScript 解析功能正常

---

*文档生成时间：2026-03-24*
*基于代码版本：meriyah@7.0.0*
