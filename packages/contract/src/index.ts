export type WorkbranchRepo = {
	readonly name: string;
	readonly branch: string;
	readonly dirty: boolean;
	readonly ahead?: number;
	readonly behind?: number;
	readonly changedFiles?: number;
	readonly lastCommitSubject?: string;
	readonly lastCommitAt?: number;
};

export type WorkbranchTask = {
 readonly name: string;
 readonly path: string;
 readonly notiCount: number;
 readonly repos: readonly WorkbranchRepo[];
};

export type WorkbranchBaseRepo = {
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

export type WorkbranchListDocument = {
	readonly schemaVersion: 2;
	readonly project: string;
	readonly root: string;
	readonly baseRepos?: readonly WorkbranchBaseRepo[];
	readonly tasks: readonly WorkbranchTask[];
};

export type WorkbranchGlobalError = {
	readonly root: string;
	readonly message: string;
};

export type WorkbranchListGlobalDocument = {
	readonly schemaVersion: 2;
	readonly projects: readonly WorkbranchListDocument[];
	readonly errors: readonly WorkbranchGlobalError[];
};

export type WorkbranchAgentSession = {
 readonly workspace: string;
 readonly provider: "claude" | "codex" | "grok";
 readonly sessionId: string;
 readonly agentId: string;
 readonly turnId: string;
 readonly state: "running" | "waiting" | "finished" | "idle";
 readonly observation: "observed" | "uncertain" | "stale";
 readonly reason: string;
 readonly prompt: string;
 readonly activity: string;
 readonly response: string;
 readonly updatedAt: number;
 readonly stateChangedAt: number;
 readonly outcome: string;
};
export type WorkbranchRuntimeDocument = { readonly schemaVersion: 1; readonly sessions: readonly WorkbranchAgentSession[] };
