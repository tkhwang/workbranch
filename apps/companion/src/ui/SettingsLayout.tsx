import type { ReactNode } from "react";
import { SettingsIcon, type SettingsIconName } from "./SettingsIcon";
import { type SettingsCategory, settingsEyebrow } from "./SettingsNav";

export type SettingsTone = "neutral" | "success" | "notice" | "danger";

type SettingsPageProps = {
	readonly category: SettingsCategory;
	readonly title: string;
	readonly description: string;
	/** Page-wide control beside the heading, such as a status re-check. */
	readonly action?: ReactNode;
	readonly children: ReactNode;
};

/** One Settings tab: numbered heading, then its groups. */
export function SettingsPage({
	category,
	title,
	description,
	action,
	children,
}: SettingsPageProps) {
	const eyebrow = settingsEyebrow(category);
	return (
		<section aria-label={eyebrow} className="settings-page">
			<header className="settings-page-header">
				<div className="settings-page-heading">
					<p className="settings-page-eyebrow">{eyebrow}</p>
					<h2>{title}</h2>
					<p className="settings-page-description">{description}</p>
				</div>
				{action}
			</header>
			{children}
		</section>
	);
}

type SettingsGroupProps = {
	readonly label: string;
	readonly ariaLabel?: string;
	readonly action?: ReactNode;
	readonly children: ReactNode;
};

/** A small label above a rounded card of rows. */
export function SettingsGroup({
	label,
	ariaLabel = label,
	action,
	children,
}: SettingsGroupProps) {
	return (
		<section aria-label={ariaLabel} className="settings-group">
			<div className="settings-group-header">
				<h3>{label}</h3>
				{action}
			</div>
			<div className="settings-card">{children}</div>
		</section>
	);
}

type SettingsRowProps = {
	readonly title: string;
	readonly description?: ReactNode;
	/** Makes the title the control's label. */
	readonly htmlFor?: string;
	readonly badge?: ReactNode;
	/** Puts the control on its own full-width line under the copy. */
	readonly stacked?: boolean;
	/** Full-width content under the row, such as an action's result. */
	readonly extra?: ReactNode;
	readonly children?: ReactNode;
};

/** Title and description on the left, the control on the right. */
export function SettingsRow({
	title,
	description,
	htmlFor,
	badge,
	stacked = false,
	extra,
	children,
}: SettingsRowProps) {
	return (
		<div className="settings-row" data-stacked={stacked ? "true" : undefined}>
			<div className="settings-row-copy">
				<div className="settings-row-title">
					{htmlFor === undefined ? (
						<strong>{title}</strong>
					) : (
						<label htmlFor={htmlFor}>{title}</label>
					)}
					{badge}
				</div>
				{description === undefined ? null : (
					<div className="settings-row-description">{description}</div>
				)}
			</div>
			{children === undefined ? null : (
				<div className="settings-row-control">{children}</div>
			)}
			{extra ? <div className="settings-row-extra">{extra}</div> : null}
		</div>
	);
}

type SettingsNoteProps = {
	readonly icon?: SettingsIconName;
	readonly tone?: SettingsTone;
	readonly role?: "alert" | "status" | undefined;
	readonly action?: ReactNode;
	readonly children: ReactNode;
};

/** A status line with an optional icon and the button that settles it. */
export function SettingsNote({
	icon,
	tone = "neutral",
	role,
	action,
	children,
}: SettingsNoteProps) {
	return (
		<div className="settings-note" data-tone={tone} role={role}>
			{icon ? <SettingsIcon name={icon} /> : null}
			<div className="settings-note-text">{children}</div>
			{action}
		</div>
	);
}

export function SettingsBadge({
	tone = "neutral",
	children,
}: {
	readonly tone?: SettingsTone;
	readonly children: ReactNode;
}) {
	return (
		<span className="settings-badge" data-tone={tone}>
			{children}
		</span>
	);
}

export type SegmentOption<T extends string> = {
	readonly value: T;
	readonly label: string;
	readonly ariaLabel?: string;
};

type SegmentedControlProps<T extends string> = {
	readonly label: string;
	readonly options: readonly SegmentOption<T>[];
	readonly value: T;
	readonly onChange: (value: T) => void;
	readonly disabled?: boolean;
	/** Spreads the segments over the full width in equal parts. */
	readonly stretch?: boolean;
};

export function SegmentedControl<T extends string>({
	label,
	options,
	value,
	onChange,
	disabled = false,
	stretch = false,
}: SegmentedControlProps<T>) {
	return (
		<fieldset
			aria-label={label}
			className="settings-segmented"
			data-stretch={stretch ? "true" : undefined}
			disabled={disabled}
		>
			{options.map((option) => {
				const selected = option.value === value;
				return (
					<button
						aria-label={option.ariaLabel}
						aria-pressed={selected}
						className="settings-segment"
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
