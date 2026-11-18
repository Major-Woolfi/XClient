-keep class com.xclient.models.** { *; }

-keep class com.xclient.service.models.** { *; }

# Preserve classes used by flutter_rust_bridge FFI
-keep class com.xclient.rust_api.** { *; }
-keep class * extends io.flutter.plugin.common.MethodChannel { *; }

# Keep native library classes
-keep class io.flutter.plugin.platform.PlatformView { *; }

# Don't shrink native libs
-keep class librust_api.** { *; }
