import type { PlanStatus } from "../domain/model";

export type StatusTokenProps = {
	readonly status: PlanStatus;
};

const STATUS_LABELS: Record<PlanStatus, string> = {
	todo: "TODO",
	planning: "PLAN",
	"in-progress": "RUN",
	review: "REVIEW",
	blocked: "BLOCKED",
	done: "DONE",
};

export function StatusToken({ status }: StatusTokenProps) {
	return (
		<span className="status-token" data-status={status}>
			<span aria-hidden="true" className="status-token-marker" />
			<span className="status-token-label">{STATUS_LABELS[status]}</span>
		</span>
	);
}
