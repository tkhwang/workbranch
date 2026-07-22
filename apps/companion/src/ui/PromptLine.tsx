import type { ReactNode } from "react";
import type { CompanionTheme } from "../application/preferences";

export type PromptLineProps = {
	readonly theme: CompanionTheme;
	readonly current?: boolean;
	readonly children: ReactNode;
};

export function PromptLine({
	theme,
	current = false,
	children,
}: PromptLineProps) {
	return (
		<div
			className="prompt-line"
			data-current={current ? "true" : "false"}
			data-prompt-theme={theme}
		>
			<span aria-hidden="true" className="prompt-marker">
				{theme === "claude" ? "❯" : "›"}
			</span>
			<span className="prompt-content">{children}</span>
		</div>
	);
}
