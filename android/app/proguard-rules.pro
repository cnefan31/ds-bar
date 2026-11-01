# DS Bar 发布构建的 ProGuard/R8 规则。

# --- Flutter ---
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# --- RemoteViews 自定义通知 ---
# RemoteViews 在系统进程里按名字反射调用控件方法（setTextViewText、
# setViewVisibility、setBackgroundResource 等），R8 若裁掉这些方法或控件类，
# 通知会在 StatusBar 里 inflate 失败并被静默丢弃。必须保留。
-keep class android.widget.RemoteViews { *; }
-keep class android.widget.TextView { *; }
-keep class android.widget.ImageView { *; }
-keep class android.widget.LinearLayout { *; }
-keep class android.view.View { *; }

# 通知相关入口
-keep class com.cnefan.ds_bar.BalanceNotification { *; }
-keep class com.cnefan.ds_bar.RefreshActionReceiver { *; }
-keep class com.cnefan.ds_bar.BalanceTileService { *; }
-keep class com.cnefan.ds_bar.RefreshWorker { *; }

# --- AndroidX WorkManager ---
# Worker 由系统按类名实例化，保留无参构造入口。
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.CoroutineWorker { *; }
-dontwarn androidx.work.**

# --- 保留注解与泛型签名，避免 JSON 反射出错 ---
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# --- org.json ---
# 项目里大量用 JSONObject.opt* 做防御式解析，不涉及反射，无需额外规则。

# 保留行号，便于线上崩溃定位
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# --- Room（WorkManager 用它持久化任务） ---
# Room 在编译期生成 *_Impl 类，运行时按约定名字反射实例化。
# R8 裁掉其无参构造会导致：
#   NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>
# 进而在 Application 启动时崩溃。
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.RoomDatabase { *; }
-dontwarn androidx.room.paging.**

# Room 生成的实现类统一保留（含所有 _Impl 后缀）
-keep class **_Impl { *; }

# Room 依赖注解处理器生成的元数据
-keep class androidx.room.** { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    public <init>();
}
