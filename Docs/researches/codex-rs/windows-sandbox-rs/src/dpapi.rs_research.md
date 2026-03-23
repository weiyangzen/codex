# dpapi.rs 研究文档

## 场景与职责

`dpapi.rs` 提供 Windows 数据保护 API（DPAPI - Data Protection API）的封装，用于加密和解密敏感数据。这是 Windows 沙箱中凭证安全存储的核心组件。

该模块在以下场景中使用：
- 沙箱用户密码的加密存储（`identity.rs`）
- 敏感配置数据的保护
- 确保只有同一机器上的进程能解密数据

## 功能点目的

### 1. 数据加密
- **`protect`**: 使用 DPAPI 加密数据
- 使用 `CryptProtectData` API
- 配置为机器范围（`CRYPTPROTECT_LOCAL_MACHINE`）

### 2. 数据解密
- **`unprotect`**: 使用 DPAPI 解密数据
- 使用 `CryptUnprotectData` API
- 支持机器范围的加密数据

### 3. 无 UI 操作
- 使用 `CRYPTPROTECT_UI_FORBIDDEN` 标志
- 防止在加密/解密过程中弹出用户界面
- 适合后台/服务场景

## 具体技术实现

### 关键数据结构

```rust
// CRYPT_INTEGER_BLOB 是 DPAPI 的数据容器
fn make_blob(data: &[u8]) -> CRYPT_INTEGER_BLOB {
    CRYPT_INTEGER_BLOB {
        cbData: data.len() as u32,
        pbData: data.as_ptr() as *mut u8,  // 注意：API 实际上不会修改，但需要可变指针
    }
}
```

### 加密流程

```
protect(data)
  └─> make_blob(data) -> CRYPT_INTEGER_BLOB
  └─> CryptProtectData(
        &mut in_blob,           // 输入数据
        null,                   // 描述字符串（可选）
        null,                   // 熵（可选的额外密钥材料）
        null_mut(),             // 保留
        null_mut(),             // 提示结构（可选）
        CRYPTPROTECT_UI_FORBIDDEN | CRYPTPROTECT_LOCAL_MACHINE,
        &mut out_blob           // 输出加密数据
      )
  └─> 如果失败: 返回错误（GetLastError）
  └─> 复制 out_blob 数据到 Vec<u8>
  └─> LocalFree(out_blob.pbData)  // 释放 DPAPI 分配的内存
  └─> 返回加密数据
```

### 解密流程

```
unprotect(blob)
  └─> make_blob(blob) -> CRYPT_INTEGER_BLOB
  └─> CryptUnprotectData(
        &mut in_blob,           // 输入加密数据
        null_mut(),             // 输出描述字符串（不需要）
        null,                   // 熵（必须与加密时相同）
        null_mut(),             // 保留
        null_mut(),             // 提示结构
        CRYPTPROTECT_UI_FORBIDDEN | CRYPTPROTECT_LOCAL_MACHINE,
        &mut out_blob           // 输出明文数据
      )
  └─> 如果失败: 返回错误（GetLastError）
  └─> 复制 out_blob 数据到 Vec<u8>
  └─> LocalFree(out_blob.pbData)
  └─> 返回明文数据
```

### 保护标志

```rust
const CRYPTPROTECT_LOCAL_MACHINE: u32 = 0x4;      // 机器范围（非用户范围）
const CRYPTPROTECT_UI_FORBIDDEN: u32 = 0x1;       // 禁止 UI
```

使用 `LOCAL_MACHINE` 的原因：
- 沙箱可能在不同用户上下文运行（提升/非提升）
- 机器范围允许同一机器上的任何进程解密
- 不需要用户配置文件加载

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `identity.rs` | `dpapi::unprotect` | 解密沙箱用户密码 |
| `setup_orchestrator.rs` | `dpapi::protect` | 加密沙箱用户密码 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/dpapi.rs
  ├─> 被 lib.rs 公开导出: dpapi_protect, dpapi_unprotect
  ├─> 被 identity.rs 使用 (unprotect)
  └─> Windows API: Win32::Security::Cryptography
```

## 依赖与外部交互

### 内部依赖
- 无内部模块依赖

### 外部依赖
- **windows-sys**: Windows API 绑定
  - `Win32::Security::Cryptography`: DPAPI 函数
  - `Win32::Foundation`: 错误处理和内存管理

### Windows API 使用

| API | 用途 |
|-----|------|
| `CryptProtectData` | 加密数据 |
| `CryptUnprotectData` | 解密数据 |
| `LocalFree` | 释放 DPAPI 分配的内存 |
| `GetLastError` | 获取错误码 |

### 数据格式

DPAPI 加密数据包含：
- 加密的数据本身
- 加密密钥（使用机器主密钥加密）
- 可选的熵和描述信息

数据格式是私有的，由 Windows 管理。

## 风险、边界与改进建议

### 安全风险

1. **机器范围风险**
   - `CRYPTPROTECT_LOCAL_MACHINE` 允许同一机器上任何进程解密
   - 如果机器被入侵，攻击者可以解密沙箱密码
   - 但这是权衡：需要支持提升/非提升进程共享

2. **内存安全**
   - `make_blob` 使用 `as *mut u8` 转换不可变引用
   - 标记 `#[allow(clippy::unnecessary_mut_passed)]` 抑制警告
   - 实际上 DPAPI 不会修改输入数据，但 API 签名要求可变指针

3. **内存清理**
   - 解密后的明文存储在 `Vec<u8>` 中
   - 没有显式清零内存，可能被交换到磁盘
   - Rust 的 `Drop` 不会清零内存

4. **错误信息泄露**
   - 错误消息包含 `GetLastError` 码
   - 可能泄露系统状态信息

### 边界条件

| 边界 | 处理 |
|------|------|
| 空数据 | 正常处理（返回空加密块） |
| 大数据 | 受限于可用内存 |
| 损坏数据 | `CryptUnprotectData` 失败，返回错误 |
| 跨机器 | 解密失败（密钥绑定到机器） |
| 非 Windows | 模块被条件编译排除 |

### 改进建议

1. **内存清零**
   ```rust
   // 当前: 直接返回 Vec<u8>
   // 建议: 使用 zeroize crate 确保敏感数据清零
   use zeroize::Zeroizing;
   
   pub fn unprotect(blob: &[u8]) -> Result<Zeroizing<Vec<u8>>> {
       // ... 解密逻辑 ...
       Zeroizing::new(slice.to_vec())
   }
   ```

2. **熵增强**
   ```rust
   // 当前: 无额外熵
   // 建议: 添加应用特定熵，增加安全性
   const APP_ENTROPY: &[u8] = b"codex-sandbox-v1";
   // 在 protect/unprotect 中使用 Some(make_blob(APP_ENTROPY))
   ```

3. **错误处理细化**
   ```rust
   // 当前: 统一返回 anyhow 错误
   // 建议: 定义具体错误类型
   #[derive(Debug)]
   pub enum DpapiError {
       EncryptionFailed(u32),
       DecryptionFailed(u32),
       InvalidData,
   }
   ```

4. **异步支持**
   - DPAPI 操作可能阻塞（涉及密钥操作）
   - 考虑提供异步接口或建议在阻塞线程执行

5. **备份/恢复考虑**
   - DPAPI 数据绑定到机器和用户（或机器范围）
   - 考虑文档化备份恢复流程

6. **替代方案评估**
   - 当前使用传统 DPAPI
   - 评估是否迁移到 DPAPI-NG（CNG）以获得更好性能

### 测试分析

当前模块无单元测试。建议补充：

| 测试场景 | 说明 |
|----------|------|
| 加密/解密往返 | 验证数据完整性 |
| 跨进程解密 | 验证 LOCAL_MACHINE 标志效果 |
| 损坏数据处理 | 验证错误处理 |
| 大数据处理 | 验证大内存分配 |
| 空数据处理 | 验证边界条件 |

### 注意事项

1. **DPAPI 依赖**
   - 需要 Windows 加密服务运行
   - 如果服务停止，DPAPI 操作失败

2. **密钥备份**
   - 机器密钥由 Windows 管理
   - 系统还原或重装后，旧加密数据无法解密

3. **性能考虑**
   - DPAPI 操作相对昂贵（涉及密钥派生）
   - 不适合高频小数据加密
   - 建议批量处理或缓存结果
