# zstd (DotSlash 文件) 深度研究文档

## 场景与职责

`.github/workflows/zstd` 是一个 **DotSlash 配置文件**，用于在 Windows 运行器上提供 `zstd` 压缩工具。它是 Codex 项目发布流程中 Windows 制品压缩的关键依赖。

### 文件性质
- **类型**: DotSlash 配置文件 (JSON 格式，带 shebang)
- **用途**: 包装 zstd 二进制，提供跨平台一致的压缩接口
- **目标平台**: Windows x86_64 和 aarch64

### 核心职责
1. **提供 zstd 工具**: 在 Windows 运行器上无需手动安装即可使用 zstd
2. **版本锁定**: 固定使用 zstd v1.5.7
3. **完整性验证**: 通过 SHA256 校验确保二进制安全
4. **多架构支持**: 支持 Windows x64 和 ARM64 (通过 x64 模拟)

---

## 功能点目的

### 1. DotSlash 机制
**DotSlash** 是 Meta 开发的工具，用于：
- 将可执行文件声明为配置文件
- 自动下载和缓存依赖的二进制
- 提供跨平台的统一调用接口

**Shebang 行**:
```bash
#!/usr/bin/env dotslash
```
允许直接执行该文件，DotSlash 会自动解析配置并启动正确的二进制。

### 2. Windows 平台支持
| 平台 | 架构 | 说明 |
|------|------|------|
| windows-x86_64 | x64 | 原生支持 |
| windows-aarch64 | ARM64 | 通过 x64 模拟运行 |

### 3. 二进制来源
- **上游**: Facebook zstd 官方发布
- **版本**: v1.5.7
- **格式**: ZIP 压缩包
- **校验**: SHA256 验证

---

## 具体技术实现

### 配置文件结构

```json
{
  "name": "zstd",
  "platforms": {
    "windows-x86_64": { ... },
    "windows-aarch64": { ... }
  }
}
```

### 平台配置详解

#### windows-x86_64
```json
{
  "size": 1747181,           // 文件大小 (字节)
  "hash": "sha256",          // 哈希算法
  "digest": "acb4e811...",   // SHA256 校验值
  "format": "zip",           // 压缩格式
  "path": "zstd-v1.5.7-win64/zstd.exe",  // 可执行文件路径
  "providers": [             // 下载源
    {
      "url": "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-v1.5.7-win64.zip"
    },
    {
      "type": "github-release",
      "repo": "facebook/zstd",
      "tag": "v1.5.7",
      "name": "zstd-v1.5.7-win64.zip"
    }
  ]
}
```

#### windows-aarch64
配置与 x86_64 完全相同，使用相同的 win64 二进制，通过 Windows 的 x64 模拟层运行。

### 使用方式

#### 在工作流中调用
```yaml
# rust-release-windows.yml
- name: Compress artifacts
  shell: bash
  run: |
    "${GITHUB_WORKSPACE}/.github/workflows/zstd" -T0 -19 "$dest/$base"
```

#### 命令行参数
- `-T0`: 自动检测并使用所有可用 CPU 核心
- `-19`: 使用最高压缩级别 (1-19)

### 下载策略

DotSlash 按顺序尝试 providers：
1. 直接 URL 下载
2. GitHub Release API 下载

如果第一个失败，自动尝试第二个。

---

## 关键代码路径与文件引用

### 本文件
| 文件 | 作用 |
|------|------|
| `.github/workflows/zstd` | DotSlash 配置 (本文件) |

### 调用方
| 文件 | 作用 |
|------|------|
| `.github/workflows/rust-release-windows.yml` | Windows 发布工作流 |
| `.github/workflows/rust-release.yml` | 主发布工作流 (Linux/macOS 使用系统 zstd) |

### DotSlash 配置
| 文件 | 作用 |
|------|------|
| `.github/dotslash-config.json` | DotSlash 发布配置 |

---

## 依赖与外部交互

### 外部服务
| 服务 | 用途 |
|------|------|
| GitHub Releases | zstd 二进制下载源 |
| facebook/zstd | 上游项目 |

### 依赖工具
| 工具 | 用途 |
|------|------|
| DotSlash | 配置文件解析和执行 |
| zstd v1.5.7 | 压缩工具 |

### 上游信息
- **项目**: https://github.com/facebook/zstd
- **版本**: v1.5.7
- **发布页**: https://github.com/facebook/zstd/releases/tag/v1.5.7
- **Windows 二进制**: zstd-v1.5.7-win64.zip

---

## 风险、边界与改进建议

### 已知风险

#### 1. 外部依赖可用性
- **风险**: GitHub 下载可能失败或缓慢
- **影响**: Windows 构建失败
- **缓解**: 双 provider 配置，支持回退

#### 2. 版本固定
- **风险**: v1.5.7 可能存在未修复的漏洞
- **建议**: 定期更新到最新版本

#### 3. ARM64 模拟性能
- **风险**: ARM64 使用 x64 模拟，性能较低
- **影响**: 压缩速度较慢
- **建议**: 监控实际性能，考虑原生 ARM64 构建

### 边界条件

#### 1. 仅 Windows 使用
- Linux 和 macOS 运行器通常预装 zstd
- 此文件仅在 Windows 工作流中使用

#### 2. 压缩级别
- 当前使用 `-19` 最高压缩
- 可能牺牲速度换取压缩率

#### 3. 文件大小限制
- 单个文件大小: 1,747,181 字节 (约 1.7 MB)
- 解压后大小: 更大

### 改进建议

#### 1. 版本更新
```json
// 升级到 v1.5.8 或更新版本
{
  "tag": "v1.5.8",
  "name": "zstd-v1.5.8-win64.zip"
}
```

#### 2. 添加更多镜像
```json
"providers": [
  {
    "url": "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-v1.5.7-win64.zip"
  },
  {
    "url": "https://mirror.example.com/zstd-v1.5.7-win64.zip"
  },
  {
    "type": "github-release",
    "repo": "facebook/zstd",
    "tag": "v1.5.7",
    "name": "zstd-v1.5.7-win64.zip"
  }
]
```

#### 3. 缓存优化
```yaml
# 在工作流中添加缓存
- name: Cache DotSlash
  uses: actions/cache@v3
  with:
    path: ~/.dotslash
    key: dotslash-${{ hashFiles('.github/workflows/zstd') }}
```

#### 4. 校验增强
```json
{
  "hash": "sha256",
  "digest": "acb4e8111511749dc7a3ebedca9b04190e37a17afeb73f55d4425dbf0b90fad9"
}
```
已配置 SHA256 校验，确保二进制完整性。

#### 5. 添加 Linux/macOS 配置
虽然当前不需要，但可以考虑统一配置：
```json
{
  "platforms": {
    "linux-x86_64": { ... },
    "linux-aarch64": { ... },
    "macos-x86_64": { ... },
    "macos-aarch64": { ... },
    "windows-x86_64": { ... },
    "windows-aarch64": { ... }
  }
}
```

---

## 附录: DotSlash 简介

### 什么是 DotSlash?
DotSlash 是 Meta 开源的工具，允许将可执行文件依赖声明为 JSON 配置文件。

### 核心特性
1. **可版本控制**: 配置文件可以提交到 Git
2. **跨平台**: 支持多平台声明
3. **自动下载**: 首次使用时自动获取二进制
4. **缓存**: 下载的二进制会被缓存复用
5. **校验**: 支持多种哈希校验

### 使用示例
```bash
# 直接执行 DotSlash 文件
./.github/workflows/zstd --version

# DotSlash 会自动:
# 1. 解析 JSON 配置
# 2. 检测当前平台
# 3. 下载对应二进制 (如果不存在)
# 4. 验证哈希
# 5. 执行二进制
```

### 相关链接
- DotSlash GitHub: https://github.com/facebook/dotslash
- zstd 项目: https://github.com/facebook/zstd
