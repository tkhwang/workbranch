# Changelog

## [2.2.0](https://github.com/tkhwang/workbranch/compare/workbranch-companion-v2.1.0...workbranch-companion-v2.2.0) (2026-06-18)


### Features

* **design:** update companion design for terminal HUD ([ff92672](https://github.com/tkhwang/workbranch/commit/ff9267211889f2621e20a63157b310a0d49b1f77))
* **design:** update companion design for terminal HUD ([cf82685](https://github.com/tkhwang/workbranch/commit/cf82685c92398438df13053e5b6a91cc9335324b))
* **release:** add release marker sync script ([00c8565](https://github.com/tkhwang/workbranch/commit/00c856557a05d833a62b339d0ad4a744dd03c156))


### Bug Fixes

* update sync-release-markers to support CRLF line endings and improve test robustness ([d6e4d40](https://github.com/tkhwang/workbranch/commit/d6e4d407c79f5be87d7c1e8be20adb4b7c760ff2))

## [2.1.0](https://github.com/tkhwang/workbranch/compare/workbranch-companion-v2.0.0...workbranch-companion-v2.1.0) (2026-06-17)


### Features

* **ui:** redesign companion app layout and summary ([24f4d51](https://github.com/tkhwang/workbranch/commit/24f4d51aff27da9b278e786f1eb3018401e72df1))
* **ui:** redesign companion app layout and summary ([cae49ca](https://github.com/tkhwang/workbranch/commit/cae49caded059a79be694c27263f14b2e5a81d7b))


### Bug Fixes

* revert version to 2.1.1, add DESIGN.md to release-please, and update Cargo.lock handling ([da77323](https://github.com/tkhwang/workbranch/commit/da773235f91a363fc1a5f2d917fa44e779637322))

## [2.0.0](https://github.com/tkhwang/workbranch/compare/workbranch-companion-v1.14.1...workbranch-companion-v2.0.0) (2026-06-17)


### ⚠ BREAKING CHANGES

* **design:** Visual design and color palette have been significantly altered. While no functional changes, the aesthetic is substantially different.

### Features

* **ui:** use DESIGN.md and update companion UI ([de04273](https://github.com/tkhwang/workbranch/commit/de042733e9eeb9a15981901280d464bbb776a0c0))


### Bug Fixes

* **watch_filter:** handle empty path events correctly ([0a6e91a](https://github.com/tkhwang/workbranch/commit/0a6e91a52d9edc71614076faf0c0917e06e7c68b))
* **watcher:** correctly filter ignored paths ([d25c758](https://github.com/tkhwang/workbranch/commit/d25c758826549c23ce6101844056e76fbd02c5d3)), closes [#123](https://github.com/tkhwang/workbranch/issues/123)


### Code Refactoring

* **design:** update design principles to Raycast-like aesthetic ([e3a3788](https://github.com/tkhwang/workbranch/commit/e3a3788e24306c1b09b7df70640c1d9691ff5488))

## [1.14.1](https://github.com/tkhwang/workbranch/compare/workbranch-companion-v1.14.0...workbranch-companion-v1.14.1) (2026-06-16)


### Bug Fixes

* **release:** ensure companion cask quits app on upgrade ([b4d8c36](https://github.com/tkhwang/workbranch/commit/b4d8c368792c19464a3d08691c6b3cc07cabe1ab))
* **release:** ensure companion cask quits app on upgrade ([0a6fff8](https://github.com/tkhwang/workbranch/commit/0a6fff8a4029757df52ca819032582a1dccb8a06))

## [1.14.0](https://github.com/tkhwang/workbranch/compare/workbranch-companion-v1.13.0...workbranch-companion-v1.14.0) (2026-06-16)


### Features

* **ci:** update ci workflows for monorepo structure ([7885c1a](https://github.com/tkhwang/workbranch/commit/7885c1ae4c68de1b8a6b2c05fe2faf010765a401))
* **ci:** update ci workflows for monorepo structure and refactor to use rust and react.js ([7489506](https://github.com/tkhwang/workbranch/commit/7489506233cb1d1dd8f1014c6622cabf01b6bbfd))
* **companion:** add activity store and universal build ([3b510c8](https://github.com/tkhwang/workbranch/commit/3b510c8902454959acfb2faa4597d7087fa054f5))
* **tauri:** add tauri app icons and update gitignore ([169c442](https://github.com/tkhwang/workbranch/commit/169c4424093497449cfcffb5dd2b250545329608))
