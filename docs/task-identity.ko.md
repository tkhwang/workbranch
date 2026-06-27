# Task identity와 branch 이름

[README](../README.ko.md) | [English](task-identity.md)

Task 생성은 configured base branch에 맞는 prompt 형태를 사용합니다.

`main`/`master` 계열 base에서는 `workbranch add`가 conventional task identity를 묻습니다.

| Prompt           | 예시    | 사용처               |
| ---------------- | ------- | -------------------- |
| Task type        | `feat`  | Git branch prefix    |
| Task detail name | `login` | folder/branch detail |

`workbranch`는 다음 값을 파생합니다.

- task folder: `feat-login`
- repo별 default Git branch: `feat/login`

모든 repo가 `feature/cpq` 같은 동일 parent feature base를 공유하면 conventional task type은 branch에 나타나지 않습니다. 이 경우 `workbranch add`는 task name만 묻고, 결과 branch의 `/`를 `-`로 바꾼 값을 folder 이름으로 사용합니다.

- task name: `login`
- task folder: `feature-cpq-login`
- repo별 default Git branch: `feature/cpq-login`

Interactive `workbranch add <name>`은 `<name>`을 수정 가능한 기본값으로 사용하면서 같은 base-aware prompt flow를 따릅니다. `main`/`master` base에서는 `Task type`과 `Task detail name [<name>]`을 묻고, shared parent feature base에서는 `Task name [<name>]`만 묻습니다.

`workbranch add feat-login`은 conventional task key의 direct shorthand로 계속 동작합니다. Parent feature base에서는 compatibility를 위해 explicit shorthand의 folder `feat-login`을 유지하면서 default branch를 `feature/cpq-login`으로 정합니다. `workbranch add feature-cpq-login` 같은 explicit parent-slug key도 허용되며 다시 `feature/cpq-login` branch로 resolve됩니다. Non-interactive script에서는 conventional `type-` prefix가 없는 task key도 계속 넘길 수 있고, 이 legacy explicit key는 compatibility를 위해 branch-prefix default를 유지합니다.

Folder 이름과 branch 이름은 별도 surface입니다. Folder는 path-safe해야 하고 Git branch는 보통 `/`를 사용하기 때문입니다. Repo별 task branch prompt에서 기본값은 여전히 overwrite할 수 있습니다.

기본적으로 `workbranch add`는 local `_base/<repo>` worktree의 현재 HEAD에서 task branch를 만듭니다. remote base branch를 자동으로 pull하지 않습니다. 최신 remote base에서 시작하려면 다음 순서로 실행하세요.

```bash
workbranch pull
workbranch add
```

다른 source ref에서 새 task branch를 시작하려면 `workbranch add [<task>] --from <ref>`를 사용하세요. 예를 들어 `workbranch add task1 --from feat/XXX`는 origin을 fetch한 뒤 `origin/feat/XXX`가 있으면 그것을 우선 사용하고, prompt로 정한 task branch 이름은 그대로 유지한 채 linked task worktree를 만듭니다. 이후 `workbranch status`는 여전히 task branch를 현재 local base와 비교하며, source ref는 생성 시점 정보일 뿐 지속적인 status 기준이 아닙니다.

작업 중에는 `workbranch refresh`로 remote base branch를 `_base/<repo>`에 pull한 다음, 갱신된 local base 기준으로 모든 task workspace를 update할 수 있습니다. 하나의 task만 갱신하려면 `workbranch refresh <task>`를 사용합니다. `refresh`는 먼저 대상 task worktree들이 update 가능한지 확인하므로, dirty 상태이거나 막힌 task가 있으면 base branch를 pull하기 전에 중단합니다.

repo를 다시 clone하지 않고 project 설정, base branch, IDE/terminal 실행 명령, repo별 setup command를 수정하려면 `workbranch config`를 사용합니다. base branch가 바뀌면 기존 `_base/<repo>` worktree를 fetch, checkout, fast-forward pull까지 해서 해당 branch로 맞춥니다. base branch만 수정하려면 `workbranch config base`를 사용합니다.
