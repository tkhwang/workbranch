import {
	COMPANION_THEME_OPTIONS,
	type CompanionTheme,
} from "../application/preferences";

type AgentThemePickerProps = {
	readonly value: CompanionTheme;
	readonly onChange: (theme: CompanionTheme) => void;
};

export function AgentThemePicker({ value, onChange }: AgentThemePickerProps) {
	return (
		<fieldset className="agent-theme-picker" aria-label="Agent theme">
			{COMPANION_THEME_OPTIONS.map((option) => {
				const selected = option.value === value;
				return (
					<button
						aria-label={`Use ${option.label} theme`}
						aria-pressed={selected}
						className="agent-theme-button"
						data-active={selected ? "true" : "false"}
						key={option.value}
						onClick={() => onChange(option.value)}
						type="button"
					>
						{option.label}
					</button>
				);
			})}
		</fieldset>
	);
}
