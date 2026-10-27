# :vault consumer rules (applied to the host app's R8 run).

# JNA (net.java.dev.jna:jna AAR): libjnidispatch.so resolves com.sun.jna classes, fields and methods by name through
# JNI (FindClass / GetMethodID / GetFieldID), and JNA reflects over Library interfaces, Structure fields and Callback
# implementations. Keep JNA whole, plus the public members of every JNA subtype (Structure, PointerType, Callback…).
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
# JNA's AWT helpers (Native.getComponentID / getWindowID, Native.AWT) reference java.awt, which Android does not ship;
# they are never called on Android.
-dontwarn java.awt.**

# SodiumScryptEngine binds libsodium's crypto_pwhash_scryptsalsa208sha256_ll through a JNA interface proxy: JNA maps
# each Java method *name* to the native symbol, so the interface and its method names must survive.
-keep interface io.ownbit.core.crypto.kdf.SodiumScryptLibrary { *; }
-keep interface * extends com.sun.jna.Library { *; }

# lazysodium-android is only the carrier of libsodium.so; its Java API is unused (it cannot reach the _ll function),
# so it gets no keep rule and R8 removes it.
# BouncyCastle (SCrypt, KeccakDigest, HMac, …) is called directly — no JCA provider / Class.forName lookup — so it
# needs no keep rule either.
