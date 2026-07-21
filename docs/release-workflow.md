# Release workflow

The `.github/workflows/release.yml` workflow publishes these assets for each
`v*` tag or manual release:

- `GangChat_v<version>.dmg`
- `GangChat_v<version>.exe`
- `GangChat-<version>-windows.zip`
- `GangChat_v<version>.apk`

## Android signing

Published APKs must use the same private key across releases so Android can
install a new version over the previous one. Configure these repository
secrets before running the release workflow:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded contents of the JKS keystore.
- `ANDROID_KEYSTORE_PASSWORD`: keystore password.
- `ANDROID_KEY_ALIAS`: release key alias.
- `ANDROID_KEY_PASSWORD`: release key password.

The workflow rejects missing or invalid signing settings instead of publishing
an APK with a temporary CI debug certificate. Keep the original keystore and
passwords backed up securely; losing them prevents future in-place upgrades.

The APK uses the workflow input as its Android `versionName`. Its numeric
`versionCode` is deterministic: `major * 1,000,000 + minor * 1,000 + patch`
(for example, `1.2.3` becomes `1002003`). Minor and patch components must each
fit in the range `0..999`, and the final value must fit Android's supported
positive version-code range. Version components use canonical decimal notation
without leading zeroes.

For local development, `flutter build apk --release` keeps the existing debug
signing fallback unless all four signing environment variables are provided.
The project's local/default build version is `1.0.0+1`, so ordinary Android
and Windows debug builds both report `1.0.0`; release builds override it with
the workflow input.
The keystore itself must never be committed; Android keystore file extensions
and `key.properties` are already ignored by `android/.gitignore`.
