# Tink (pulled in by security-crypto) references these annotation types.
# They are compile-only and are not shipped, so R8 must not fail the release build.
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
