# 2.9.5-B 第三步：系统专注过滤与可选上课勿扰

触发：应用内自动上课状态和语音查课已有，但尚无系统专注界面过滤、Android 授权后独立勿扰规则。
预期：iOS 允许用户现有专注选择课曜界面过滤；Android 默认关闭，只有明确同意、勿扰访问与精确定时条件齐备后才按真实课表请求自己的规则，上下课不改用户/其他应用的勿扰。

## iOS 源码

ClassroomFocusFilter 遵循 SetFocusFilterIntent，默认精简参数为 false，建议配置为 true。系统专注关闭时回到默认参数。应用前台通过 async throws 的 current 获取当前配置，失败回退 false；随 scenePhase 取消后台轮询。每约五秒更新模型，然后首页和背景渲染读取同一状态。过滤时仅突出当前或下一节课、收起次要安排、降低背景动效；用户仍可主动展开，关闭过滤恢复。

这是前台界面过滤，无新增扩展或共享组权限，不借过滤器改变系统专注开关，不承诺后台通知过滤。perform 不写持久化开关，避免遗留的偏好错误维持过滤。用户可在已有系统专注中选择课曜上课界面，不需要按星期手工建快捷指令自动化。原本按课表自动进入应用内上课状态仍独立可用。

## Android 源码

- API 29（Android 10）以上使用 app-owned AutomaticZenRule + setAutomaticZenRuleState；低版本保留应用内专注，不声称支持该独立系统规则。声明勿扰访问权限并提供系统设置入口，但本轮没有在任何设备上授权。
- 提醒页先说明影响，再由用户明确点同意；默认 consent=false，权限不足时拒绝开启。精确定时是启用条件，API 31 以下无需该额外授权。没有相应设置页时有失败提示。
- 仅创建/读取保存的课曜规则 ID，并核对 condition URI；不调用全局 setInterruptionFilter/setNotificationPolicy，不改其他规则。优先通知允许哪些中断沿用系统用户设置。用户在系统中关闭规则不会被自动重新启用，用户删掉规则后需再次明确启用才能创建。
- 核心规划器只对可读的真实课表生效，任何未同意/缺权限/演示/读失败都不请求勿扰。按引擎产生的整学期课程区间合并重叠/连续课程，在真正上课/下课边界切换。
- 先安排下次边界，成功后才发布 TRUE；调度或更新失败尝试发布本规则 FALSE。停用只撤销本规则并取消本规则的边界任务，不主动关闭其他勿扰。
- 私有边界接收器 goAsync，保存成功、回到前台、重启、时间/时区及规则启停事件重新读取课表和规划。重启回调在异步广播完成前同步规划。用户暂停规则不在中途被强制重新开启。
- 系统/厂商节电、撤回权限、杀进程和 Android 闹钟配额仍可延迟后台执行，界面已提示检查实际通知栏状态；源码和核心测试不能证明下课时刻系统一定已退出。无本地设备或系统权限变更。

两端保持 2.9.5，中文日志、设置/关于说明同步。

## 验证与剩余验收

- Android 核心 JVM 90 项通过，新增 6 项：用户同意/两权限/读状态/真实数据门槛，起止边界及下一次切换，重叠课程保持到最后结束，假期/取消不请求，延时同步移动边界，学期结束/空课表无任务。
- Swift 新增 2 项过滤策略测试（课外下一节、主动展开、取消过滤、不凭空构造空/不可读课表），无 Swift/Xcode，未执行。
- 项目、版本快照、diff 检查通过。静态检查勿扰权限声明、规则配置入口、私有接收器、默认关闭及禁止调用全局切换接口通过。
- 无 Android SDK，平台代码/Manifest/Compose 未编译。系统 Focus Filter 发现、异步配置读回、建议/默认配置、系统勿扰授权/规则/撤权/删除/暂停、重启/锁屏/Doze/厂商节电和上课/下课真实效果未验收。UI 的确认弹窗及提醒页长内容沿用现有组件并可滚动，仍无大小屏/大字/浅深色截图审美证据。

B 的已要求源码范围已分别由三步覆盖；Siri/语音/通知/Live Activity 与上述系统能力的平台验收仍欠缺，B 不勾选、整批不可打包交付。下一轮可继续 C 的学习板块审计和实现，不反复重做已有源码。

接口依据：[Apple Focus Filter 示例](https://developer.apple.com/documentation/appintents/defining-your-app-s-focus-filter)、[current 的异步声明](https://developer.apple.com/documentation/appintents/setfocusfilterintent/current)、[Android AutomaticZenRule](https://developer.android.com/reference/android/app/AutomaticZenRule)、[NotificationManager](https://developer.android.com/reference/android/app/NotificationManager)。

待用户要求后再推送；iOS 待用户要求推送后云端构建。未访问 GitHub/GitLab、未推送或发布、未使用浏览器会话。
