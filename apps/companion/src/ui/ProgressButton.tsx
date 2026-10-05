import type { ReactNode } from "react";

type Props = {
	readonly pending: boolean;
	readonly pendingLabel: string;
	readonly disabled?: boolean;
	readonly onClick: () => void;
	readonly children: ReactNode;
};

/** Long-running actions keep their own button and show that it is running. */
export function ProgressButton({
	pending,
	pendingLabel,
	disabled = false,
	onClick,
	children,
}: Props) {
	return (
		<button
			type="button"
			aria-busy={pending || undefined}
			disabled={pending || disabled}
			onClick={onClick}
		>
			{pending ? (
				<>
					<span aria-hidden="true" className="button-spinner" />
					{pendingLabel}
				</>
			) : (
				children
			)}
		</button>
	);
}
