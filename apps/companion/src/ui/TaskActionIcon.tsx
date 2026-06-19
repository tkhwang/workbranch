import type { TaskActionKind } from "./TaskRow";

export function TaskActionIcon({ kind }: { readonly kind: TaskActionKind }) {
	switch (kind) {
		case "ide":
			return (
				<svg
					aria-hidden="true"
					className="task-action-icon"
					viewBox="0 0 24 24"
				>
					<path d="M5 6h14v10H5z" />
					<path d="M9 20h6" />
					<path d="M12 16v4" />
				</svg>
			);
		case "terminal":
			return (
				<svg
					aria-hidden="true"
					className="task-action-icon"
					viewBox="0 0 24 24"
				>
					<path d="m7 8 4 4-4 4" />
					<path d="M13 16h5" />
				</svg>
			);
		case "finder":
			return (
				<svg
					aria-hidden="true"
					className="task-action-icon"
					viewBox="0 0 24 24"
				>
					<path d="M4.5 6.5h6l1.6 2H19.5v9H4.5z" />
					<path d="M4.5 8.5h15" />
				</svg>
			);
	}
}
