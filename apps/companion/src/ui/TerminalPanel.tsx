import type { ReactNode } from "react";
import type { CompanionTheme } from "../application/preferences";

export type TerminalPanelProps = {
	readonly theme: CompanionTheme;
	readonly label: string;
	readonly className?: string;
	readonly children: ReactNode;
};

export function TerminalPanel({
	theme,
	label,
	className,
	children,
}: TerminalPanelProps) {
	const classes = ["terminal-panel", className].filter(Boolean).join(" ");

	if (theme === "claude") {
		return (
			<fieldset className={classes} data-terminal-panel={theme}>
				<legend>{label}</legend>
				{children}
			</fieldset>
		);
	}

	return (
		<section className={classes} data-terminal-panel={theme}>
			<h2 className="terminal-panel-heading">{label}</h2>
			{children}
		</section>
	);
}
