import type {
	WorkbranchListDocument,
	WorkbranchListGlobalDocument,
} from "@workbranch/contract";
import type { BaseRepo, GlobalState, Project, Task } from "../domain/model";

function mapTask(dto: WorkbranchListDocument["tasks"][number]): Task {
	return {
		name: dto.name,
		path: dto.path,
		notiCount: dto.notiCount,
		repos: dto.repos.map((repo) => ({
			name: repo.name,
			branch: repo.branch,
			dirty: repo.dirty,
			activityAvailable: repo.changedFiles !== undefined,
			ahead: repo.ahead ?? 0,
			behind: repo.behind ?? 0,
			changedFiles: repo.changedFiles ?? 0,
			lastCommitSubject: repo.lastCommitSubject ?? "",
			lastCommitAt: repo.lastCommitAt ?? 0,
		})),
		updatedAt: Math.max(0, ...dto.repos.map((repo) => repo.lastCommitAt ?? 0)),
	};
}

function mapBaseRepo(
	dto: NonNullable<WorkbranchListDocument["baseRepos"]>[number],
): BaseRepo {
	return {
		name: dto.name,
		baseBranch: dto.baseBranch,
		branch: dto.branch,
		present: dto.present,
		dirty: dto.dirty,
		changedFiles: dto.changedFiles,
		remoteAvailable: dto.remoteAvailable,
		ahead: dto.ahead,
		behind: dto.behind,
		inspectionError: dto.inspectionError,
	};
}

export function mapListDocumentToProject(dto: WorkbranchListDocument): Project {
	return {
		name: dto.project,
		root: dto.root,
		tasks: dto.tasks.map(mapTask),
		baseRepos: (dto.baseRepos ?? []).map(mapBaseRepo),
	};
}

export function mapGlobalDocumentToState(
	dto: WorkbranchListGlobalDocument,
): GlobalState {
	return {
		projects: dto.projects.map(mapListDocumentToProject),
		errors: dto.errors.map((error) => ({
			root: error.root,
			message: error.message,
		})),
	};
}
