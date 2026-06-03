# Changelog

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
