<div align="center">

<img src="icon/macos/AppIcon256.png" width="128" alt="pile" />

# pile

**三个快捷键，把当前屏幕的窗口摆整齐 —— 居中、收起 / 展开、切换**

Swift 6 · SwiftPM · AppKit + SwiftUI · macOS 26+

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue?logo=apple)](#构建与运行)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](Package.swift)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0A84FF)](#架构)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

## 功能

- 🎯 **居中预设** — 用同一个修饰键加数字键，把聚焦窗口居中到预设尺寸。默认三个、最多五个，宽高按屏幕百分比调节
- 🗂 **收起 / 展开** — 一键把当前屏幕的窗口居中摞成一叠，再按一次按设定的方式摊开；整叠沿用聚焦窗口的尺寸，间距可调
- ⇥ **窗口切换器** — 按住修饰键再按 Tab，屏幕中央弹出横向窗口条，直接选目标而不是顺序轮切；悬停显示关闭 / 最小化按钮，容器使用 Liquid Glass
- 🖥 **菜单栏常驻** — 无 Dock 图标、无主窗口；菜单里可触发所有动作、查看当前状态、打开设置与功能介绍
- ⌨️ **可配置快捷键** — 所有快捷键共用一个修饰键（⌥ / ⌃ / ⇧），默认 ⌥，修改后立即重新注册
- 🚀 **登录时启动** — 基于 `SMAppService`，可在设置里开关；作为登录项启动时安静地待在菜单栏
- 🖥 **多显示器** — 窗口操作始终针对「当前屏幕」；没有聚焦窗口时，切换器使用鼠标所在屏幕
- ✨ **平滑动画** — 窗口先移动、再缩放，可在设置中关闭
- 🧭 **首次引导** — 首次启动引导授权辅助功能并播放内置演示，之后可从菜单再次打开

### 快捷键

所有快捷键共用设置里的修饰键（默认 ⌥）。

| 快捷键 | 作用 |
| --- | --- |
| `⌥ + 1–5` | 把聚焦窗口居中到对应预设尺寸 |
| `⌥ + ·` | 收起 / 展开当前屏幕的窗口 |
| `⌥ + Tab` | 打开窗口切换器，选择要切换到的窗口 |

窗口切换器打开后：

| 操作 | 作用 |
| --- | --- |
| 按住 `⌥` 连按 `Tab` / `⇧ + Tab` | 向后 / 向前移动高亮 |
| `←` / `→` | 移动高亮 |
| `Return` | 切换到高亮窗口 |
| `Esc` | 取消 |
| 松开 `⌥` | 切换到高亮窗口 |
| 点击图标 | 切换到该窗口 |

> 居中、收起 / 展开需要有一个聚焦的标准窗口，且设置窗口已关闭；`⌥ + Tab` 没有这个限制，桌面无聚焦窗口时也能使用。

## 构建与运行

需要 **macOS 26+** 与 **Xcode 26+**（Swift 6）。

```bash
# 调试构建，产物在 build/pile.app
./Scripts/build-app.sh debug
open build/pile.app

# Release 构建
./Scripts/build-app.sh release
```

也可以直接用 SwiftPM：

```bash
swift build
```

### 打包 DMG

```bash
./Scripts/build-dmg.sh
# 输出 build/pile-<version>.dmg
```

脚本会构建 Release 应用、生成拖拽安装布局并进行 ad-hoc 签名。产物未经过公证；首次打开时请右键点击图标选择「打开」。若要在设置里启用「登录时启动」，请先把 pile.app 放进「应用程序」文件夹。

### 首次运行

1. 启动 pile，按引导在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 pile
2. 授权后自动进入功能介绍与设置窗口
3. 关闭设置窗口后，居中与收起 / 展开快捷键即可使用

## 工作原理与权限

- **辅助功能** — 通过 `AXUIElement` 读取窗口位置、尺寸、最小化状态，并执行移动、缩放、关闭、最小化、聚焦与置顶；未授权时快捷键不可用，菜单会提供引导
- **窗口发现** — 用 `CGWindowListCopyWindowInfo` 获取屏幕上的窗口层级，再用 AX 窗口列表按标题、角色匹配，只保留当前屏幕的标准窗口，顺序即系统的前后层级
- **全局快捷键** — 预设与 `·` 使用 Carbon `RegisterEventHotKey`；`⌥ + Tab` 需要按下 / 松开语义，改由会话级 `CGEvent` tap 处理，被系统禁用后会自动重新启用
- **切换器浮层** — 非激活的 `NSPanel`（`.nonactivatingPanel`、`popUpMenu` 层级、可加入所有空间），不会抢走当前应用的焦点，悬停与点击也不改变系统焦点
- **堆叠状态** — 按显示器 UUID 记录收起布局，只有未被扰动的收起状态才会展开；切换桌面空间或显示器时清空
- **无后台服务** — 单进程菜单栏应用，无网络请求，偏好只保存在本机 `UserDefaults`

## 架构

```
Sources/
├─ main.swift                       # NSApplication 启动入口
├─ AppController.swift              # 菜单栏、快捷键注册、权限状态、设置与引导窗口
├─ HotKeyManager.swift              # Carbon 全局快捷键（预设、收起 / 展开）
├─ OptionTabMonitor.swift           # CGEvent tap（⌥ + Tab 按住 / 松开、方向键、确认、取消）
├─ AccessibilityWindowService.swift # 窗口发现、移动 / 缩放动画、关闭 / 最小化 / 聚焦
├─ FocusSwitcher.swift              # 切换器控制器、数据模型、非激活面板
├─ FocusSwitcherView.swift          # Liquid Glass 横向窗口条与悬停操作
├─ LayoutCoordinator.swift          # 按屏幕维护收起状态，决定收起还是展开
├─ WindowGeometry.swift             # 屏幕几何、预设、堆叠排布计算
├─ PreferencesStore.swift           # 偏好持久化与校验（UserDefaults + Codable）
├─ SettingsView.swift               # 侧边栏式设置（通用 / 展开方式 / 窗口预设 / 关于）
├─ FeatureTourView.swift            # 首次功能介绍
├─ FeatureTourDemoView.swift        # 功能介绍中的动画演示
├─ PermissionOnboardingView.swift   # 辅助功能权限引导
├─ LaunchAtLogin.swift              # SMAppService 登录项
└─ WindowAnimation.swift            # 动画缓动曲线
```

## 已知边界

- 最小化、全屏与非标准窗口（对话框、浮动面板等）不会出现在堆叠与切换器中
- 切换器一次只处理一个屏幕，不会跨屏混合列表
- 切换器不提供窗口实时预览、按应用分组或跨全屏空间切换
- 个别应用的窗口可能拒绝 AX 调整或关闭 / 最小化操作，pile 会保持原状
