# 2D 开箱

Mac：`nunu-unboxing.tsx` 与 `nunu-unboxing-motion.ts`。场景是 three.js。WebGL 失败时退回 `AgentAvatar` 全身、190px。`prefers-reduced-motion` 时时钟跳到 `UNBOX_PLAYBACK_DURATION`，姿态是休息态，彩纸不画。

Android 始终走这条退路的视觉，再加上可选的 2D 包装淡出。不创建 WebGL，不加载 `BODY_ASSETS`，不 portal 彩纸 canvas。

区域：`.sand-nunu-unbox` 的盒子。宽 100%，高 280dp；窗口高度 `< 640dp` 时高 192dp。`aria-hidden`，因为旁边的色板和名字已经说明这是什么。

## 终态（验收画面）

无论有没有动效，停下来时必须是：

- 包装剪影不可见（`packaging = 0`）
- 矢量全身 Nunu 居中，190dp，viewBox `0 0 232 232`
- 颜色、形状、材质等于创建页当前的 `avatar`
- 姿态是 `NUNU_REST`：无跃起、无招手
- 无彩纸

用户改颜色时，身体色素立刻换成新的 `value`，形状和材质不变。Mac 在改色时只 `setPigment`，不重播开箱。Android 同样不重播。

## 有动效时

仅当系统没有打开减弱动态效果：

1. 开场画一种包装剪影，由 `rollUnboxingPackage()` 决定，一次打开只抽一次。
   - `soft-tray`：圆角 `--nuum-radius-3xl` 的矩形
   - `paper-fold`：折角矩形
   - `round-box`：圆
   填充是 `value` 以 40% 混在 `--sand-bg-elevated` 上。
2. 1500ms 内剪影透明度收到 0，Nunu 从 0.92 放到 1。缓动 `--nuum-easing-out-strong`。
3. 1500ms 时与终态重合。不延长到彩纸的 4620ms。

## 减弱动态效果

第一帧就是终态。不注册 `Animator`、不注册帧回调、不抽包装种类也可以（抽了也不画）。WP-08 的测试要能断言没有动画时钟。

从减弱动态效果切换到开着：不要把已经结束的形象再播一遍。只有新打开创建页才播。

## 状态

| 状态 | 这一屏 |
| --- | --- |
| 空 | 不出现。创建页一定有一次 `rollAgentAvatar()` 的结果 |
| 加载 | 矢量不需要解码。没有骨架屏 |
| 流式 | 此表面不出现 |
| 错误 | 不单独显示。创建失败由创建页 alert 承担。形象留在终态 |
| 无 key | 此表面不出现 |
| 权限被拒 | 此表面不出现 |
| 讨论中断 | 此表面不出现 |

打招呼、待机、`wave` / `cheer` / `think` / `sleepy` 都不在开箱里播放。资料页的本地反应见 [profile.md](./profile.md) 与 [motion.md](../motion.md)。
