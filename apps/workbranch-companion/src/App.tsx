import { useCallback, useEffect, useState } from "react";
import { buildMenuModel, type MenuModel } from "./application/state";
import type { GlobalState } from "./domain/model";
import { refreshStatus } from "./infrastructure/tauriClient";
import { TaskRow } from "./ui/TaskRow";

const EMPTY_STATE: GlobalState = { projects: [], errors: [] };

export function App() {
	const [state, setState] = useState<GlobalState>(EMPTY_STATE);
	const [status, setStatus] = useState("Ready");
	const model: MenuModel = buildMenuModel(state);

	const refresh = useCallback(async () => {
		try {
			const next = await refreshStatus();
			setState(next);
			setStatus("Updated");
		} catch (error) {
			if (error instanceof Error) {
				setStatus(error.message);
			} else {
				setStatus(String(error));
			}
		}
	}, []);

	useEffect(() => {
		void refresh();
	}, [refresh]);

	return (
		<main>
			<header>
				<h1>{model.title}</h1>
				<button
					type="button"
					onClick={() => void refresh()}
					aria-label="refresh"
				>
					↻
				</button>
			</header>
			<section>
				{model.rows.length === 0 ? (
					<p className="empty">No workbranch tasks configured.</p>
				) : null}
				{model.rows.map((row) => (
					<TaskRow
						key={`${row.root}-${row.task.name}`}
						project={row.project}
						task={row.task}
						expanded={row.expanded}
					/>
				))}
			</section>
			{model.errors.map((error) => (
				<p className="error" key={error.root}>
					{error.root}: {error.message}
				</p>
			))}
			<footer>{status}</footer>
		</main>
	);
}
