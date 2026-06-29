# android/app/proguard-rules.pro

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase / HTTP
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# Keep Dart entry points
-keep class * extends io.flutter.embedding.android.FlutterActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterFragment { *; }

# OkHttp (used internally by some plugins)
-dontwarn okhttp3.**
-dontwarn okio.**
