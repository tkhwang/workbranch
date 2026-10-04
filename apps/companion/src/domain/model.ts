export type Repo = {
	readonly name: string;
	readonly branch: string;
	readonly dirty: boolean;
	readonly activityAvailable: boolean;
	readonly ahead: number;
	readonly behind: number;
	readonly changedFiles: number;
	readonly lastCommitSubject: string;
	readonly lastCommitAt: number;
};

export type Task = {
	readonly name: string;
	readonly path: string;
	readonly notiCount: number;
	readonly repos: readonly Repo[];
	readonly updatedAt: number;
};

export type BaseRepo = {
	readonly name: string;
	readonly baseBranch: string;
	readonly branch: string;
	readonly present: boolean;
	readonly dirty: boolean;
	readonly changedFiles: number;
	readonly remoteAvailable: boolean;
	readonly ahead: number;
	readonly behind: number;
	readonly inspectionError: "invalid-worktree" | "git-read-failed" | null;
};

export type BaseRepoHealth = "ok" | "warn" | "bad";
export type BaseRepoAction = "pull" | "push" | "check";

export function baseRepoHealth(repo: BaseRepo): BaseRepoHealth {
	if (repo.inspectionError !== null) return "bad";
	if (!repo.present || !repo.remoteAvailable) return "bad";
	if (repo.branch !== repo.baseBranch) return "bad";
	if (repo.ahead > 0 && repo.behind > 0) return "bad";
	if (repo.dirty || repo.ahead > 0 || repo.behind > 0) return "warn";
	return "ok";
}

export function baseRepoAction(repo: BaseRepo): BaseRepoAction | undefined {
	if (baseRepoHealth(repo) === "bad") return "check";
	if (repo.dirty && repo.behind > 0) return "check";
	if (repo.behind > 0) return "pull";
	if (repo.ahead > 0) return "push";
	return undefined;
}

export type Project = {
	readonly name: string;
	readonly root: string;
	readonly tasks: readonly Task[];
	readonly baseRepos: readonly BaseRepo[];
};

export type GlobalError = {
	readonly root: string;
	readonly message: string;
};

export type GlobalState = {
	readonly projects: readonly Project[];
	readonly errors: readonly GlobalError[];
};

export const MATRIX_COLUMNS = [
	"waiting",
	"running",
	"finished",
	"unknown",
] as const;
export type MatrixColumn = (typeof MATRIX_COLUMNS)[number];
export type AgentState = "running" | "waiting" | "finished" | "idle";
export type AgentSession =
	import("@workbranch/contract").WorkbranchAgentSession;

export const runtimeLabels = {
	waiting: "내 응답 대기",
	running: "실행 중",
	finished: "턴 종료",
	unknown: "관측 불명",
	idle: "비활성",
} as const;
export function sessionKey(s: AgentSession): string {
	return JSON.stringify([s.workspace, s.provider, s.sessionId, s.agentId]);
}
