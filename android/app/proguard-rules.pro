# Release builds run R8 in full mode, which strips classes and constructors
# that are only reached via reflection. Keep what the plugins instantiate
# reflectively.

# workmanager: androidx.work creates its Room database via reflection;
# without this the app crashes at startup with
# NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>[].
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# flutter_local_notifications: scheduled notifications are (de)serialized
# with Gson using generic types, which R8 full mode breaks.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*
