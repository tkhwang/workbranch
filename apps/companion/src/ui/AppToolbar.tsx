type Props = {
	readonly onRefresh: () => void;
	readonly onQuit: () => void;
};

export function AppToolbar({ onRefresh, onQuit }: Props) {
	return (
		<div className="toolbar" aria-label="Companion controls" role="toolbar">
			<button
				type="button"
				className="toolbar-button refresh-button"
				onClick={onRefresh}
				aria-label="Refresh tasks"
			>
				<svg aria-hidden="true" className="toolbar-icon" viewBox="0 0 24 24">
					<path d="M20 6.5v5h-5" />
					<path d="M4 17.5v-5h5" />
					<path d="M18.2 9A7 7 0 0 0 6.6 6.4L4 8.8" />
					<path d="M5.8 15a7 7 0 0 0 11.6 2.6l2.6-2.4" />
				</svg>
			</button>
			<button
				type="button"
				className="toolbar-button quit-button"
				onClick={onQuit}
				aria-label="Quit Companion"
			>
				<svg aria-hidden="true" className="toolbar-icon" viewBox="0 0 24 24">
					<path d="M12 3.5v7" />
					<path d="M7.4 6.8a7 7 0 1 0 9.2 0" />
				</svg>
			</button>
		</div>
	);
}
