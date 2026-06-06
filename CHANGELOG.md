# Changelog

## [1.3.0](https://github.com/tkhwang/workbranch/compare/v1.2.0...v1.3.0) (2026-06-06)


### Features

* add a task from remote branch ref ([fc6f903](https://github.com/tkhwang/workbranch/commit/fc6f903b6ce0739c43864ff189dc2949dc69e8cd))
* **add:** support creating task branches from a source ref ([603c45f](https://github.com/tkhwang/workbranch/commit/603c45f00cdee5ebc549fd9a7354ed54da3c1ef6))
* **status:** show remote diff for base worktrees ([8d0bb49](https://github.com/tkhwang/workbranch/commit/8d0bb49ccfc4faffdab13f124678aabbe9239cd1))


### Bug Fixes

* **add:** handle empty --from value and unset upstream ([0bb5669](https://github.com/tkhwang/workbranch/commit/0bb5669e4924f721a49e74b0a4584c330baba934))

## [1.2.0](https://github.com/tkhwang/workbranch/compare/v1.1.0...v1.2.0) (2026-06-06)


### Features

* **finder:** add xdg-open support for linux ([9d472b5](https://github.com/tkhwang/workbranch/commit/9d472b595f3d69bc322657b23434cac2e27e8b97))
* **tool:** enhance editor and terminal tool launching ([50f2f1e](https://github.com/tkhwang/workbranch/commit/50f2f1e797d3cc5d3ae94210a032260c42c7e6e9))
* **tool:** enhance editor and terminal tool launching ([cc7dc99](https://github.com/tkhwang/workbranch/commit/cc7dc99f4a777bd70022f0fb68d8ea803bee1587))

## [1.1.0](https://github.com/tkhwang/workbranch/compare/v1.0.0...v1.1.0) (2026-06-05)


### Features

* **cli:** enhance output with colors and improved layout ([37fca5a](https://github.com/tkhwang/workbranch/commit/37fca5abe0a1069926be1052efc7938e3620157b))
* **cli:** enhance output with colors and improved layout ([9e2aca7](https://github.com/tkhwang/workbranch/commit/9e2aca747fa88b6e8eb4ecbd9f88caf8f0a6ba3f)), closes [#123](https://github.com/tkhwang/workbranch/issues/123)


### Bug Fixes

* **display:** set term for pty tests ([27f6a00](https://github.com/tkhwang/workbranch/commit/27f6a003371a27d7fe19eceadbbee9fbe95ce2a8))

## [1.0.0](https://github.com/tkhwang/workbranch/compare/v0.5.0...v1.0.0) (2026-06-05)


### ⚠ BREAKING CHANGES

* **add:** The `workbranch resume <task>` command has been removed. Users should now use `workbranch add <task>` to create or re-attach to existing task workspaces.

### Features

* **branch:** implement explicit task branch names with per-repo meta… ([812a4de](https://github.com/tkhwang/workbranch/commit/812a4dee9f44a540c807c78f634e6f5e9151ff0d))
* **branch:** implement explicit task branch names with per-repo metadata storage and input validation ([aba9998](https://github.com/tkhwang/workbranch/commit/aba9998adafb6e72553348ebdcc03b1a190eb1e3))
* **tool:** add tool command - editor, terminal ([2f04671](https://github.com/tkhwang/workbranch/commit/2f04671caf9093fcbec965be149b477a328be557))
* **tool:** add tool command - editor, terminal ([a877962](https://github.com/tkhwang/workbranch/commit/a87796256df998da9b5d798f3615e6806159759a))


### Bug Fixes

* **path:** validate task workspace and worktree paths ([1ffa897](https://github.com/tkhwang/workbranch/commit/1ffa8976002ce15a6100018489d4ff375de5287f))


### Code Refactoring

* **add:** streamline task branch creation ([e700f55](https://github.com/tkhwang/workbranch/commit/e700f55b6c5a0c01643fbd301dc858999e593647))

## [0.5.0](https://github.com/tkhwang/workbranch/compare/v0.4.0...v0.5.0) (2026-06-04)


### Features

* **script:** allow workbranch init to clone missing base repositories and remove unused render script ([f9f6195](https://github.com/tkhwang/workbranch/commit/f9f6195fcddc85a46fbc73dfdc527c347c22f9a8))

## [0.4.0](https://github.com/tkhwang/workbranch/compare/v0.3.0...v0.4.0) (2026-06-04)


### Features

* **commands:** add `resume` command and update `add`/`remove` ([91628fd](https://github.com/tkhwang/workbranch/commit/91628fd6426b9fde012b47dd06bff25806cacc0b))
* **commands:** add `resume` command and update `add`/`remove` ([d9b5225](https://github.com/tkhwang/workbranch/commit/d9b522597d341eaa1c660d0ac1d67ce7aca30ff3))
* **workbranch:** improve stale task directory handling ([f4945fc](https://github.com/tkhwang/workbranch/commit/f4945fc7619f21950661075dd778e74c8766f4f4))

## [0.3.0](https://github.com/tkhwang/workbranch/compare/v0.2.0...v0.3.0) (2026-06-03)


### Features

* **config:** reject changing main worktrees dir or branch prefix ([47dff7d](https://github.com/tkhwang/workbranch/commit/47dff7d8f5d43c2cbab3afe9433ca3b8b61c1310))
* **config:** update config command ([52f516f](https://github.com/tkhwang/workbranch/commit/52f516f79d443d40d755c2bc9c259cf08d5f00fd))

## [0.2.0](https://github.com/tkhwang/workbranch/compare/v0.1.0...v0.2.0) (2026-06-02)


### Features

* **add:** branch new tasks from local base HEAD ([8fe36d5](https://github.com/tkhwang/workbranch/commit/8fe36d53e257aa866973a46dc79f2c304cb16eb8))
* **add:** reuse existing task branch on add ([3821491](https://github.com/tkhwang/workbranch/commit/382149118bd3f2f08af00c351712c76115c07763))
* **build:** implement modular source and single-file distribution ([9659bcf](https://github.com/tkhwang/workbranch/commit/9659bcf28253c11dcaa1c2a28e009e8a354c6804))
* **cli:** enhance interactive init experience ([67fe642](https://github.com/tkhwang/workbranch/commit/67fe642c3e910de6cf833a02c0a805e60f4a3948))
* **cli:** implement core monotree mvp commands ([cf959a1](https://github.com/tkhwang/workbranch/commit/cf959a16ebb1c6878eb671e3737d8214ca40c360))
* **cli:** implement stacked git workflow ([67fe642](https://github.com/tkhwang/workbranch/commit/67fe642c3e910de6cf833a02c0a805e60f4a3948))
* **cli:** introduce `monotree config` command ([525b877](https://github.com/tkhwang/workbranch/commit/525b877b960c4e2455f0912a039c04d769ab6a29))
* **cli:** introduce git workflow commands ([67fe642](https://github.com/tkhwang/workbranch/commit/67fe642c3e910de6cf833a02c0a805e60f4a3948))
* **config:** add repo-level setup commands ([0f8651f](https://github.com/tkhwang/workbranch/commit/0f8651f6ce1a4e98ab5945df7816c5d64991bf4f))
* **config:** add repo-level setup commands ([115d5a8](https://github.com/tkhwang/workbranch/commit/115d5a89f2596d0019c5ae2bb1d809bb75d287e1))
* **config:** allow legacy config to be used without rewrite ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* implement basic functionality ([70acc44](https://github.com/tkhwang/workbranch/commit/70acc44fd9fd125eacd9da84a4f7c70652c4367d))
* **installer:** require WORKBRANCH_RAW_BASE_URL for standalone installs ([8fe36d5](https://github.com/tkhwang/workbranch/commit/8fe36d53e257aa866973a46dc79f2c304cb16eb8))
* **project:** add task setup command ([a081ecc](https://github.com/tkhwang/workbranch/commit/a081ecc359be83779e5bf0d17ccd28f3be3bbb54))
* **project:** initialize monotree project structure ([cc53c4f](https://github.com/tkhwang/workbranch/commit/cc53c4f5d46ed04a65d183fc1e570394bbf4b318))
* **pull:** add preflight check for base worktree branch ([8fe36d5](https://github.com/tkhwang/workbranch/commit/8fe36d53e257aa866973a46dc79f2c304cb16eb8))
* rebranding to tasktree ([9099775](https://github.com/tkhwang/workbranch/commit/90997755d9743cc7a6e19b17841cd056bb102b44))
* **release:** automate homebrew and curl installer releases ([5c0dda9](https://github.com/tkhwang/workbranch/commit/5c0dda94219758d348f6dd49276f797ffd72ffc2))
* **release:** automate homebrew and curl installer releases ([be605d3](https://github.com/tkhwang/workbranch/commit/be605d33724a63743f3e47272bb8220361873917))
* **update:** add preflight checks for base worktree ([8fe36d5](https://github.com/tkhwang/workbranch/commit/8fe36d53e257aa866973a46dc79f2c304cb16eb8))


### Bug Fixes

* **add:** improve rollback of created worktrees and branches on failure ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* **ci:** update homebrew bump workflow ([77a7ef2](https://github.com/tkhwang/workbranch/commit/77a7ef2c5a786bc84a5e8cc36241503e3bfb7c05))
* **config:** improve validation and error handling ([67fe642](https://github.com/tkhwang/workbranch/commit/67fe642c3e910de6cf833a02c0a805e60f4a3948))
* **init:** ensure base repo path is a git repository ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* **init:** reject existing non-directory base targets ([79499f7](https://github.com/tkhwang/workbranch/commit/79499f7dbad36dff8260d64b3b9ff64d2092d9f4))
* **prompts:** handle EOF during required prompt ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* **remove:** gracefully handle missing worktrees and removal failures ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* **setup:** improve task setup error reporting and configuration ([dd67fd4](https://github.com/tkhwang/workbranch/commit/dd67fd452c697dfc9b01dd46e0550701f3d320f1))
* **status:** enhance task workspace filtering and display ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* **update:** allow base worktrees with gitfile ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
* **validation:** improve name validation to reject dot and dot-dot ([a680e1c](https://github.com/tkhwang/workbranch/commit/a680e1c78e31b76a8180e4be829137fce58b5abd))
