import type { AgentSession } from "../domain/model";

type Provider = AgentSession["provider"];

export const PROVIDER_NAMES = {
	claude: "Claude Code",
	codex: "Codex",
	grok: "Grok Build",
} as const satisfies Record<Provider, string>;

// Simplified marks, not brand artwork: a spark, a hexagon and a slashed ring.
const CLAUDE_RAYS = Array.from({ length: 8 }, (_, index) => {
	const angle = (index * Math.PI) / 4;
	const length = index % 2 === 0 ? 6.4 : 4.8;
	return {
		x1: 8 + Math.cos(angle) * 1.4,
		y1: 8 + Math.sin(angle) * 1.4,
		x2: 8 + Math.cos(angle) * length,
		y2: 8 + Math.sin(angle) * length,
	};
});

function ProviderMark({ provider }: { readonly provider: Provider }) {
	switch (provider) {
		case "claude":
			return (
				<>
					{CLAUDE_RAYS.map((ray) => (
						<line key={`${ray.x2}:${ray.y2}`} {...ray} />
					))}
				</>
			);
		case "codex":
			return <path d="M8 1.6 13.6 4.8v6.4L8 14.4 2.4 11.2V4.8Z" />;
		case "grok":
			return (
				<>
					<circle cx="8" cy="8" r="5.4" />
					<path d="M3.2 13.2 13.4 2.6" />
				</>
			);
	}
}

export function ProviderIcon({ provider }: { readonly provider: Provider }) {
	const name = PROVIDER_NAMES[provider];
	return (
		<svg
			aria-label={name}
			className="provider-icon"
			data-provider={provider}
			fill="none"
			role="img"
			stroke="currentColor"
			strokeLinecap="round"
			strokeLinejoin="round"
			strokeWidth={provider === "claude" ? 1.8 : 1.5}
			viewBox="0 0 16 16"
		>
			<title>{name}</title>
			<ProviderMark provider={provider} />
		</svg>
	);
}

export function sessionProviders(
	sessions: readonly AgentSession[],
): readonly Provider[] {
	return [...new Set(sessions.map((s) => s.provider))];
}
