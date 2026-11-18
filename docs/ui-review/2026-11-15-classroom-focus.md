# 2.9.5-B 第一小步：自动应用内上课专注

触发：两端已有上课中判断，但未改变界面减扰；iOS 设置把手工配置系统自动化当主路径。
预期：打开应用后按实际课表自动进入应用内上课状态，突出当前课、收起其他课程、降低背景动效；下课恢复。随时可主动查看当天所有课程，不改课程数据和系统权限。

## 已实现的源码范围

- 两端 TodayOverview 提供 classroomCourse / displayedCourses，复用课表引擎的假期、取消、延时和周次规则。上课包含开始时刻、不包含结束时刻；尚未开始的下一节不会触发减扰。
- iOS 首页收起其他课程和次要安排，保留主动展开入口；专注卡明确区分系统专注。ChromeInstaller 临时按省电/减弱动态策略渲染，不写主题配置；结束后恢复原来的用户设置。
- Android 同样突出当前课、收起其他课程，停用倾斜传感器和背景丰富动效；前台每约五秒刷新，离开 RESUMED 状态停止轮询，恢复前台立即刷新。用户主题/性能设置不改写。
- iOS 设置删除自行配置自动化的主路径，说明已自动生效的应用内行为与系统边界。版本仍为 2.9.5，两端关于/中文日志同步。
- 复核 A 发现 Android AlertDialog 缺少显式 import，本次补齐。这是源码修复，未据此宣称 Android 编译通过。

## 本地验证

Android 核心 JVM 77 项通过，其中新增 3 项：起止边界及主动展开/下课恢复，假期/读取失败不触发，取消/延时仅影响指定周。Swift 增加相应 3 项测试，但没有 Swift/Xcode，未执行。静态项目检查、版本快照检查、git diff --check 通过。

源码审美复核：专注卡在主课程卡下方，短标题、边界说明、一个主动展开按钮；保持现有卡片和文字样式。尚无大小屏/深浅色/大字截图，不能标记视觉验收完成。需设备验证相邻课程切换、恢复前台、临时展开归位、传感器停止和恢复、不可读课表及已有系统省电/减弱动态设置。

## B 仍未完成

下一轮继续 B：补齐 Siri 短语和开始上课入口、可行的系统 Focus Filter，以及 Android 标准查询 capability/核心答句和用户明确同意后的勿扰策略。现有通知/Live Activity 未改，后台准时刷新不能由本次前台行为证明；Siri 发现、语音唤起与共享读取也未做设备验收。不能把本步当作 B 或整批交付。

后续标准接口依据：[Apple Focus Filter](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter)、[Android App Actions schema](https://developer.android.com/develop/devices/assistant/action-schema)。平台接口不等于所有厂商助手已接入。

未使用浏览器会话、未访问 GitHub/GitLab、未推送或发布。待用户要求后再推送；iOS 待用户要求推送后云端构建。
