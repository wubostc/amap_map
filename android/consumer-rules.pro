# AMap native libraries use reflection/JNI with original Java class names.
# Keep these packages from being renamed or removed by R8 in release builds.
-keep class com.amap.** { *; }
-keep class com.autonavi.** { *; }
-keep class com.loc.** { *; }

-dontwarn com.amap.**
-dontwarn com.autonavi.**
-dontwarn com.loc.**
