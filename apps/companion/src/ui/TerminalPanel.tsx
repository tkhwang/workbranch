import type { ReactNode } from "react";
import type { CompanionTheme } from "../application/preferences";

export type TerminalPanelProps = {
	readonly theme: CompanionTheme;
	readonly anatomy?: CompanionTheme;
	readonly label: string;
	readonly className?: string;
	readonly children: ReactNode;
};

export function TerminalPanel({
	theme,
	anatomy = theme,
	label,
	className,
	children,
}: TerminalPanelProps) {
	const classes = ["terminal-panel", className].filter(Boolean).join(" ");

	if (anatomy === "claude") {
		return (
			<fieldset
				className={classes}
				data-terminal-panel={theme}
				data-terminal-panel-anatomy={anatomy}
			>
				<legend>{label}</legend>
				{children}
			</fieldset>
		);
	}

	return (
		<section
			className={classes}
			data-terminal-panel={theme}
			data-terminal-panel-anatomy={anatomy}
		>
			<h2 className="terminal-panel-heading">{label}</h2>
			{children}
		</section>
	);
}
