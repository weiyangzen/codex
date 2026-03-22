# shell-tool-mcp/tests 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 整体定位

`shell-tool-mcp/tests` 是 `@openai/codex-shell-tool-mcp` 包的测试目录，该包是 Codex CLI 的 MCP (Model Context Protocol) 服务器组件，提供沙箱化的 Shell 执行能力。

### 核心职责

测试目录负责验证以下关键功能模块：

1. **Bash 二进制选择逻辑** (`bashSelection.test.ts`)
   - 验证 Linux 系统下基于 `/etc/os-release` 的 Bash 变体选择
   - 验证 macOS 系统下基于 Darwin 内核版本的 Bash 变体选择
   - 确保在无法精确匹配时能够正确回退到兼容版本

2. **OS Release 文件解析** (`osRelease.test.ts`)
   - 验证 `/etc/os-release` 文件格式的解析逻辑
   - 处理字段缺失、引号包裹、空格分隔等边界情况

### 测试范围边界

| 范围 | 说明 |
|------|------|
| **包含** | TypeScript 源码单元测试 |
| **不包含** | 实际 Bash 二进制执行测试（由 Rust 侧的 `codex-rs/shell-escalation` 负责） |
| **不包含** | MCP 协议集成测试（由上层应用负责） |
| **不包含** | 实际沙箱功能测试（属于 E2E 测试范畴） |

---

## 功能点目的

### 1. Bash 选择逻辑测试 (`bashSelection.test.ts`)

#### 目的

确保 MCP 服务器能够在不同操作系统和发行版上选择正确的预编译 Bash 二进制文件。

#### 测试场景

**Linux 场景：**
- **精确版本匹配**：当 OS ID 和版本都匹配时，选择对应变体（如 Ubuntu 24.04 → `ubuntu-24.04`）
- **无匹配回退**：当 OS 不在支持列表时，回退到第一个支持的变体（`ubuntu-24.04`）

**macOS 场景：**
- **版本兼容选择**：Darwin 24.x → `macos-15`
- **旧版本回退**：Darwin 20.x 回退到第一个可用变体（`macos-15`）

#### 业务价值

- 保证跨平台兼容性
- 确保 glibc 版本匹配，避免运行时链接错误
- 提供可预测的降级行为

### 2. OS Release 解析测试 (`osRelease.test.ts`)

#### 目的

验证从 `/etc/os-release` 提取发行版信息的能力，这是 Linux Bash 选择的关键输入。

#### 测试场景

- **基础字段解析**：提取 `ID`, `ID_LIKE`, `VERSION_ID`
- **缺失字段处理**：当字段不存在时返回空值
- **ID_LIKE 规范化**：将空格分隔的字符串转换为小写数组（如 `"CentOS   Rocky"` → `["centos", "rocky"]`）
- **引号处理**：去除字段值的引号包裹

#### 业务价值

- 支持所有符合 freedesktop.org 规范的发行版
- 正确处理衍生发行版（如 Rocky Linux 继承 RHEL 的兼容性）

---

## 具体技术实现

### 1. 测试框架配置

```javascript
// jest.config.cjs
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/tests"],
};
```

- **测试框架**：Jest 29.7.0
- **TypeScript 支持**：ts-jest
- **运行环境**：Node.js（非浏览器环境）

### 2. Bash 选择算法详解

#### Linux 选择逻辑

```typescript
// 核心算法位于 src/bashSelection.ts
function selectLinuxBash(bashRoot: string, info: OsReleaseInfo): BashSelection {
  // 1. 构建候选列表：匹配 id 或 idLike
  const candidates = LINUX_BASH_VARIANTS.filter(variant => 
    variant.ids.includes(info.id) || 
    variant.ids.some(id => info.idLike.includes(id))
  ).map(variant => ({
    variant,
    matchesVersion: versionId && variant.versions.some(v => versionId.startsWith(v))
  }));

  // 2. 优先选择版本匹配的
  const preferred = candidates.find(c => c.matchesVersion);
  if (preferred) return buildSelection(preferred.variant);

  // 3. 次选：仅 ID 匹配的
  const fallbackMatch = candidates.find(c => c.variant);
  if (fallbackMatch) return buildSelection(fallbackMatch.variant);

  // 4. 最终回退：第一个可用变体
  return buildSelection(LINUX_BASH_VARIANTS[0]);
}
```

#### Darwin 选择逻辑

```typescript
function selectDarwinBash(bashRoot: string, darwinRelease: string): BashSelection {
  const darwinMajor = parseInt(darwinRelease.split(".")[0], 10);
  
  // 选择满足 minDarwin 要求的第一个变体
  const preferred = DARWIN_BASH_VARIANTS.find(v => darwinMajor >= v.minDarwin);
  if (preferred) return buildSelection(preferred);
  
  // 回退到第一个变体
  return buildSelection(DARWIN_BASH_VARIANTS[0]);
}
```

### 3. OS Release 解析算法

```typescript
// src/osRelease.ts
function parseOsRelease(contents: string): OsReleaseInfo {
  const lines = contents.split("\n").filter(Boolean);
  const info: Record<string, string> = {};
  
  for (const line of lines) {
    const [rawKey, rawValue] = line.split("=", 2);
    if (!rawKey || rawValue === undefined) continue;
    
    const key = rawKey.toLowerCase();
    // 去除首尾的引号
    const value = rawValue.replace(/^"/, "").replace(/"$/, "");
    info[key] = value;
  }
  
  // ID_LIKE 规范化：按空白分割，转小写，过滤空值
  const idLike = (info.id_like || "")
    .split(/\s+/)
    .map(s => s.trim().toLowerCase())
    .filter(Boolean);
    
  return {
    id: (info.id || "").toLowerCase(),
    idLike,
    versionId: info.version_id || "",
  };
}
```

### 4. 支持的平台变体

#### Linux Bash 变体（`src/constants.ts`）

| 变体名称 | 支持的 ID | 版本前缀 |
|---------|----------|---------|
| `ubuntu-24.04` | ubuntu | 24.04 |
| `ubuntu-22.04` | ubuntu | 22.04 |
| `ubuntu-20.04` | ubuntu | 20.04 |
| `debian-12` | debian | 12 |
| `debian-11` | debian | 11 |
| `centos-9` | centos, rhel, rocky, almalinux | 9 |

#### Darwin Bash 变体

| 变体名称 | 最低 Darwin 版本 |
|---------|----------------|
| `macos-15` | 24 |
| `macos-14` | 23 |
| `macos-13` | 22 |

### 5. 数据结构定义

```typescript
// src/types.ts

// Linux 变体配置
interface LinuxBashVariant {
  name: string;      // 变体标识，如 "ubuntu-24.04"
  ids: string[];     // 匹配的 OS ID 列表
  versions: string[]; // 匹配的版本前缀列表
}

// Darwin 变体配置
interface DarwinBashVariant {
  name: string;      // 变体标识，如 "macos-15"
  minDarwin: number; // 最低 Darwin 主版本号
}

// OS Release 解析结果
interface OsReleaseInfo {
  id: string;        // 发行版 ID，如 "ubuntu"
  idLike: string[];  // 衍生关系，如 ["debian"]
  versionId: string; // 版本号，如 "24.04"
}

// Bash 选择结果
interface BashSelection {
  path: string;      // 二进制完整路径
  variant: string;   // 选中的变体名称
}
```

---

## 关键代码路径与文件引用

### 测试文件

```
shell-tool-mcp/tests/
├── bashSelection.test.ts    # Bash 选择逻辑测试
└── osRelease.test.ts        # OS Release 解析测试
```

### 被测源码

```
shell-tool-mcp/src/
├── bashSelection.ts         # Bash 选择核心逻辑
├── constants.ts             # 平台变体配置
├── osRelease.ts             # OS Release 解析
├── types.ts                 # TypeScript 类型定义
├── platform.ts              # 目标三元组解析
└── index.ts                 # MCP 服务器入口
```

### 关键调用链

```
测试入口
├── bashSelection.test.ts
│   └── selectLinuxBash()
│       ├── 读取 LINUX_BASH_VARIANTS (constants.ts)
│       └── 返回 BashSelection (types.ts)
│   └── selectDarwinBash()
│       ├── 读取 DARWIN_BASH_VARIANTS (constants.ts)
│       └── 返回 BashSelection (types.ts)
│
└── osRelease.test.ts
    └── parseOsRelease()
        └── 返回 OsReleaseInfo (types.ts)
```

### 与上游的集成

```
shell-tool-mcp/src/index.ts (MCP 服务器)
    └── resolveBashPath() (bashSelection.ts)
        ├── Linux: readOsRelease() → selectLinuxBash()
        └── Darwin: selectDarwinBash()
```

### 与 Rust 侧的关联

```
codex-rs/shell-escalation/
├── src/unix/escalate_server.rs    # 实际使用选中的 Bash 路径
├── src/unix/escalate_protocol.rs  # EXEC_WRAPPER 协议定义
└── README.md                      # 架构文档
```

---

## 依赖与外部交互

### 1. 运行时依赖

| 依赖 | 用途 | 版本 |
|-----|------|------|
| `node:path` | 路径拼接 | Node.js 内置 |
| `node:os` | 获取 Darwin 版本 | Node.js 内置 |
| `node:fs` | 读取 /etc/os-release | Node.js 内置 |

### 2. 开发依赖

| 依赖 | 用途 | 版本 |
|-----|------|------|
| `jest` | 测试框架 | ^29.7.0 |
| `ts-jest` | TypeScript 支持 | ^29.3.4 |
| `@types/jest` | Jest 类型定义 | ^29.5.14 |
| `@types/node` | Node.js 类型定义 | ^20.19.18 |

### 3. 外部文件依赖

| 文件 | 用途 | 测试 Mock |
|-----|------|----------|
| `/etc/os-release` | Linux 发行版检测 | 测试中直接传入字符串内容 |
| `vendor/` 目录 | 预编译 Bash 二进制 | 测试中使用虚拟路径 `/vendor/bash` |

### 4. 与 MCP 协议的交互

虽然测试目录不直接测试 MCP 协议，但被测代码是 MCP 服务器的基础：

```
MCP Client (Codex CLI)
    ↓ MCP 协议
MCP Server (shell-tool-mcp)
    ↓ 调用
Bash Selection Logic (被测代码)
    ↓ 选择
Patched Bash Binary (vendor/)
    ↓ EXEC_WRAPPER 协议
Execve Wrapper (codex-rs/shell-escalation)
```

### 5. 与 Rust Shell Escalation 的关系

```
shell-tool-mcp (TypeScript)
├── 职责：选择正确的 Bash 二进制
└── 输出：Bash 路径

codex-rs/shell-escalation (Rust)
├── 职责：执行 EXEC_WRAPPER 协议
├── 职责：处理命令拦截和权限决策
└── 输入：使用 shell-tool-mcp 提供的 Bash 路径
```

---

## 风险、边界与改进建议

### 1. 当前风险

#### 1.1 测试覆盖不足

| 风险点 | 严重程度 | 说明 |
|-------|---------|------|
| 无实际 Bash 执行测试 | 中 | 仅测试选择逻辑，不验证二进制是否可用 |
| 无平台特定测试 | 中 | 测试在任意平台运行，不验证实际平台行为 |
| 无错误处理测试 | 低 | 未测试文件不存在、权限不足等异常情况 |

#### 1.2 代码边界情况

```typescript
// 潜在问题：当 LINUX_BASH_VARIANTS 为空数组时
const fallback = LINUX_BASH_VARIANTS[0];  // undefined
if (fallback) { ... }  // 有保护，但后续 throw 的 error 信息可能不准确
```

#### 1.3 版本匹配精度

```typescript
// 使用 startsWith 进行版本匹配
variant.versions.some((prefix) => versionId.startsWith(prefix))
// 问题："24.04.1" 匹配 "24.04" 是正确的
// 但 "24.10" 也会匹配 "24.04" 的前缀（如果配置错误）
```

### 2. 边界条件

#### 2.1 OS Release 解析边界

| 输入 | 当前行为 | 是否预期 |
|-----|---------|---------|
| 空字符串 | 返回 `{id: "", idLike: [], versionId: ""}` | ✓ |
| 无等号的行 | 被跳过 | ✓ |
| 多个等号 | 仅分割第一个 | ✓ |
| 嵌套引号 | 仅去除首尾引号 | ? |
| 特殊字符 | 原样保留 | ? |

#### 2.2 Bash 选择边界

| 场景 | 当前行为 |
|-----|---------|
| Linux 但无法读取 /etc/os-release | 回退到第一个变体 |
| Darwin 版本解析失败 | 使用 "0" 作为版本，触发回退 |
| 未知平台 | 抛出 Error |

### 3. 改进建议

#### 3.1 测试增强

```typescript
// 建议添加的测试用例

describe("selectLinuxBash edge cases", () => {
  it("handles empty os-release gracefully", () => {
    const info = { id: "", idLike: [], versionId: "" };
    const selection = selectLinuxBash(bashRoot, info);
    expect(selection.variant).toBe(LINUX_BASH_VARIANTS[0].name);
  });

  it("handles versionId with multiple dots", () => {
    const info = { id: "ubuntu", idLike: [], versionId: "24.04.1-LTS" };
    const selection = selectLinuxBash(bashRoot, info);
    expect(selection.variant).toBe("ubuntu-24.04");
  });

  it("prioritizes exact id match over idLike match", () => {
    // 需要验证当同时匹配 id 和 idLike 时的优先级
  });
});

describe("parseOsRelease edge cases", () => {
  it("handles inline comments", () => {
    // ID=ubuntu # this is a comment
  });

  it("handles escaped quotes", () => {
    // PRETTY_NAME="Ubuntu \"24.04\""
  });

  it("handles multiline values", () => {
    // 某些发行版可能有换行值
  });
});
```

#### 3.2 代码改进

```typescript
// 建议：更严格的版本匹配
function matchesVersion(versionId: string, prefixes: string[]): boolean {
  return prefixes.some(prefix => {
    // 确保是完整版本段匹配，而非前缀匹配
    const versionParts = versionId.split('.');
    const prefixParts = prefix.split('.');
    return prefixParts.every((part, i) => versionParts[i] === part);
  });
}
```

#### 3.3 架构改进建议

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 添加集成测试 | 高 | 验证实际 Bash 二进制可用性 |
| 支持运行时检测 | 中 | 通过 `ldd --version` 检测 glibc 版本 |
| 添加遥测 | 低 | 记录选择结果用于后续优化 |
| 支持用户覆盖 | 低 | 允许通过环境变量强制指定 Bash 路径 |

### 4. 与上游的协作点

#### 4.1 与 codex-rs/shell-escalation 的接口

当前接口：
```typescript
// shell-tool-mcp 输出
{ path: "/vendor/x86_64-unknown-linux-musl/bash/ubuntu-24.04/bash", variant: "ubuntu-24.04" }
```

建议的契约：
- 路径必须指向可执行文件
- 变体名称必须与 vendor 目录结构一致
- 需要文档化支持的最低 Bash 版本

#### 4.2 与 vendor 目录的依赖

```
vendor/
├── x86_64-unknown-linux-musl/
│   └── bash/
│       ├── ubuntu-24.04/
│       │   └── bash          # 测试假设此文件存在
│       ├── ubuntu-22.04/
│       │   └── bash
│       └── ...
```

风险：测试不验证 vendor 目录内容，实际部署时可能缺失文件。

---

## 附录：相关文档

### 内部文档

- `shell-tool-mcp/README.md` - 包的使用说明
- `codex-rs/shell-escalation/README.md` - Shell Escalation 架构
- `shell-tool-mcp/patches/bash-exec-wrapper.patch` - Bash 补丁

### 外部规范

- [freedesktop.org os-release 规范](https://www.freedesktop.org/software/systemd/man/latest/os-release.html)
- [MCP 协议规范](https://modelcontextprotocol.io/specification)

---

*文档生成时间：2026-03-22*
*研究范围：shell-tool-mcp/tests 目录及其直接依赖*
