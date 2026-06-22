type Props = {
	readonly message: string | undefined;
};

export function StatusAlert({ message }: Props) {
	if (message === undefined) {
		return null;
	}
	return (
		<p className="app-error" role="alert">
			{message}
		</p>
	);
}
