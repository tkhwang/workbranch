import type {
	WorkbranchBaseRepo,
	WorkbranchListDocument,
	WorkbranchListGlobalDocument,
	WorkbranchRepo,
	WorkbranchTask,
} from "@workbranch/contract";

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isString(value: unknown): value is string {
	return typeof value === "string";
}

function isNonNegativeInteger(value: unknown): value is number {
	return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

function isOptionalNonNegativeInteger(value: unknown): boolean {
	return value === undefined || isNonNegativeInteger(value);
}

function isOptionalString(value: unknown): boolean {
	return value === undefined || isString(value);
}

function isInspectionError(
	value: unknown,
): value is WorkbranchBaseRepo["inspectionError"] {
	return (
		value === null ||
		value === "invalid-worktree" ||
		value === "git-read-failed"
	);
}

function isRepo(value: unknown): value is WorkbranchRepo {
	if (!isRecord(value)) {
		return false;
	}
	return (
		isString(value["name"]) &&
		isString(value["branch"]) &&
		typeof value["dirty"] === "boolean" &&
		isOptionalNonNegativeInteger(value["ahead"]) &&
		isOptionalNonNegativeInteger(value["behind"]) &&
		isOptionalNonNegativeInteger(value["changedFiles"]) &&
		isOptionalString(value["lastCommitSubject"]) &&
		isOptionalNonNegativeInteger(value["lastCommitAt"])
	);
}

function isTask(value: unknown): value is WorkbranchTask {
	if (!isRecord(value)) return false;
	return (
		isString(value["name"]) &&
		isString(value["path"]) &&
		isNonNegativeInteger(value["notiCount"]) &&
		Array.isArray(value["repos"]) &&
		value["repos"].every(isRepo)
	);
}

function isBaseRepo(value: unknown): value is WorkbranchBaseRepo {
	if (!isRecord(value)) {
		return false;
	}
	return (
		isString(value["name"]) &&
		isString(value["baseBranch"]) &&
		isString(value["branch"]) &&
		typeof value["present"] === "boolean" &&
		typeof value["dirty"] === "boolean" &&
		isNonNegativeInteger(value["changedFiles"]) &&
		typeof value["remoteAvailable"] === "boolean" &&
		isNonNegativeInteger(value["ahead"]) &&
		isNonNegativeInteger(value["behind"]) &&
		isInspectionError(value["inspectionError"])
	);
}

function isListDocument(value: unknown): value is WorkbranchListDocument {
	if (!isRecord(value)) {
		return false;
	}
	return (
		value["schemaVersion"] === 2 &&
		isString(value["project"]) &&
		isString(value["root"]) &&
		(value["baseRepos"] === undefined ||
			(Array.isArray(value["baseRepos"]) &&
				value["baseRepos"].every(isBaseRepo))) &&
		Array.isArray(value["tasks"]) &&
		value["tasks"].every(isTask)
	);
}

function isGlobalError(
	value: unknown,
): value is WorkbranchListGlobalDocument["errors"][number] {
	if (!isRecord(value)) {
		return false;
	}
	return isString(value["root"]) && isString(value["message"]);
}

function isGlobalDocument(
	value: unknown,
): value is WorkbranchListGlobalDocument {
	if (!isRecord(value)) {
		return false;
	}
	return (
		value["schemaVersion"] === 2 &&
		Array.isArray(value["projects"]) &&
		value["projects"].every(isListDocument) &&
		Array.isArray(value["errors"]) &&
		value["errors"].every(isGlobalError)
	);
}

export function parseGlobalDocument(raw: string): WorkbranchListGlobalDocument {
	const parsed: unknown = JSON.parse(raw);
	if (isRecord(parsed) && parsed["schemaVersion"] !== 2)
		throw new Error(
			"Update workbranch CLI and Companion together: incompatible schema version",
		);
	if (!isGlobalDocument(parsed)) {
		throw new Error("invalid workbranch global list document");
	}
	return parsed;
}

export function parseListDocument(raw: string): WorkbranchListDocument {
	const parsed: unknown = JSON.parse(raw);
	if (isRecord(parsed) && parsed["schemaVersion"] !== 2)
		throw new Error(
			"Update workbranch CLI and Companion together: incompatible schema version",
		);
	if (!isListDocument(parsed)) {
		throw new Error("invalid workbranch list document");
	}
	return parsed;
}

export function parseRuntimeDocument(
	raw: string,
): readonly import("../domain/model").AgentSession[] {
	const value: unknown = JSON.parse(raw);
	if (
		!isRecord(value) ||
		value["schemaVersion"] !== 1 ||
		!Array.isArray(value["sessions"])
	)
		throw new Error("Update runtime collector: incompatible snapshot");
	return value["sessions"].map((s: unknown) => {
		if (
			!isRecord(s) ||
			!["claude", "codex", "grok"].includes(String(s["provider"])) ||
			!["running", "waiting", "finished", "idle"].includes(
				String(s["state"]),
			) ||
			!["observed", "uncertain", "stale"].includes(String(s["observation"])) ||
			![
				"workspace",
				"sessionId",
				"agentId",
				"turnId",
				"reason",
				"prompt",
				"activity",
				"response",
				"outcome",
			].every((k) => typeof s[k] === "string") ||
			!isNonNegativeInteger(s["updatedAt"]) ||
			!isNonNegativeInteger(s["stateChangedAt"])
		)
			throw new Error("Invalid runtime session");
		return s as unknown as import("../domain/model").AgentSession;
	});
}
