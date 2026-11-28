export type WorkbranchRepo = {
	readonly name: string;
	readonly branch: string;
	readonly dirty: boolean;
	readonly ahead?: number;
	readonly behind?: number;
	readonly changedFiles?: number;
	readonly lastCommitSubject?: string;
	readonly lastCommitAt?: number;
	/** The task's own commits (base..HEAD), newest first, at most 3. */
	readonly recentCommits?: readonly WorkbranchCommit[];
};

export type WorkbranchCommit = {
	readonly subject: string;
	/** Epoch seconds. */
	readonly at: number;
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
 /** The last 24 hours of state changes; absent from older collectors. */
 readonly transitions?: readonly WorkbranchRuntimeTransition[];
 /** Seconds per state over the retained log; absent when nothing is logged. */
 readonly totals?: WorkbranchRuntimeTotals;
 /** The last few requests and replies, newest last; absent from older collectors. */
 readonly messages?: readonly WorkbranchRuntimeMessage[];
 /** When turns began in the last 3 hours, oldest first; absent from older collectors. */
 readonly turns?: readonly WorkbranchRuntimeTurn[];
 /** Tool calls in the last 3 hours, oldest first; absent from older collectors. */
 readonly calls?: readonly WorkbranchRuntimeCall[];
 /** How far the agent's todo list has come; absent without todos or from older collectors. */
 readonly todos?: WorkbranchRuntimeTodos;
 /** What the last request turn left once it ended; absent while it runs and from older collectors. */
 readonly lastTurn?: WorkbranchRuntimeTurnSummary;
};
export type WorkbranchRuntimeTurnSummary = {
 /** Epoch seconds the turn's request came in. */
 readonly startedAt: number;
 readonly filesChanged: number;
 /** From the edit input: exact for Codex patches, approximate for Claude Code edits. */
 readonly linesAdded: number;
 readonly linesRemoved: number;
 /** The turn's last test command: `unknown` when the provider did not say how it went. */
 readonly tests: "passed" | "failed" | "unknown" | "none";
 readonly commits: number;
};
export type WorkbranchRuntimeTodos = {
 readonly total: number;
 readonly done: number;
 /** The todo in progress, clipped and scrubbed; absent when none is. */
 readonly active?: string;
};
export type WorkbranchRuntimeTurn = {
 /** `prompt`: a request the user sent; `agent`: a subagent's report. */
 readonly kind: "prompt" | "agent";
 /** Epoch seconds. */
 readonly at: number;
};
export type WorkbranchRuntimeCall = {
 /** The provider's own tool name (`Bash`, `Edit`, `apply_patch`, `mcp__…`). */
 readonly tool: string;
 /** Names, never paths, of the files the call touched; absent when none. */
 readonly files?: readonly string[];
 /** Present and true when the provider reported the call failed. */
 readonly failed?: boolean;
 /** Epoch seconds the call started. */
 readonly at: number;
};
export type WorkbranchRuntimeMessage = {
 readonly kind: "prompt" | "response";
 /** Clipped and scrubbed like `prompt` and `response`. */
 readonly text: string;
 /** Epoch seconds. */
 readonly at: number;
};
export type WorkbranchRuntimeTransition = {
 readonly state: "running" | "waiting" | "finished" | "idle";
 /** Epoch seconds the state was entered. */
 readonly at: number;
 /** How a turn ended, on `finished` changes only. */
 readonly outcome?: string;
};
export type WorkbranchRuntimeTotals = {
 readonly running: number;
 readonly waiting: number;
 readonly finished: number;
};
export type WorkbranchRuntimeDocument = { readonly schemaVersion: 1; readonly sessions: readonly WorkbranchAgentSession[] };
