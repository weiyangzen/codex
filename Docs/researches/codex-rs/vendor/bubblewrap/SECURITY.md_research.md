# SECURITY.md 研究文档

## 场景与职责

`SECURITY.md` 是 bubblewrap 项目的安全政策文件，定义了安全漏洞的报告流程、安全边界说明以及漏洞披露政策。该文件面向安全研究人员、用户和项目维护者，建立了负责任的安全漏洞披露框架。

## 功能点目的

1. **漏洞报告指南**：指导安全研究人员如何报告漏洞
2. **安全边界定义**：明确说明项目的安全保证范围
3. **披露政策**：规定漏洞披露的时间线和流程
4. **历史参考**：引用已知 CVE 作为安全边界示例
5. **责任划分**：明确 bubblewrap 与调用者的安全责任

## 具体技术实现

### 文件结构

```markdown
## Security and Disclosure Information Policy for the bubblewrap Project

### System security
- setuid root 场景下的安全目标
- CVE-2020-5291 示例

### Sandbox security
- bubblewrap 作为工具包的定位
- CVE-2017-5226 示例（调用者责任）
```

### 核心内容解析

#### 1. 安全政策引用模式

```markdown
The bubblewrap Project follows the [Security and Disclosure Information Policy](https://github.com/containers/common/blob/HEAD/SECURITY.md) for the Containers Projects.
```

与 `CODE-OF-CONDUCT.md` 类似，采用引用上游政策的方式：
- **优势**：与容器生态其他项目保持一致，减少维护负担
- **内容**：包含漏洞报告流程、披露时间线、安全公告发布等

#### 2. 系统安全（System Security）

**安全目标定义**
```markdown
If bubblewrap is setuid root, then the goal is that it does not allow
a malicious local user to do anything that would not have been possible
on a kernel that allows unprivileged users to create new user namespaces.
```

**核心原则**：
- setuid root 场景：安全边界等价于 user namespaces 内核
- 非 setuid 场景：不构成安全边界（用户可自行编写等效工具）

**CVE-2020-5291 案例研究**
```markdown
For example, CVE-2020-5291 was treated as a security vulnerability in bubblewrap.
```

- **漏洞性质**：GitHub Security Advisory GHSA-j2qp-rvxj-43vj
- **处理态度**：确认为安全漏洞并修复
- **意义**：确立了 setuid 场景下的安全责任边界

#### 3. 沙箱安全（Sandbox Security）

**工具包定位**
```markdown
bubblewrap is a toolkit for constructing sandbox environments.
bubblewrap is not a complete, ready-made sandbox with a specific security policy.
```

**责任划分模型**

```
┌─────────────────────────────────────────┐
│  调用者 (Flatpak, 脚本等)                │
│  - 定义安全模型                          │
│  - 选择命令行参数                        │
│  - 承担安全策略责任                      │
├─────────────────────────────────────────┤
│  bubblewrap                             │
│  - 提供沙箱构建原语                      │
│  - 确保自身实现安全                      │
│  - 不定义具体安全策略                    │
└─────────────────────────────────────────┘
```

**CVE-2017-5226 案例研究**
```markdown
For example, CVE-2017-5226 (in which a Flatpak app could send input
to a parent terminal using the TIOCSTI ioctl) is considered to be
a Flatpak vulnerability, not a bubblewrap vulnerability.
```

- **漏洞描述**：Flatpak 应用可通过 TIOCSTI ioctl 向父终端发送输入
- **责任归属**：Flatpak（调用者）而非 bubblewrap
- **原因**：bubblewrap 提供 `--new-session` 选项，但 Flatpak 未使用
- **安全边界**：调用者负责正确使用 bubblewrap 提供的安全机制

## 关键代码路径与文件引用

- **文件位置**: `codex-rs/vendor/bubblewrap/SECURITY.md`
- **引用目标**: https://github.com/containers/common/blob/HEAD/SECURITY.md
- **关联文件**:
  - `CODE-OF-CONDUCT.md` - 同样引用上游
  - `README.md` - 安全相关说明
  - GitHub Security Advisories - 漏洞公告

### 相关 CVE 链接

| CVE | 描述 | 归属 |
|-----|------|------|
| CVE-2020-5291 | setuid 场景下的安全漏洞 | bubblewrap |
| CVE-2017-5226 | TIOCSTI 终端注入 | Flatpak（调用者） |
| CVE-2016-3135 | user namespaces 相关（提及） | Linux 内核 |

## 依赖与外部交互

### 外部依赖

- **Containers 项目**: 安全政策定义者
- **GitHub Security Advisories**: 漏洞披露平台
- **MITRE**: CVE 编号分配

### 交互流程

```
安全研究人员
      │
      ▼
发现潜在漏洞
      │
      ▼
参考 SECURITY.md 报告
      │
      ▼
维护者评估
      │
      ├──► bubblewrap 漏洞 ──► 修复 + CVE
      │
      └──► 调用者责任 ──► 转交相关项目
```

## 风险、边界与改进建议

### 风险

1. **报告渠道不明确**
   - 仅引用上游政策，未提供项目特定联系方式
   - 可能导致报告者困惑

2. **响应时间未承诺**
   - 未明确漏洞响应时间承诺
   - 可能影响负责任披露的执行

3. **漏洞分类模糊**
   - 某些场景下难以区分 bubblewrap 与调用者责任
   - 可能导致争议

### 边界

- 不涵盖物理安全
- 不涵盖社会工程学攻击
- 不涵盖依赖项（内核、libc）的漏洞
- 不保证沙箱内的应用安全（仅保证与宿主机的隔离）

### 改进建议

1. **添加项目特定联系信息**
   ```markdown
   ## Reporting a Vulnerability
   
   For general policy, see [Containers Security Policy](...).
   
   For bubblewrap-specific reports:
   - Email: security@example.com (加密选项)
   - GitHub Private Vulnerability Reporting
   
   Expected response time: 48 hours (acknowledgment), 90 days (fix)
   ```

2. **漏洞分类指南**
   ```markdown
   ## Vulnerability Classification
   
   ### In Scope (bubblewrap responsibility)
   - setuid 二进制中的权限提升
   - 命名空间逃逸
   - 命令行参数解析中的缓冲区溢出
   
   ### Out of Scope (caller responsibility)
   - 不当使用 --bind 挂载敏感目录
   - 未使用 --new-session 导致的 TIOCSTI
   - seccomp 规则配置不当
   ```

3. **安全加固建议**
   ```markdown
   ## Security Hardening Recommendations
   
   For callers building sandboxes with bubblewrap:
   
   1. Always use `--new-session` unless you have specific reasons not to
   2. Apply seccomp filters to block TIOCSTI
   3. Use minimal bind mounts
   4. Enable user namespaces when available (avoid setuid)
   ```

4. **安全审计信息**
   ```markdownn   ## Security Audit History
   
   - 2023: [Audit by XXX](link) - [Results](link)
   - 2021: [Audit by YYY](link) - [Results](link)
   ```

5. **漏洞赏金计划**
   考虑加入 [GitHub Security Lab](https://securitylab.github.com/) 或类似计划

6. **安全相关配置**
   ```markdown
   ## Security-Related Configuration
   
   ### Disabling setuid (recommended when user namespaces available)
   chmod u-s /usr/bin/bwrap
   
   ### Checking for user namespace support
   unshare --user --pid echo "User namespaces supported"
   ```

## 与项目整体的关系

### 在开源治理中的位置

```
安全治理体系
├── SECURITY.md (本文件) - 漏洞报告和披露政策
├── CODE-OF-CONDUCT.md - 社区行为规范
├── COPYING - 法律许可
├── src/ - 安全敏感代码
│   ├── bubblewrap.c - 主程序
│   ├── bind-mount.c - 挂载操作
│   └── ...
└── .github/ - 安全工作流程
```

### 对 bubblewrap 的特殊意义

作为 setuid root 工具，安全是 bubblewrap 的核心关切：

1. **信任基础**
   - 用户必须信任 setuid 二进制不会滥用权限
   - 透明的安全政策有助于建立信任

2. **审计友好**
   - 明确的安全边界便于安全审计
   - 历史 CVE 处理展示安全响应能力

3. **生态责任**
   - 明确与调用者的责任划分
   - 避免安全问题的责任推诿

## 相关资源

- [Containers Security Policy](https://github.com/containers/common/blob/HEAD/SECURITY.md)
- [GitHub Security Advisories for bubblewrap](https://github.com/containers/bubblewrap/security/advisories)
- [CVE-2020-5291](https://github.com/containers/bubblewrap/security/advisories/GHSA-j2qp-rvxj-43vj)
- [CVE-2017-5226](https://github.com/flatpak/flatpak/security/advisories/GHSA-7gfv-rvfx-h87x)
- [Responsible Disclosure](https://en.wikipedia.org/wiki/Responsible_disclosure)
