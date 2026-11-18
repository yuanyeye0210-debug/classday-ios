# Classday 2.9.7 —— 开启 R8 后必须保留的反射入口。
#
# 说明：2.9.7 首次打开代码裁剪（isMinifyEnabled / isShrinkResources）。首轮冒烟在
# 模拟器上直接 FATAL：androidx.startup.InitializationProvider 起不来，
# 原因是 ML Kit 的 ComponentDiscovery 用反射 newInstance() 注册器，
# 而注册器内部用 WorkManager 的 Room 数据库，两者都被 R8 裁掉。
# 下面按"谁靠反射构造"分组保留，不要随手删。

-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod, AnnotationDefault

# ML Kit：ComponentDiscovery 反射实例化各 Registrar
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_chinese.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# ML Kit 内部用 WorkManager + Room，Room 生成的 *_Impl 由反射创建
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.work.ListenableWorker { *; }
-keepclassmembers class * extends androidx.work.ListenableWorker { <init>(...); }
-dontwarn androidx.work.**

# 应用自身：小组件 Receiver、TileService、闹钟广播都由系统按类名反射拉起
-keep class com.classday.app.widget.** { *; }
-keep class com.classday.app.platform.** { *; }
-keep class com.classday.app.ClassAlarmReceiver { *; }
-keep class com.classday.app.ReminderReceiver { *; }
-keep class com.classday.app.BootReceiver { *; }

# Glance 的 GlanceAppWidget / Receiver 也走反射
-keep class androidx.glance.** { *; }
-dontwarn androidx.glance.**

-dontwarn com.google.mlkit.**
