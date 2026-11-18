-keep class com.xclient.models.** { *; }

-keep class com.xclient.service.models.** { *; }

# Preserve classes used by flutter_rust_bridge FFI
-keep class * extends io.flutter.plugin.common.MethodChannel { *; }

# Keep platform view classes
-keep class io.flutter.plugin.platform.PlatformView { *; }

# Keep native library loading
-keep class com.xclient.core.CoreLib { *; }
