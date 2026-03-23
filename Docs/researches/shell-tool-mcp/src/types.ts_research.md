# types.ts 研究文档

## 场景与职责

`types.ts` 是 shell-tool-mcp 包的类型定义中心，集中声明所有跨模块共享的 TypeScript 接口和类型。该模块作为项目的"契约层"，确保各组件间数据结构的类型安全一致性。

**核心职责：**
1. 定义 Bash 变体的配置结构（Linux 和 Darwin）
2. 定义操作系统信息的数据结构
3. 定义 Bash 选择结果的返回类型
4. 作为单一类型数据源，避免重复定义和类型漂移

## 功能点目的

### 1. `LinuxBashVariant` - Linux Bash 变体配置类型

**目的：** 描述 Linux 发行版 Bash 构建的配置结构。

```typescript
type LinuxBashVariant = {
  name: string;       // 变体标识符，用作目录名
  ids: Array<string>; // 匹配的 /etc/os-release ID 列表
  versions: Array<string>; // 匹配的版本前缀列表
};
```

**设计考量：**
- **name**：同时作为标识符和文件系统路径组件（如 `"ubuntu-24.04"` → `bash/ubuntu-24.04/bash`）
- **ids**：支持多 ID 匹配，处理派生发行版（如 `centos-9` 同时匹配 `centos`、`rhel`、`rocky`、`almalinux`）
- **versions**：字符串数组支持多版本前缀（如同时支持 `"12"` 和 `"12.0"`）

### 2. `DarwinBashVariant` - macOS Bash 变体配置类型

**目的：** 描述 macOS Bash 构建的配置结构。

```typescript
type DarwinBashVariant = {
  name: string;      // 变体标识符（如 "macos-15"）
  minDarwin: number; // 最低 Darwin 内核主版本号
};
```

**设计考量：**
- **minDarwin**：使用数值比较（`>=`）而非字符串匹配，简化版本兼容性判断
- **与 Linux 结构差异**：macOS 无需 `ids`（单一供应商），版本判断逻辑也不同（最低版本 vs 前缀匹配）

### 3. `OsReleaseInfo` - 操作系统信息类型

**目的：** 标准化 `/etc/os-release` 的解析结果。

```typescript
type OsReleaseInfo = {
  id: string;           // 发行版 ID（小写）
  idLike: Array<string>; // 派生关系 ID 列表（小写）
  versionId: string;    // 版本标识符
};
```

**字段映射：**
| 字段 | 来源 | 转换 |
|------|------|------|
| `id` | `ID` | 小写化 |
| `idLike` | `ID_LIKE` | 分割 + 小写化 + 去空 |
| `versionId` | `VERSION_ID` | 原样保留（去引号） |

### 4. `BashSelection` - Bash 选择结果类型

**目的：** 统一 Bash 选择函数的返回格式。

```typescript
type BashSelection = {
  path: string;    // Bash 二进制文件的绝对路径
  variant: string; // 选中的变体名称（如 "ubuntu-24.04"）
};
```

**设计考量：**
- **分离路径和元数据**：调用方可仅使用路径，或记录选择的变体用于调试
- **variant 冗余但有用**：可从路径解析，但显式提供避免重复解析逻辑

## 具体技术实现

### 类型导出策略

```typescript
export type LinuxBashVariant = { ... };
export type DarwinBashVariant = { ... };
export type OsReleaseInfo = { ... };
export type BashSelection = { ... };
```

- 全部使用 `export type`，确保类型在模块边界可用
- 不使用 `interface`，保持简单对象类型语义

### 类型使用模式

**在常量定义中：**
```typescript
// constants.ts
export const LINUX_BASH_VARIANTS: ReadonlyArray<LinuxBashVariant> = [...];
```

**在函数签名中：**
```typescript
// bashSelection.ts
export function selectLinuxBash(
  bashRoot: string,
  info: OsReleaseInfo,
): BashSelection { ... }
```

**在测试中：**
```typescript
// bashSelection.test.ts
import { OsReleaseInfo } from "../src/types";
const info: OsReleaseInfo = { id: "ubuntu", idLike: ["debian"], versionId: "24.04" };
```

## 关键代码路径与文件引用

### 类型消费者

| 类型 | 消费者 | 用途 |
|------|--------|------|
| `LinuxBashVariant` | `constants.ts` | 数组元素类型注解 |
| `DarwinBashVariant` | `constants.ts` | 数组元素类型注解 |
| `OsReleaseInfo` | `osRelease.ts` | 解析函数返回类型 |
| `OsReleaseInfo` | `bashSelection.ts` | 选择函数参数类型 |
| `BashSelection` | `bashSelection.ts` | 选择函数返回类型 |

### 依赖关系图

```
types.ts
├── LinuxBashVariant ──→ constants.ts (LINUX_BASH_VARIANTS)
├── DarwinBashVariant ─→ constants.ts (DARWIN_BASH_VARIANTS)
├── OsReleaseInfo ─────→ osRelease.ts (parseOsRelease 返回)
│                        bashSelection.ts (selectLinuxBash 参数)
└── BashSelection ─────→ bashSelection.ts (select* 函数返回)
```

## 依赖与外部交互

### 无运行时依赖

本模块为纯类型定义，：
- 无 `import` 语句
- 编译后完全擦除（无 JavaScript 输出）
- 零运行时开销

### 与 Node.js 类型的关系

本模块定义的领域类型与 Node.js 内置类型互补：
- `NodeJS.Platform` / `NodeJS.Architecture` → 用于平台检测（`platform.ts`）
- `OsReleaseInfo` / `BashSelection` → 用于业务逻辑（本模块）

## 风险、边界与改进建议

### 已知风险

1. **类型与实现不同步**
   - 若修改 `osRelease.ts` 的解析逻辑但未更新 `OsReleaseInfo`，可能导致类型不匹配
   - 例如：添加新字段到解析结果但未更新类型定义

2. **字段语义模糊**
   - `versionId` 为字符串，但某些比较逻辑可能期望数值比较
   - `idLike` 为空数组 vs 未定义，语义上是否等价？

3. **无运行时验证**
   - TypeScript 类型仅在编译时检查
   - 运行时接收的外部数据（如 API 响应）可能不符合类型

### 边界情况

| 场景 | 类型系统行为 | 运行时风险 |
|------|--------------|------------|
| `id` 为 `null` | 编译错误 | 若使用 `as any` 绕过，可能导致空指针 |
| `idLike` 为 `undefined` | 编译错误 | 需要默认值 `[]` |
| `versionId` 含前导零 | 允许（字符串）| 数值比较时可能意外（"9" > "10"） |
| 额外字段 | 允许（structural typing）| 无风险，但可能表示类型不完整 |

### 改进建议

1. **添加只读修饰符**
   ```typescript
   export type OsReleaseInfo = {
     readonly id: string;
     readonly idLike: ReadonlyArray<string>;
     readonly versionId: string;
   };
   ```

2. **使用 branded types 增强类型安全**
   ```typescript
   type BashPath = string & { __brand: "BashPath" };
   type VariantName = string & { __brand: "VariantName" };
   
   export type BashSelection = {
     path: BashPath;
     variant: VariantName;
   };
   ```

3. **添加 JSDoc 文档**
   ```typescript
   /**
    * Represents the parsed contents of /etc/os-release.
    * All string fields are normalized to lowercase.
    */
   export type OsReleaseInfo = {
     /** The operating system identifier (e.g., "ubuntu", "debian") */
     id: string;
     /** Upstream distribution identifiers (e.g., ["debian"] for Ubuntu) */
     idLike: Array<string>;
     /** The version identifier (e.g., "24.04", "12") */
     versionId: string;
   };
   ```

4. **考虑使用 discriminated union**
   ```typescript
   export type BashVariant = 
     | { platform: "linux"; config: LinuxBashVariant }
     | { platform: "darwin"; config: DarwinBashVariant };
   ```

5. **添加验证函数（运行时类型检查）**
   ```typescript
   export function isOsReleaseInfo(obj: unknown): obj is OsReleaseInfo {
     return (
       typeof obj === "object" &&
       obj !== null &&
       "id" in obj &&
       typeof (obj as OsReleaseInfo).id === "string" &&
       "idLike" in obj &&
       Array.isArray((obj as OsReleaseInfo).idLike) &&
       "versionId" in obj &&
       typeof (obj as OsReleaseInfo).versionId === "string"
     );
   }
   ```

6. **版本号专用类型**
   ```typescript
   // 区分原始版本字符串和已解析的版本
   export type VersionId = string;
   export type ParsedVersion = { major: number; minor: number; patch: number };
   ```

### 架构演进建议

当前类型设计为简单对象，适合当前规模。若项目扩展，可考虑：
- 使用 `zod` 或 `io-ts` 进行运行时类型验证
- 将类型定义拆分为更细粒度的模块（`types/platform.ts`、`types/bash.ts`）
- 添加版本化类型（`OsReleaseInfoV1`、`OsReleaseInfoV2`）支持向后兼容

### 测试策略

类型本身无需测试，但建议：
- 使用 `type-fest` 或条件类型测试确保类型约束
- 在 CI 中启用 `tsc --noEmit` 确保类型一致性
- 考虑使用 `dtslint` 或 `tsd` 进行类型级单元测试
