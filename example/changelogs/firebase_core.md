## 5.2.0

 - **FIX**(app_check,apple): use the provider passed to activate() on Flutter 3.50 ([#18968](https://github.com/firebase/flutterfire/issues/18968)). ([d0fec9cc](https://github.com/firebase/flutterfire/commit/d0fec9cc817eb9d8e2cf72b543a2460fc3f66e2d))
 - **FIX**: pass analyze and format on Flutter 3.50 ([#18950](https://github.com/firebase/flutterfire/issues/18950)). ([e5339880](https://github.com/firebase/flutterfire/commit/e53398808f6d78b293d4ac1455f296b9257a096d))
 - **FEAT**(android): detect built-in Kotlin instead of checking the AGP version ([#18355](https://github.com/firebase/flutterfire/issues/18355)). ([4376b824](https://github.com/firebase/flutterfire/commit/4376b824405005092630aef97a5b7f31a394aaa7))
 - **FEAT**(core): bump Firebase Android SDK to 35.2.0 ([#18960](https://github.com/firebase/flutterfire/issues/18960)). ([fd7d1164](https://github.com/firebase/flutterfire/commit/fd7d1164a81237f7718360cd0fd504b6df1982fc))
 - **FEAT**(android): migrate plugins to built-in Kotlin on Flutter 3.44 ([#18922](https://github.com/firebase/flutterfire/issues/18922)). ([1abe0561](https://github.com/firebase/flutterfire/commit/1abe05614d03f22782f597f847c1fc9c8c57f016))

## 5.1.0

 - **FIX**(android): replace Groovy space-assignment in plugin build.gradle files ([#18837](https://github.com/firebase/flutterfire/issues/18837)). ([09e913ac](https://github.com/firebase/flutterfire/commit/09e913acd98fa25ea6ff547141e7caf421b7b02d))
 - **FEAT**(core): bump Firebase Android SDK to 35.0.2 ([#18812](https://github.com/firebase/flutterfire/issues/18812)). ([cb3cc4b6](https://github.com/firebase/flutterfire/commit/cb3cc4b6bed7aa0ca916d98abb11275fbfe0728f))
 - **FEAT**(core): bump Firebase Android SDK to 35.0.1 ([#18808](https://github.com/firebase/flutterfire/issues/18808)). ([a0e08589](https://github.com/firebase/flutterfire/commit/a0e08589bc9d401067dd1a87a8ca5c0c2d205698))

## 5.0.0

> Note: This release has breaking changes.

 - **FIX**(core): use valid-format placeholder options for demoProjectId apps ([#18792](https://github.com/firebase/flutterfire/issues/18792)). ([05b647f1](https://github.com/firebase/flutterfire/commit/05b647f1559ceeb1376cdacb4de7c0e45ee640f9))
 - **FIX**(apple): build on Firebase Apple SDK 13 and require macOS 11 for Swift packages ([#18783](https://github.com/firebase/flutterfire/issues/18783)). ([aca14eab](https://github.com/firebase/flutterfire/commit/aca14eab5305d80011af473bc7dd289ef71b75e8))
 - **FIX**(android): build on Firebase BoM 35 and require minSdk 24 ([#18782](https://github.com/firebase/flutterfire/issues/18782)). ([7555707d](https://github.com/firebase/flutterfire/commit/7555707dec23382dfce1e7841c00446a21c9a406))
 - **FEAT**(core): bump Firebase C++ SDK to 14.0.0 ([#18799](https://github.com/firebase/flutterfire/issues/18799)). ([2fa3dd52](https://github.com/firebase/flutterfire/commit/2fa3dd52eb681d174a58e9e88b566f5e2b701c96))
 - **FEAT**(core): bump Firebase C++ SDK to 13.13.0 ([#18696](https://github.com/firebase/flutterfire/issues/18696)). ([ae76a9f3](https://github.com/firebase/flutterfire/commit/ae76a9f325df79abbcd5537ebcb7bc6a823289f4))
 - **BREAKING** **FEAT**: bump Firebase iOS SDK to 13.0.0 ([#18771](https://github.com/firebase/flutterfire/issues/18771)). ([dbf7f754](https://github.com/firebase/flutterfire/commit/dbf7f7543a37386f7e8e314d8344be82b0483b77))
 - **BREAKING** **FEAT**: bump Firebase Android SDK to 35.0.0 ([#18767](https://github.com/firebase/flutterfire/issues/18767)). ([90c22c8d](https://github.com/firebase/flutterfire/commit/90c22c8dd99d51ae6d98b37e2a6c4d991159375a))

## 4.15.0

 - **FEAT**(core): bump Firebase iOS SDK to 12.19.0 ([#18683](https://github.com/firebase/flutterfire/issues/18683)). ([35e39637](https://github.com/firebase/flutterfire/commit/35e39637f4cbef0d70043047f80d6f6e80daf8fe))
 - **FEAT**(core): bump Firebase Android SDK to 34.19.0 ([#18678](https://github.com/firebase/flutterfire/issues/18678)). ([fbf39e96](https://github.com/firebase/flutterfire/commit/fbf39e96a4cacff809f32ca3be87358f9ea038da))
 - **FEAT**(core): bump Firebase C++ SDK to 13.12.0 ([#18618](https://github.com/firebase/flutterfire/issues/18618)). ([d54b9308](https://github.com/firebase/flutterfire/commit/d54b93083c33d845873b11a901b9c469538b810f))

## 4.14.0

 - **REFACTOR**(core,android): migrate native implementation to Kotlin ([#18570](https://github.com/firebase/flutterfire/issues/18570)). ([7a0f5856](https://github.com/firebase/flutterfire/commit/7a0f5856cbb2ae64c530dcbdb43b03d43912465c))
 - **REFACTOR**(core,apple): migrate iOS/macOS plugin implementation to Swift ([#18569](https://github.com/firebase/flutterfire/issues/18569)). ([3b9a655b](https://github.com/firebase/flutterfire/commit/3b9a655b8ac8ac5f6efa23ea63e210b597f2ec02))
 - **FIX**(ci): bump Kotlin Gradle plugin to 2.3.0 ([#18600](https://github.com/firebase/flutterfire/issues/18600)). ([4c3865e2](https://github.com/firebase/flutterfire/commit/4c3865e2e56bf59904a9f48a6e70f0f963df2cda))
 - **FIX**(ci): align Android toolchain and analyzer with Flutter 3.47 ([#18566](https://github.com/firebase/flutterfire/issues/18566)). ([87ace849](https://github.com/firebase/flutterfire/commit/87ace8496fec75c461f3b29a9b8a85d46e286957))
 - **FEAT**(core): bump Firebase Android SDK to 34.18.0 ([#18597](https://github.com/firebase/flutterfire/issues/18597)). ([9bc9d9ce](https://github.com/firebase/flutterfire/commit/9bc9d9ce406e868a958f6e36b2a07682834d0458))
 - **FEAT**: bump Firebase iOS SDK to 12.18.0 ([#18596](https://github.com/firebase/flutterfire/issues/18596)). ([07febc37](https://github.com/firebase/flutterfire/commit/07febc37617ab8b4f6f06e7208baa6a15ce2ef70))
 - **FEAT**(core): bump Firebase C++ SDK to 13.11.0 ([#18599](https://github.com/firebase/flutterfire/issues/18599)). ([9a357750](https://github.com/firebase/flutterfire/commit/9a357750b28c9b9a5cb4c64e13ea497616a39a22))
