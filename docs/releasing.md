# pile 发布与应用内更新手册

日常流程：**改版本和说明 → 打包验证 → 提交代码 → GitHub Release 上传 DMG → 同步更新源 → 推送并等待 Pages 部署 → 从旧版测试更新**。

以下命令均在 pile 仓库目录执行：

```bash
cd /Users/akira1ce/Documents/workspace/akira1ce/pile
```

## 每次发布

### 1. 更新版本和 release notes

修改 `Resources/Info.plist` 的两个字段：

| 字段 | 用途 | 下一版示例 |
| --- | --- | --- |
| `CFBundleShortVersionString` | 用户看到的版本号、Release tag、DMG 文件名 | `1.2.2` |
| `CFBundleVersion` | Sparkle 比较新旧版本的 build number | `7` |

这里以当前 `1.2.1 / build 6` 的下一版为例；后续发布请使用对应的新版本。**build number 每次递增，不随版本号重置。**

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.2.2" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 7" Resources/Info.plist
```

编写 `docs/releases/1.2.2.md`，记录本次更新内容。这份 Markdown 同时用于 GitHub Release 说明和应用内更新弹窗。

### 2. 打包并验证

```bash
./Scripts/build-dmg.sh release
codesign --verify --deep --strict --verbose=2 build/pile.app
hdiutil verify build/pile-1.2.2.dmg
```

签名验证最后应显示 `valid on disk` 和 `satisfies its Designated Requirement`；DMG 校验应显示 `VALID`。

| 产物 | 用途 |
| --- | --- |
| `build/pile.app` | 签名后的应用 |
| `build/pile-1.2.2.dmg` | 上传到 GitHub Release 的安装包 |
| `build/updates/appcast.xml` | 已签名、暂存的更新源 |

脚本会一起嵌入并签名 Sparkle，生成包含版本、安装包签名和更新说明的更新源。平时直接运行打包命令即可，不需要重新设置签名身份或生成密钥。

### 3. 提交并推送代码

将本次代码、版本字段和 release notes 提交并推送到 `main`。创建 Release 时选择这次提交，让 tag 对应生成安装包的源码。

此时公开的 `site/appcast.xml` 仍指向上一次已发布版本。

### 4. 创建 GitHub Release

打开 [创建 Release](https://github.com/akira1ce/pile/releases/new)：

- Tag 默认使用版本号，例如 `1.2.2`。
- 标题可写 `pile v1.2.2`。
- 说明粘贴 `docs/releases/1.2.2.md` 的内容。
- 上传 `build/pile-1.2.2.dmg`，发布为正式 Release。

默认 tag 不带 `v`。如果选择带 `v` 的 tag，必须在打包时一起指定：

```bash
PILE_RELEASE_TAG=v1.2.2 ./Scripts/build-dmg.sh release
```

### 5. 同步更新源

安装包上传完成后运行：

```bash
./Scripts/publish-updates.sh
```

它会验证更新源和本地 DMG 的签名，下载 GitHub 上的安装包并比较内容；确认一致后，把 `build/updates/appcast.xml` 复制到 `site/appcast.xml`。

成功输出：

```text
Updated site/appcast.xml for pile 1.2.2. Commit and push it to deploy via GitHub Pages.
```

**上传的 DMG 和更新源必须来自同一次打包。** 如果重新打包了同一版本，需要重新上传对应的 DMG，再同步更新源。

### 6. 推送更新源并等待部署

提交修改后的 `site/appcast.xml`，推送到 `main`。在 [GitHub Actions](https://github.com/akira1ce/pile/actions) 等待 `Deploy site` 工作流成功。

公开更新源地址：<https://akira1ce.github.io/pile/appcast.xml>。

`site/appcast.xml` 带有签名，保持脚本生成的内容；需要修改时重新生成。先发布安装包，再部署更新源，用户收到提醒时才能下载。

若还需要更新网站下载按钮和页脚版本，在 Release 发布后修改 `site/index.html`，可与更新源一起提交。

### 7. 从旧版测试应用内更新

保留并运行 `/Applications/pile.app` 中的旧版，新的 DMG 用于上传发布。

1. 在旧版菜单栏或「关于 pile」点击「检查更新」。
2. 确认弹窗显示新版本和本次更新说明。
3. 确认下载并安装，等待 pile 重新启动。
4. 在「关于 pile」确认版本已更新，再确认自定义设置、快捷键和辅助功能授权是否正常。

含 Sparkle 的首个版本是 `1.2.0`，需要手动安装一次；后续可走应用内更新。此次已发布 `1.2.1`，可用 `1.2.0 → 1.2.1` 的流程作为参考。

## 已完成的一次性设置

- 应用默认使用固定的 **Apple Development** 证书签名，指纹是 `E4AA3D29A59D3306655EE1BCC796285EE8260AF2`。
- Sparkle 更新密钥已由 `./Scripts/setup-updates.sh` 设置，私钥留在登录钥匙串，账户名为 `com.akira1ce.pile`；公钥在 `Resources/Info.plist` 的 `SUPublicEDKey` 字段。
- 保持 Bundle ID `com.akira1ce.pile`、签名身份、更新密钥和安装路径 `/Applications/pile.app` 一致。
- 更换构建机器时，迁移原证书及其私钥，并恢复原 Sparkle 更新密钥。请安全备份这两套签名材料；未来更新需要原来的密钥。
- 目前采用 Apple Development 签名，未经过 Apple 公证。签名和公证是独立流程。

## 常见报错

### `Developer ID Application: ...: no identity found`

终端中的旧环境变量覆盖了脚本默认的 Apple Development 证书。清掉后重试：

```bash
unset PILE_SIGN_IDENTITY
./Scripts/build-dmg.sh release
```

如果 `~/.zshrc` 中写过旧的 `export PILE_SIGN_IDENTITY=...`，也删除那行。

### `curl: (16) Error in the HTTP2 framing layer`

此次已通过启用本机代理解决。先启动代理，再在同一个终端设置并重试发布脚本：

```bash
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897
./Scripts/publish-updates.sh
```

`7897` 是当前代理端口；更换客户端或端口时按实际配置修改。设置只影响当前终端会话。这个下载错误无需重新打包。

### 更新源同步失败

- **404**：确认 Release 已正式发布、tag 与打包参数一致、DMG 文件名正确。
- **远端 DMG 与本地不同**：上传同一次构建的 DMG，再运行同步脚本。
- **Sparkle key does not match**：恢复原来的钥匙串密钥，使其匹配应用公钥。

### 应用提示没有新版本

确认 `Deploy site` 已成功、新更新源中的 `sparkle:version` 大于旧版 build number，并稍后再次手动检查更新。

### 更新后提示辅助功能未授权

退出 pile，在「系统设置 → 隐私与安全性 → 辅助功能」中删除旧条目，重新添加 `/Applications/pile.app` 并启动。授权状态由 macOS 管理，保持固定签名身份与安装路径有助于维持应用身份一致。
