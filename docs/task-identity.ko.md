# Task identity와 branch 이름

[README](../README.ko.md) | [English](task-identity.md)

새 task 생성은 두 값을 묻습니다.

| Prompt           | 예시    | 사용처               |
| ---------------- | ------- | -------------------- |
| Task type        | `feat`  | Git branch prefix    |
| Task detail name | `login` | folder/branch detail |

`workbranch`는 다음 값을 파생합니다.

- task folder: `feat-login`
- repo별 default Git branch:
  - base `main` 또는 `master` -> `feat/login`
  - base `feature/cpq` -> `feature/cpq-login`

Folder 이름과 branch 이름은 분리됩니다. folder는 path-safe해야 하고 Git branch는 보통 `/`를 사용하기 때문입니다. `workbranch`는 folder-safe type/detail separator로 `-`를 사용하므로 `feat-login`은 `feat/login`의 task-folder 형태입니다. Repo별 task branch prompt에서 기본값은 여전히 overwrite할 수 있습니다.

Interactive `workbranch add <detail>`도 같은 생성 flow로 들어가며, `<detail>`을 Task detail name의 기본값으로 사용합니다. 예를 들어 `workbranch add login`은 Task type을 묻고 `login`을 수정 가능한 detail 기본값으로 보여주며 folder `feat-login`을 추천합니다. 이후 각 repo가 configured base branch 기준으로 task branch를 제안합니다. `workbranch add feat-login`은 conventional task key의 direct shorthand로 계속 동작합니다. Non-interactive script에서는 conventional `type-` prefix가 없는 task key도 계속 넘길 수 있고, 이 legacy explicit key는 compatibility를 위해 branch-prefix default를 유지합니다.

기본적으로 `workbranch add`는 local `_base/<repo>` worktree의 현재 HEAD에서 task branch를 만듭니다. remote base branch를 자동으로 pull하지 않습니다. 최신 remote base에서 시작하려면 다음 순서로 실행하세요.

```bash
workbranch pull
workbranch add
```

다른 source ref에서 새 task branch를 시작하려면 `workbranch add [<task>] --from <ref>`를 사용하세요. 예를 들어 `workbranch add task1 --from feat/XXX`는 origin을 fetch한 뒤 `origin/feat/XXX`가 있으면 그것을 우선 사용하고, prompt로 정한 task branch 이름은 그대로 유지한 채 linked task worktree를 만듭니다. 이후 `workbranch status`는 여전히 task branch를 현재 local base와 비교하며, source ref는 생성 시점 정보일 뿐 지속적인 status 기준이 아닙니다.

작업 중에는 `workbranch refresh`로 remote base branch를 `_base/<repo>`에 pull한 다음, 갱신된 local base 기준으로 모든 task workspace를 update할 수 있습니다. 하나의 task만 갱신하려면 `workbranch refresh <task>`를 사용합니다. `refresh`는 먼저 대상 task worktree들이 update 가능한지 확인하므로, dirty 상태이거나 막힌 task가 있으면 base branch를 pull하기 전에 중단합니다.

repo를 다시 clone하지 않고 project 설정, base branch, IDE/terminal 실행 명령, repo별 setup command를 수정하려면 `workbranch config`를 사용합니다. base branch가 바뀌면 기존 `_base/<repo>` worktree를 fetch, checkout, fast-forward pull까지 해서 해당 branch로 맞춥니다. base branch만 수정하려면 `workbranch config base`를 사용합니다.
