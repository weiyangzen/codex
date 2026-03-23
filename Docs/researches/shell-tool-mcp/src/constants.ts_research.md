# constants.ts 研究文档

## 场景与职责

`constants.ts` 是 shell-tool-mcp 包的配置中心，集中管理所有支持的 Bash 二进制变体定义。该模块将操作系统发行版/版本与预编译 Bash 构建的映射关系进行显式声明，实现配置与选择逻辑的解耦。

**核心职责：**
1. 定义支持的 Linux 发行版变体列表（含 ID、版本约束）
2. 定义支持的 macOS 版本变体列表（含最低 Darwin 内核版本）
3. 作为单一数据源（SSOT）供 `bashSelection.ts` 消费

## 功能点目的

### 1. `LINUX_BASH_VARIANTS` - Linux Bash 变体配置

**目的：** 声明所有支持的 Linux 发行版及其对应的 Bash 构建。

**当前支持的变体（按优先级排序）：**

| 名称 | 匹配 ID | 匹配版本 | 典型发行版 |
|------|---------|----------|------------|
| `ubuntu-24.04` | `ubuntu` | `24.04` | Ubuntu 24.04 LTS (Noble) |
| `ubuntu-22.04` | `ubuntu` | `22.04` | Ubuntu 22.04 LTS (Jammy) |
| `ubuntu-20.04` | `ubuntu` | `20.04` | Ubuntu 20.04 LTS (Focal) |
| `debian-12` | `debian` | `12` | Debian 12 (Bookworm) |
| `debian-11` | `debian` | `11` | Debian 11 (Bullseye) |
| `centos-9` | `centos`, `rhel`, `rocky`, `almalinux` | `9` | RHEL 9 系（含兼容发行版）|

**设计考量：**
- **顺序即优先级**：数组顺序决定回退优先级，Ubuntu 24.04 作为最现代、最安全的默认
- **ID 别名支持**：`centos-9` 同时匹配多个 RHEL 系发行版，覆盖 Rocky Linux、AlmaLinux 等
- **版本前缀匹配**：`versions` 中的值作为前缀匹配，如 `"24.04"` 匹配 `"24.04.1"`

### 2. `DARWIN_BASH_VARIANTS` - macOS Bash 变体配置

**目的：** 声明支持的 macOS 版本及其对应的 Bash 构建。

**当前支持的变体（按优先级排序）：**

| 名称 | 最低 Darwin 版本 | 对应 macOS 版本 |
|------|------------------|-----------------|
| `macos-15` | 24 | macOS 15 (Sequoia) |
| `macos-14` | 23 | macOS 14 (Sonoma) |
| `macos-13` | 22 | macOS 13 (Ventura) |

**Darwin 版本映射关系：**
- Apple 使用 Darwin 内核版本作为内部标识
- 公开版本 = Darwin 主版本 - 9（近似）
- 例如：Darwin 24 → macOS 15

## 具体技术实现

### 类型定义

```typescript
// 来自 types.ts
LinuxBashVariant = {
  name: string;       // 变体标识符（目录名）
  ids: Array<string>; // 匹配的 /etc/os-release ID 列表
  versions: Array<string>; // 匹配的版本前缀列表
}

DarwinBashVariant = {
  name: string;       // 变体标识符（目录名）
  minDarwin: number;  // 最低 Darwin 主版本号
}
```

### 不可变性保证

```typescript
export const LINUX_BASH_VARIANTS: ReadonlyArray<LinuxBashVariant> = [...];
export const DARWIN_BASH_VARIANTS: ReadonlyArray<DarwinBashVariant> = [...];
```

使用 `ReadonlyArray` 确保：
1. 运行时防止意外修改
2. 编译时类型检查捕获修改尝试
3. 明确表达"配置只读"的意图

## 关键代码路径与文件引用

### 消费者

| 常量 | 消费者 | 用途 |
|------|--------|------|
| `LINUX_BASH_VARIANTS` | `bashSelection.ts` | `selectLinuxBash()` 遍历匹配 |
| `DARWIN_BASH_VARIANTS` | `bashSelection.ts` | `selectDarwinBash()` 遍历匹配 |
| 两者 | `bashSelection.test.ts` | 测试断言回退行为 |

### 类型依赖

- **`./types`**：导入 `LinuxBashVariant` 和 `DarwinBashVariant` 类型

### 间接引用

- **`README.md`**：第 50 行提及 `bashSelection.ts`，引导读者查看选择逻辑

## 依赖与外部交互

### 构建时依赖

本模块为纯数据配置，无运行时依赖。

### 与构建系统的关联

`vendor/` 目录结构必须与这些常量保持同步：
```
vendor/
├── x86_64-unknown-linux-musl/
│   └── bash/
│       ├── ubuntu-24.04/bash
│       ├── ubuntu-22.04/bash
│       ├── debian-12/bash
│       └── centos-9/bash
└── aarch64-apple-darwin/
    └── bash/
        ├── macos-15/bash
        └── macos-14/bash
```

**注意：** 实际 `vendor` 目录在源码仓库中不存在（见 `.gitignore`），由 CI/CD 或发布流程填充。

## 风险、边界与改进建议

### 已知风险

1. **配置与二进制不同步**
   - 若添加新变体到此文件但未构建对应二进制，运行时会因文件不存在而失败
   - 当前无构建时验证机制确保 `vendor/` 结构与常量一致

2. **Ubuntu 优先级的争议性**
   - 当前将 Ubuntu 24.04 作为最高优先级可能不适合企业环境
   - RHEL/CentOS 用户可能期望 `centos-9` 作为默认

3. **版本号硬编码**
   - 新版本发布（如 Ubuntu 26.04）需要手动更新此文件
   - 无自动化机制检测新发行版发布

4. **musl 构建的兼容性假设**
   - 所有 Linux 变体使用 musl libc 构建，理论上可在任何 Linux 运行
   - 但实际可能依赖特定内核特性或 `/etc` 文件布局

### 边界情况

| 场景 | 影响 | 当前状态 |
|------|------|----------|
| 新发行版（如 Ubuntu 26.04） | 回退到 24.04 构建 | 可运行但非最优 |
| 旧发行版（如 CentOS 7） | 回退到 centos-9 构建 | glibc 兼容风险 |
| 未知 ID（如 `arch`） | 回退到第一个变体 | 可能运行但无保障 |
| macOS 16 发布 | 回退到 macos-15 构建 | 需更新常量 |

### 改进建议

1. **添加验证脚本**
   ```typescript
   // 建议：构建时检查 vendor/ 结构与常量一致
   export function validateVariants(vendorPath: string): boolean {
     for (const variant of LINUX_BASH_VARIANTS) {
       const binaryPath = path.join(vendorPath, 'bash', variant.name, 'bash');
       if (!fs.existsSync(binaryPath)) {
         throw new Error(`Missing binary for variant: ${variant.name}`);
       }
     }
   }
   ```

2. **支持更多发行版**
   - 添加 `fedora-40`（新兴企业选择）
   - 添加 `alpine-3.x`（容器环境常见）
   - 考虑 `arch` 的滚动发布模型（无版本号）

3. **版本匹配策略优化**
   ```typescript
   // 当前：前缀匹配
   versions: ["24.04"]
   // 建议：支持范围或语义化版本
   versions: [">=20.04", "<26.04"]
   ```

4. **动态配置支持**
   - 考虑从外部 JSON 文件加载变体配置
   - 允许用户通过环境变量扩展变体列表

5. **文档化变体选择理由**
   - 为何选择这些特定版本？
   - 每个变体的 glibc/musl 基线是什么？
   - 添加注释说明每个变体的支持生命周期

### 维护清单

当添加新变体时，需同步更新：
- [ ] `constants.ts` - 添加变体定义
- [ ] `bashSelection.test.ts` - 添加对应测试用例
- [ ] `README.md` - 更新支持的发行版列表
- [ ] CI/CD 构建配置 - 添加新变体的交叉编译
- [ ] 发布流程 - 确保新二进制包含在包中
