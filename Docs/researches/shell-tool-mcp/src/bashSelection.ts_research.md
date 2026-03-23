# bashSelection.ts 研究文档

## 场景与职责

`bashSelection.ts` 是 shell-tool-mcp 包的核心模块，负责根据宿主操作系统（Linux/macOS）和系统版本选择最合适的 Bash 二进制变体。该模块解决了跨平台 shell 执行中不同发行版/版本需要不同编译基线的问题。

**核心职责：**
1. 根据平台类型（Linux/Darwin）路由到相应的选择逻辑
2. 在 Linux 上基于 `/etc/os-release` 信息匹配最佳 Bash 变体
3. 在 macOS 上基于 Darwin 内核版本选择兼容的 Bash 变体
4. 提供优雅的降级策略（版本不匹配 → ID 匹配 → 全局默认）

## 功能点目的

### 1. `selectLinuxBash(bashRoot, info)` - Linux Bash 变体选择

**目的：** 在多种 Linux 发行版和版本中选择最合适的预编译 Bash 二进制文件。

**匹配优先级（从高到低）：**
1. **精确版本匹配**：`id` 或 `idLike` 匹配，且 `versionId` 前缀匹配
2. **ID 匹配回退**：仅 `id` 或 `idLike` 匹配（忽略版本）
3. **全局默认**：使用 `LINUX_BASH_VARIANTS[0]`（当前为 ubuntu-24.04）

**关键设计决策：**
- 使用 `idLike` 数组支持派生发行版（如 Rocky Linux 继承 RHEL 的 Bash）
- 版本匹配采用前缀比较（`startsWith`），支持 "24.04.1" 匹配 "24.04"
- 所有字符串比较均转为小写，确保大小写不敏感

### 2. `selectDarwinBash(bashRoot, darwinRelease)` - macOS Bash 变体选择

**目的：** 基于 Darwin 内核主版本号选择兼容的 macOS Bash 变体。

**匹配逻辑：**
- 解析 `darwinRelease`（如 "24.0.0" → 24）
- 选择 `minDarwin <= darwinMajor` 的第一个变体（即满足最低版本要求的最旧变体）
- 回退到 `DARWIN_BASH_VARIANTS[0]`（macos-15）

**Darwin 版本映射：**
- Darwin 24+ → macOS 15
- Darwin 23+ → macOS 14
- Darwin 22+ → macOS 13

### 3. `resolveBashPath(targetRoot, platform, darwinRelease, osInfo)` - 统一入口

**目的：** 提供跨平台的统一 Bash 路径解析接口。

**路径构造：**
```
{targetRoot}/bash/{variant.name}/bash
```

**错误处理：**
- Linux 平台必须提供 `osInfo`，否则抛出错误
- 不支持的平台（非 linux/darwin）抛出明确错误

## 具体技术实现

### 数据结构

```typescript
// 候选对象结构（内部使用）
{
  variant: LinuxBashVariant,
  matchesVersion: boolean  // 是否版本匹配
}

// 返回结构
{
  path: string,    // 完整路径
  variant: string  // 变体名称（如 "ubuntu-24.04"）
}
```

### 关键算法流程

**Linux 选择流程：**
```
1. 遍历 LINUX_BASH_VARIANTS
2. 检查 id 匹配: variant.ids.includes(info.id)
   或 idLike 匹配: variant.ids.some(id => info.idLike.includes(id))
3. 若匹配，检查版本: versionId.startsWith(prefix)
4. 收集所有候选到 candidates 数组
5. 优先返回 matchesVersion=true 的候选
6. 其次返回任意匹配的候选
7. 最后返回全局默认
```

**Darwin 选择流程：**
```
1. 解析主版本: parseInt(darwinRelease.split(".")[0])
2. 使用 Array.find 选择 darwinMajor >= minDarwin 的变体
3. 若找到则返回，否则返回全局默认
```

### 辅助函数

**`supportedDetail(variants)`**：生成支持的变体列表字符串，用于错误信息。

## 关键代码路径与文件引用

### 内部依赖

| 导入 | 来源 | 用途 |
|------|------|------|
| `DARWIN_BASH_VARIANTS` | `./constants` | macOS 变体配置列表 |
| `LINUX_BASH_VARIANTS` | `./constants` | Linux 变体配置列表 |
| `BashSelection` | `./types` | 返回类型定义 |
| `OsReleaseInfo` | `./types` | OS 信息输入类型 |

### 被调用方

- **`src/index.ts`**：CLI 入口，调用 `resolveBashPath()` 输出最终 Bash 路径

### 测试覆盖

- **`tests/bashSelection.test.ts`**：
  - `selectLinuxBash`：精确版本匹配、无匹配回退
  - `selectDarwinBash`：兼容版本选择、旧版本回退

## 依赖与外部交互

### Node.js 内置模块

- **`node:path`**：跨平台路径拼接（`path.join`）
- **`node:os`**：获取 Darwin 版本（`os.release()`）作为默认值

### 文件系统约定

期望的目录结构：
```
{targetRoot}/
└── bash/
    ├── ubuntu-24.04/bash
    ├── ubuntu-22.04/bash
    ├── debian-12/bash
    ├── macos-15/bash
    └── ...
```

### 版本配置源

变体定义集中管理于 `src/constants.ts`，本文件仅实现选择逻辑，不硬编码变体列表。

## 风险、边界与改进建议

### 已知风险

1. **版本前缀匹配歧义**
   - 当前 `"12"` 会同时匹配 `"12"` 和 `"12.1"`
   - 但也会错误匹配 `"123"`（虽然实际发行版版本号不太可能出现）

2. **Darwin 版本解析脆弱性**
   - `split(".")[0]` 假设版本号格式为 `x.y.z`
   - 非标准格式（如 "24" 无子版本）会正确解析，但空字符串会回退到 "0"

3. **Linux 回退过于激进**
   - 当 OS 完全未知时，直接回退到 Ubuntu 24.04 的 Bash
   - 可能导致 glibc 兼容性问题（尽管 musl 构建缓解了此问题）

4. **无变体时的崩溃**
   - 若 `LINUX_BASH_VARIANTS` 或 `DARWIN_BASH_VARIANTS` 为空数组
   - `pickVariant` 返回 `undefined`，后续访问 `.name` 会抛出

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| `osInfo.id` 为空字符串 | 依赖 `idLike` 匹配或回退 | 合理 |
| `versionId` 为空字符串 | 无法版本匹配，走 ID 匹配或回退 | 合理 |
| `idLike` 包含空字符串 | `filter(Boolean)` 已过滤 | 已处理 |
| Darwin 版本 "0.0.0" | 回退到第一个变体 | 合理 |
| 不支持的 platform | 抛出明确错误 | 正确 |

### 改进建议

1. **增强版本匹配精度**
   ```typescript
   // 建议：添加边界检查，避免 "12" 匹配 "123"
   variant.versions.some(prefix => 
     versionId === prefix || versionId.startsWith(prefix + ".")
   )
   ```

2. **Darwin 版本验证**
   ```typescript
   // 建议：验证解析结果
   const darwinMajor = Number.parseInt(...);
   if (Number.isNaN(darwinMajor)) {
     throw new Error(`Invalid Darwin release: ${darwinRelease}`);
   }
   ```

3. **空变体数组保护**
   ```typescript
   // 在 pickVariant 后添加检查
   if (!preferred) {
     throw new Error(`No Bash variants configured for ${platform}`);
   }
   ```

4. **日志与可观测性**
   - 当前选择过程完全静默
   - 建议添加调试日志记录匹配过程（可通过环境变量启用）

5. **缓存优化**
   - `resolveBashPath` 在单次运行中可能被多次调用
   - 建议对 `readOsRelease()` 和路径解析结果添加简单缓存

### 测试缺口

- 未测试 `resolveBashPath` 的完整流程
- 未测试 `idLike` 匹配逻辑
- 未测试错误路径（不支持的 platform、空变体数组）
- 未测试边界版本号（如 "24", "24.0", "24.0.0"）
