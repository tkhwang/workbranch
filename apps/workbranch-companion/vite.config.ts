import react from "@vitejs/plugin-react";
import { defineConfig, type ServerOptions } from "vite";

const host = process.env["TAURI_DEV_HOST"];
const server: ServerOptions = {
	host: host ?? false,
	port: 5173,
	strictPort: true,
	watch: {
		ignored: ["**/src-tauri/**"],
	},
};

if (host) {
	server.hmr = {
		host,
		port: 1421,
		protocol: "ws",
	};
}

export default defineConfig({
	clearScreen: false,
	plugins: [react()],
	server,
	envPrefix: ["VITE_", "TAURI_ENV_*"],
	build: {
		minify: process.env["TAURI_ENV_DEBUG"] ? false : "esbuild",
		sourcemap: Boolean(process.env["TAURI_ENV_DEBUG"]),
		target:
			process.env["TAURI_ENV_PLATFORM"] === "windows"
				? "chrome105"
				: "safari13",
	},
});
