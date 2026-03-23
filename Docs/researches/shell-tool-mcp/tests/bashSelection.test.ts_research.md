# bashSelection.test.ts 研究文档

## 场景与职责

`bashSelection.test.ts` 是 shell-tool-mcp 项目中负责测试 Bash 二进制文件选择逻辑的核心测试文件。该测试模块确保 MCP (Model Context Protocol) 服务器能够根据宿主操作系统的类型和版本，智能选择最合适的预编译 Bash 可执行文件。

在 Codex CLI 的架构中，shell-tool-mcp 提供了一个沙箱化的 Bash 环境，用于安全地执行 shell 命令。由于不同 Linux 发行版和 macOS 版本之间存在 ABI 兼容性差异，项目需要为不同目标平台（Ubuntu、Debian、CentOS/RHEL、macOS 等）提供特定的 Bash 二进制文件。本测试文件验证选择逻辑的正确性。

## 功能点目的

测试文件覆盖两个核心函数：

1. **`selectLinuxBash`** - Linux 平台的 Bash 选择逻辑
   - 验证精确版本匹配（如 Ubuntu 24.04 选择 ubuntu-24.04 变体）
   - 验证回退机制（当无匹配时选择第一个支持的变体）

2. **`selectDarwinBash`** - macOS 平台的 Bash 选择逻辑
   - 验证基于 Darwin 内核版本的兼容性选择
   - 验证旧版本系统的回退机制

## 具体技术实现

### 测试框架与配置

- **测试框架**: Jest (通过 ts-jest 支持 TypeScript)
- **配置位置**: `jest.config.cjs`
- **测试环境**: Node.js

### 关键测试用例分析

#### Linux 平台测试

```typescript
// 测试用例1: 精确版本匹配
const info: OsReleaseInfo = {
  id: "ubuntu",
  idLike: ["debian"],
  versionId: "24.04.1",  // 实际版本可能包含补丁号
};
// 期望选择 ubuntu-24.04 变体（前缀匹配）
expect(selection.variant).toBe("ubuntu-24.04");
```

匹配逻辑：
- 通过 `id` 或 `idLike` 数组匹配发行版家族
- 通过 `versionId` 前缀匹配确定具体版本（如 "24.04.1" 匹配 "24.04" 前缀）

```typescript
// 测试用例2: 无匹配时的回退
const info: OsReleaseInfo = { id: "unknown", idLike: [], versionId: "1.0" };
// 回退到 LINUX_BASH_VARIANTS[0]（当前为 ubuntu-24.04）
expect(selection.variant).toBe(LINUX_BASH_VARIANTS[0].name);
```

#### macOS 平台测试

```typescript
// 测试用例1: Darwin 24.x 选择 macOS 15
const darwinRelease = "24.0.0";  // Darwin 24.x 对应 macOS 15
expect(selection.variant).toBe("macos-15");

// 测试用例2: 旧版本回退
const darwinRelease = "20.0.0";  // Darwin 20.x 对应 macOS 11
// 回退到 DARWIN_BASH_VARIANTS[0]（当前为 macos-15）
expect(selection.variant).toBe(DARWIN_BASH_VARIANTS[0].name);
```

Darwin 版本映射关系：
- Darwin 24+ → macOS 15
- Darwin 23+ → macOS 14
- Darwin 22+ → macOS 13

### 数据结构依赖

测试依赖以下核心类型定义（来自 `src/types.ts`）：

```typescript
// 操作系统发行版信息
interface OsReleaseInfo {
  id: string;           // 发行版 ID，如 "ubuntu"
  idLike: string[];     // 相关发行版家族，如 ["debian"]
  versionId: string;    // 版本号，如 "24.04"
}

// Bash 选择结果
interface BashSelection {
  path: string;         // 二进制文件完整路径
  variant: string;      // 变体名称，如 "ubuntu-24.04"
}
```

### 变体配置（来自 `src/constants.ts`）

```typescript
// Linux 支持的变体列表（按优先级排序）
const LINUX_BASH_VARIANTS = [
  { name: "ubuntu-24.04", ids: ["ubuntu"], versions: ["24.04"] },
  { name: "ubuntu-22.04", ids: ["ubuntu"], versions: ["22.04"] },
  { name: "ubuntu-20.04", ids: ["ubuntu"], versions: ["20.04"] },
  { name: "debian-12", ids: ["debian"], versions: ["12"] },
  { name: "debian-11", ids: ["debian"], versions: ["11"] },
  { name: "centos-9", ids: ["centos", "rhel", "rocky", "almalinux"], versions: ["9"] },
];

// macOS 支持的变体列表
const DARWIN_BASH_VARIANTS = [
  { name: "macos-15", minDarwin: 24 },
  { name: "macos-14", minDarwin: 23 },
  { name: "macos-13", minDarwin: 22 },
];
```

## 关键代码路径与文件引用

### 被测代码

| 文件路径 | 职责 |
|---------|------|
| `src/bashSelection.ts` | 核心选择逻辑实现 |
| `src/constants.ts` | 支持的 Bash 变体配置 |
| `src/types.ts` | TypeScript 类型定义 |

### 测试文件结构

```
shell-tool-mcp/tests/
├── bashSelection.test.ts  # 本测试文件
└── osRelease.test.ts      # 相关：OS 信息解析测试
```

### 核心函数调用链

```
index.ts (入口)
  └── resolveBashPath()
        ├── selectLinuxBash()   # Linux 平台
        └── selectDarwinBash()  # macOS 平台
```

### 选择算法流程

```
selectLinuxBash(bashRoot, osInfo):
  1. 遍历 LINUX_BASH_VARIANTS
  2. 检查 id 匹配: variant.ids.includes(info.id) || variant.ids.some(id => info.idLike.includes(id))
  3. 检查版本匹配: versionId.startsWith(prefix)
  4. 优先返回 matchesVersion=true 的候选
  5. 其次返回仅 matchesId 的候选
  6. 最后回退到 LINUX_BASH_VARIANTS[0]

selectDarwinBash(bashRoot, darwinRelease):
  1. 解析主版本号: parseInt(darwinRelease.split(".")[0])
  2. 查找满足 darwinMajor >= variant.minDarwin 的变体
  3. 返回匹配的变体或回退到 DARWIN_BASH_VARIANTS[0]
```

## 依赖与外部交互

### 内部依赖

| 模块 | 导入内容 | 用途 |
|------|---------|------|
| `../src/bashSelection` | `selectDarwinBash`, `selectLinuxBash` | 被测函数 |
| `../src/constants` | `DARWIN_BASH_VARIANTS`, `LINUX_BASH_VARIANTS` | 验证回退变体 |
| `../src/types` | `OsReleaseInfo` | 类型定义 |
| `node:path` | `path` | 路径拼接验证 |

### 外部系统交互

测试为纯单元测试，不涉及外部系统交互：
- 不读取实际 `/etc/os-release` 文件
- 不访问文件系统
- 不执行子进程

所有测试使用模拟数据（mock data）进行验证。

## 风险、边界与改进建议

### 当前风险点

1. **回退策略过于激进**
   - 当无法识别发行版时，直接回退到 `LINUX_BASH_VARIANTS[0]`（ubuntu-24.04）
   - 风险：在不兼容的 Linux 发行版上可能导致运行时错误

2. **版本匹配精度**
   - 使用字符串前缀匹配（`startsWith`）处理版本号
   - 边界案例：`"24.04.1"` 匹配 `"24.04"` 是预期行为，但 `"24.04.10"` 也会匹配

3. **Darwin 版本映射硬编码**
   - macOS 版本与 Darwin 版本的映射关系（24→15, 23→14...）是硬编码的
   - 需要手动维护更新

4. **测试覆盖不完整**
   - 缺少对 `resolveBashPath` 的测试
   - 缺少对 `idLike` 匹配优先级的测试
   - 缺少对空/无效输入的错误处理测试

### 边界情况

| 场景 | 当前行为 | 建议 |
|------|---------|------|
| `versionId` 为空字符串 | 无法匹配任何版本，进入回退逻辑 | 应明确处理 |
| `idLike` 包含多个匹配 | 选择第一个匹配的变体 | 需要定义明确优先级 |
| Darwin 版本解析失败 | 回退到 `parseInt("0")` | 应显式报错 |
| 变体数组为空 | 抛出异常（无法构造错误消息） | 添加前置检查 |

### 改进建议

1. **增强测试覆盖**
   ```typescript
   // 建议添加的测试用例
   - 测试 idLike 优先级（如 Rocky Linux 应匹配 centos-9）
   - 测试 versionId 为空的情况
   - 测试 resolveBashPath 的跨平台行为
   - 测试不支持的 platform（如 win32）的错误处理
   ```

2. **改进版本匹配逻辑**
   - 考虑使用语义化版本比较（semver）替代字符串前缀匹配
   - 添加版本号格式验证

3. **添加日志记录**
   - 在选择过程中记录决策原因（为什么选择了某个变体）
   - 便于调试用户报告的问题

4. **支持更多发行版**
   - 当前仅支持 Ubuntu、Debian、CentOS-like
   - 可考虑添加 Alpine、Arch 等发行版支持

5. **运行时验证**
   - 在回退到默认变体后，添加二进制文件存在性检查
   - 提前发现部署问题而非运行时失败

### 相关文档

- [shell-tool-mcp README](../README.md) - 项目整体说明
- [Codex .rules 文档](https://developers.openai.com/codex/local-config#rules-preview) - 沙箱规则配置
- [MCP 协议规范](https://modelcontextprotocol.io/) - Model Context Protocol 规范
