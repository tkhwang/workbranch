import {
	COMPANION_THEME_OPTIONS,
	type CompanionTheme,
} from "../application/preferences";
import { SegmentedControl } from "./SettingsLayout";

type AgentThemePickerProps = {
	readonly value: CompanionTheme;
	readonly onChange: (theme: CompanionTheme) => void;
};

const THEME_SEGMENTS = COMPANION_THEME_OPTIONS.map((option) => ({
	value: option.value,
	label: option.label,
	ariaLabel: `Use ${option.label} theme`,
}));

export function AgentThemePicker({ value, onChange }: AgentThemePickerProps) {
	return (
		<SegmentedControl
			label="Agent theme"
			onChange={onChange}
			options={THEME_SEGMENTS}
			value={value}
		/>
	);
}
