# 在浏览器里实时操作 iOS 界面（不装手机）

## 方案：Appetize.io + CI 打模拟器包

安卓用模拟器随时点，iOS 也可以——把**模拟器版 `.app`** 上传到 Appetize，得到一个网页链接，
在里面能真实点击、滑动、输入、旋转，跟安卓模拟器一样，全程不碰手机。

### 为什么必须是模拟器包，不是 IPA

| 产物 | 能装真机 | 能 Appetize |
|---|---|---|
| `Classday-v*.ipa`（device, arm64） | 需要签名（AltStore/SideStore） | ❌ |
| `Classday-simulator.zip`（iOS Simulator） | ❌ | ✅ |

仓库里已有专门的 workflow：`classday-ios-simulator`（Codemagic 里显示为
「Classday simulator app (App Preview)」），产物就是 `dist/Classday-simulator.zip`。

### 三种用法

**A. 手动（1 分钟，先试试）**

1. Codemagic → YYY-project → Start new build → workflow 选 `Classday simulator app (App Preview)`
2. 构建完成 → 下载 `Classday-simulator.zip`
3. 打开 https://appetize.io/upload → 拖进去 → 选 iOS → 得到链接
4. 之后随时打开链接就能点，不用再上传

**B. 全自动（推荐，配一次永久受益）**

1. 注册 Appetize，Account → API token 拷出来
2. Codemagic → YYY-project → Settings → Environment variables → 新增 `APPTIZE_TOKEN`（勾 Secure）
3. 之后每次跑模拟器 workflow，日志末尾会自动打印：

```
================ Appetize 可交互预览 ================
https://appetize.io/app/<publicKey>
====================================================
```

（`codemagic.yaml` 里已内置 `Upload to Appetize (optional)` 步骤，没有 token 时自动跳过）

**C. 云真机（要验证通知/相机/Widget 才需要）**

BrowserStack App Live / LambdaTest 可以操作真机，付费；装机包仍用 IPA + 侧载。

### 备注

- Appetize 免费额度有限（每月若干分钟），足够日常点几下验证功能
- 模拟器看不到：真实推送、相机、Widget 时间线、真实性能；这些还是得上真机
- CI 另外会自动截每个页面（7 套主题 + 详情/周览/课程/考试/导入/我的），
  纯看视觉可以直接看截图，不用开 Appetize