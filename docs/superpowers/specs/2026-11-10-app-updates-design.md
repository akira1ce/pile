# pile 应用内更新

用户已确认采用 Sparkle、GitHub Release 和 GitHub Pages，并开始实施。

- 菜单栏、应用菜单、设置的「关于 pile」提供「检查更新…」。
- Sparkle 定期检查更新；提供开关。发现新版由用户确认下载、安装并重启，不启用静默安装，也不发送系统信息。
- 更新功能不依赖辅助功能授权。应用生命周期持有唯一的更新控制器，SwiftUI 观察检查是否可用。
- 更新源为 `https://akira1ce.github.io/pile/appcast.xml`。DMG 继续在 GitHub Release 发布，标签遵循已有的无 `v` 版本格式。
- 使用 Sparkle 官方工具生成、验证 EdDSA 更新签名。私钥保留在本机钥匙串，不写入仓库；公钥写入应用 Info.plist。缺少密钥时禁止生成可发布的更新源。
- 构建脚本复制 Sparkle framework，按由内向外顺序使用现有 Apple Development 证书签名。无需修改 Bundle ID；不添加 Apple 公证流程。
- DMG 打包后在 `build/updates/` 生成 appcast 与本次说明；发布 DMG 后显式运行发布脚本，复制更新源至 `site/`，避免提前指向尚未上传的包。
- 最低系统保持 macOS 26；版本及 build number 单调递增。第一次安装包含更新器的版本仍需手动安装。
- 验证 release 编译、framework 嵌入与加载路径、appcast 内容和发布顺序、签名工具及实际 DMG。系统安装和跨版本权限保留需在用户 macOS 会话验证。
