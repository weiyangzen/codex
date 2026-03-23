# frame_12.txt 研究文档

## 场景与职责

`frame_12.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 12 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 12/36 帧
**时序位置**：880ms（第 12 个 80ms 间隔）

## 功能点目的

1. **动画序列推进**：作为 36 帧循环的第 12 帧，达到 1/3 周期点
2. **旋转展示**：展示 Codex 图标旋转约 110° 后的状态
3. **视觉连续性**：保持与前后帧的平滑过渡

## 具体技术实现

### 帧周期分析
```
完整周期：36 帧 × 80ms = 2880ms
当前进度：12/36 = 33.3%
当前时间：880ms
剩余时间：2000ms
```

### 帧索引计算
```rust
let frame_idx = (elapsed_ms / 80) % 36;
// 当 elapsed_ms = 880 时
// frame_idx = (880 / 80) % 36 = 11
// 对应 FRAMES_CODEX[11] = frame_12.txt
```

### 动画状态
```rust
struct AsciiAnimation {
    variant_idx: usize,  // 1 = FRAMES_CODEX
    start: Instant,      // 动画开始时间
    frame_tick: Duration::from_millis(80),
}
```

## 关键代码路径与文件引用

### 文件位置
```
codex-rs/tui_app_server/
├── src/frames.rs          # 包含本文件
├── src/ascii_animation.rs # 使用本文件
├── src/onboarding/welcome.rs # 渲染本文件
└── frames/codex/frame_12.txt # 本文件
```

### 代码引用
```rust
// frames.rs (编译时)
include_str!("../frames/codex/frame_12.txt")

// ascii_animation.rs (运行时)
frames[11]  // 当计算出的索引为 11

// welcome.rs (渲染时)
frame.lines().map(Into::into)  // 转换为 Line
```

## 依赖与外部交互

### 系统依赖
- **编译时**：文件系统读取
- **运行时**：仅内存访问（已嵌入二进制）

### 模块交互
| 模块 | 交互方式 |
|-----|---------|
| `frames` | 静态包含 |
| `ascii_animation` | 时间索引 |
| `welcome` | 渲染显示 |
| `tui` | 调度触发 |

## 风险、边界与改进建议

### 风险分析
1. **文件一致性**：36 个帧文件必须保持一致的尺寸和格式
2. **版本同步**：帧文件变更需要重新编译
3. **二进制大小**：所有帧嵌入后增加约 24KB（仅 codex 变体）

### 改进方向
1. **动态加载**：运行时从配置文件加载帧
2. **压缩算法**：使用简单的 RLE 压缩
3. **矢量描述**：使用数学描述代替位图帧

### 测试策略
```rust
#[test]
fn test_frame_12_dimensions() {
    let frame = FRAMES_CODEX[11];
    let lines: Vec<_> = frame.lines().collect();
    assert_eq!(lines.len(), 17);
    assert!(lines.iter().all(|l| l.len() <= 40));
}
```
