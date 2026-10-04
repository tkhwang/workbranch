import type { AgentState } from "../domain/model";
import { runtimeLabels } from "../domain/model";
export function StatusToken({ status }: { readonly status: AgentState }) {
	return (
		<span className="status-token" data-status={status}>
			<span aria-hidden="true" className="status-token-marker" />
			{runtimeLabels[status]}
		</span>
	);
}
