# RideX Android release signing

This folder holds the **release** PKCS#12 keystore used by CI so sideloaded APKs are **not** signed with the Android debug key (which Google Play Protect blocks/pauses).

- `ridex-release.p12` — release keystore  
- `key.properties` — passwords / alias for local & CI builds  

`scripts/patch_mobile_native.py` copies these into `android/app/` after `flutter create` and wires `signingConfigs.release`.

Keep this keystore stable. Changing it forces users to uninstall before updating.
