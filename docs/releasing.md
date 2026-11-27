# pile 发布流程

**打包 → 提交代码 → GitHub 上传安装包 → 同步更新源 → 推送部署。**

以下以 `1.2.2` 为例，所有命令在仓库根目录执行。发布其他版本时替换版本号。

## 1. 准备版本和更新说明

- `Resources/Info.plist`：版本号 `CFBundleShortVersionString` 为 `1.2.2`，build number `CFBundleVersion` 为 `7`。
- `docs/releases/1.2.2.md`：写这次更新内容。

本次已经准备好。以后每次发布都要增加版本号和 build number。

## 2. 打包并提交代码

```bash
./Scripts/build-dmg.sh release
codesign --verify --deep --strict build/pile.app
hdiutil verify build/pile-1.2.2.dmg
```

全部成功后，提交本次代码、版本号和更新说明，推送到 `main`。

要上传的文件是 **`build/pile-1.2.2.dmg`**。暂存更新源在 `build/updates/appcast.xml`，此时不用手动复制。

## 3. 在 GitHub 上传安装包

打开 [创建 Release](https://github.com/akira1ce/pile/releases/new)，填写：

| 项目 | 填什么 |
| --- | --- |
| Tag | `1.2.2`，不加 `v` |
| Target | 第 2 步推送的提交 |
| 标题 | `pile v1.2.2` |
| 说明 | 粘贴 `docs/releases/1.2.2.md` 的内容 |
| 附件 | 上传 `build/pile-1.2.2.dmg` |

等附件上传完成，点击 **Publish release**，不要停在草稿状态。

## 4. 同步应用内更新源

**完成第 3 步后**，再运行：

```bash
./Scripts/publish-updates.sh
```

它会下载 GitHub 安装包，确认与本地文件一致，再更新 `site/appcast.xml`。

遇到 **404**：检查 Release 是否已发布、Tag 是否为 `1.2.2`、附件是否为 `pile-1.2.2.dmg`。修正后重跑这一步。

如果重新打包，必须重新上传新的 DMG；安装包和更新源要来自同一次打包。不要手动修改已签名的 XML。

## 5. 推送更新源并检查

```bash
git add site/appcast.xml
git commit -m "feat(appcast): publish signed 1.2.2 release feed"
git push origin main
```

在 [GitHub Actions](https://github.com/akira1ce/pile/actions) 等待 **Deploy site** 成功。再用旧版 pile 点击「检查更新」，确认能下载安装，并检查设置和辅助功能权限。

网站下载按钮、页脚如显示旧版本，同步修改 `site/index.html` 后一起提交。

## 换构建机器时

迁移原应用签名证书及其私钥、原 Sparkle 更新密钥。`setup-updates.sh` 是首次配置用的，不需要每次发布都运行；不要生成替代旧密钥的新密钥。
