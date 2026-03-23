# frame_20.txt 研究文档

## 场景与职责

`frame_20.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 20 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 20/36 帧
**时序位置**：1520ms（第 20 个 80ms 间隔）

## 功能点目的

1. **动画序列推进**：作为 36 帧循环的第 20 帧，超过 55% 周期点
2. **旋转展示**：展示 Codex 图标旋转约 190° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 帧时序
```
frame_20 时间线：
├─ 起始：1520ms
├─ 结束：1600ms
├─ 周期进度：20/36 ≈ 55.6%
└─ 剩余帧数：16 帧
```

### 帧索引
```rust
const FRAME_20_INDEX: usize = 19;
let content = FRAMES_CODEX[FRAME_20_INDEX];
```

### 时间计算
```rust
let elapsed_ms = 1520;
let idx = (elapsed_ms / 80) % 36;  // = 19
assert_eq!(FRAMES_CODEX[idx as usize], include_str!("frame_20.txt"));
```

## 关键代码路径与文件引用

### 核心模块
| 模块 | 与本帧关系 |
|-----|-----------|
| `frames` | 静态包含 frame_20.txt |
| `ascii_animation` | 时间索引到本帧 |
| `welcome` | 渲染本帧 |

### 调用链
```
frame_20.txt
  ↓
include_str!
  ↓
FRAMES_CODEX[19]
  ↓
current_frame() (idx=19)
  ↓
render_ref()
  ↓
终端
```

## 依赖与外部交互

### 编译依赖
- 文件存在
- UTF-8 编码
- 路径正确

### 运行时依赖
- 时间计算
- 索引访问

### 用户交互
- 变体切换
- 动画开关

## 风险、边界与改进建议

### 边界情况
1. **后半周期**：frame_20 已进入后半周期
2. **接近结束**：还有 16 帧完成周期
3. **循环准备**：需要确保与 frame_1 的过渡平滑

### 改进建议
1. **帧复用**：如果动画对称，后半周期可以复用前半周期帧
2. **内存优化**：36 帧可以压缩存储
3. **懒加载**：按需加载帧到内存

### 测试覆盖
```rust
#[test]
fn frame_20_accessible() {
    assert!(FRAMES_CODEX.get(19).is_some());
    let frame = FRAMES_CODEX[19];
    assert!(!frame.is_empty());
}
```
