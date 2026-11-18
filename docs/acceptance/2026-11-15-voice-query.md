# 2.9.5-B 第二步：Siri 与 Android 语音查课

触发：Siri 只有长问句，缺少打开课堂入口；Android 快捷方式只能打开页面，没有查询答句或 capability，今日快捷方式还用了无法解析的 course/today 路径。
预期：Siri 保留原问句并增加短句/课堂入口；Android 标准查询、中文手机语音识别和文字输入统一走只读核心答句，未知请求给帮助，不修改任何课表。

## 已实现源码

- iOS AppShortcutsProvider 保留并扩充「课曜下节课是什么/课曜下节课」「课曜今天几点下课/课曜下课时间」，注册「开始课曜上课专注」。查询继续读取与小组件同策略的主/备用共享快照。
- 开始课堂意图使用 openAppWhenRun（兼容现有最低系统），在主线程记录待处理路由并通知前台；根视图在挂载、恢复前台和收到通知时消费一次路由，打开今日页。避免启动意图先于视图订阅导致路由丢失。答句放 Core，只说应用内专注，课外不伪称已在上课，不开启系统专注。未采用要求 universal link 的 OpenURLIntent 自定义 URL 方案。
- Android 增加只读 ScheduleAnswers、两种问题分派、日期时间/地点回答；按课表引擎处理假期、取消和时区。语音/文字/标准 SEARCH 入口共用模型查询方法。问句长度限制 200；不理解的请求不会按关键词误执行，也不执行任何写入。
- shortcuts.xml 增加 GET_THING capability（thing.name → query，允许参数缺失时打开帮助页），下节课/下课时间快捷查询，修正今日课表链接；MainActivity 处理 SEARCH/query/today，新增「我的 → 语音查课」页。
- 中文输入通过外部 RecognizerIntent 识别活动返回文字；请求离线优先，但服务可忽略。界面在启动前提示可能联网；课曜不接收音频、不上传课表。识别服务缺失、权限拒绝、空结果有提示，取消不查询。无新增麦克风权限、无第三方开发者账号或密钥。
- 两端版本保持 2.9.5；iOS 中文日志、Siri 设置和 Android 关于说明同步。

## 支持边界与依据

Google 官方 GET_THING 文档仅列 en-US/pt-BR 的预览和用户唤起支持；因此配置 capability 不代表中文可被 Google Assistant 直接唤起，也不代表侧载安装已被服务索引。中文可用入口是应用内手机语音识别（需手机装有可用服务），文字/快捷按钮始终保留。小爱、小艺、OPPO/vivo、Bixby 的专属技能没有接入，须各家开放平台开发者账号、审核及相应技能适配，不能用标准接口替代并称已接入。

参考：[GET_THING 支持语言与参数](https://developer.android.com/reference/app-actions/built-in-intents/common/get-thing)、[capability 与 fallback 规范](https://developer.android.com/develop/devices/assistant/action-schema)、[RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent)、[Apple 前台 App Intent 导航示例](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents)。

## 本地结果与未验收

- Kotlin 核心 JVM 84 项通过，新增 7 项：中文/英文查询别名，未知/有歧义请求，不可读与空课表区分，下一节排除已开始的课，最后一节结束边界，假期与取消，学校时区。
- Swift 为课堂答句补 1 项边界测试，原 Siri 答句测试保留；无 Swift/Xcode，未运行。
- 项目/版本快照/diff 检查通过；XML 检查 capability 参数映射、缺省入口、快捷方式 ID、标签资源及 SEARCH 路由声明通过。
- 无 Android SDK，未编译 Compose/Manifest/资源；无真实语音服务、Siri 元数据编译、中文唤起、侧载共享读取或冷/热启动路由验收。核心与静态检查不替代这些证据。
- 语音页沿用已有间距、标题、输入框和按钮样式；仍需大小屏、大字、浅深色截图审美复核。

B 还剩系统 Focus Filter 和 Android 用户同意后的勿扰策略，通知/Live Activity 的后台时序仍缺设备验收。本步不是 B 或整批交付。待用户要求后再推送；iOS 待用户要求推送后云端构建。本轮未使用浏览器会话、未访问 GitHub/GitLab、未推送、未发布。

> 2026-11-16 更新：本人 2026-11-15 23:26 决定 Android 语音助手全部不接。Android 端的 GET_THING capability、搜索快捷方式、classday://query、应用内语音查课页与 ScheduleAnswers 已移除；iOS Siri 查课表保留不动。
