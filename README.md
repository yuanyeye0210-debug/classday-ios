# classday-ios

课间 / Classday is a native SwiftUI iPhone timetable with a WidgetKit extension. The project lives in [`Classday/`](Classday/).

This repository does not ship an App Store build.

## 发版流程（必须在发新版时遵守）

规则见 [`Classday/Docs/RELEASE-RETENTION.md`](Classday/Docs/RELEASE-RETENTION.md)，核心三条：

1. **备份上一版**：上一个版本目录打包到 `artifacts/_backup/<版本>.zip`，并校验条目数
2. **删除更早版本**：所有比「上一版」更旧的版本目录、调试目录、散落临时文件全部删除
3. **只留一份备份**：`_backup` 里只保留上一版，随每次发版轮转替换

### 一条命令发版

```powershell
# 安卓本地构建 + iOS 推 CI 取回 IPA + 自动轮转 + 写发布记录
F:\vebcoding\ClassDay\build-tools\release.ps1 -Version 2.10.5

# 只出安卓 / 只推 iOS
F:\vebcoding\ClassDay\build-tools\release.ps1 -Version 2.10.5 -Platform android
F:\vebcoding\ClassDay\build-tools\release.ps1 -Version 2.10.5 -Platform ios
```

脚本做的事：

| 步骤 | 内容 |
|---|---|
| 1 | 改版本号：Android `versionName`/`versionCode`（`major*10000+minor*100+patch`）、iOS `MARKETING_VERSION` |
| 2 | Android：`gradlew :app:assembleRelease` → `artifacts/<版本>/Classday-android-v<版本>.apk` |
| 3 | iOS：提交并推 GitLab，再用孤立快照推 GitHub `ios-build` 触发 CI，成功后经 API 取回 IPA |
| 4 | 轮转：备份上一版 → 删除更早版本（`release-prune.ps1`） |
| 5 | 写 `artifacts/<版本>/RELEASE-NOTES.md`（产物 + SHA256 + 时间 + 平台） |

单个动作也可以单独跑：

```powershell
F:\vebcoding\ClassDay\build-tools\release-prune.ps1 -ProjectRoot F:\vebcoding\ClassDay -CurrentVersion 2.10.5 -DryRun
```

### 注意

- iOS 的版本号必须改在 **GitLab 分支**（Codemagic 从 GitLab 拉代码），只在本地或 GitHub 改不生效
- GitHub 历史提交里有旧的内置密钥，会被推送保护拦；所以推 GitHub 一律走**孤立快照 + ours 合并**
- 用户 `Downloads` 目录不在自动清理范围（那是手工下载的副本）
