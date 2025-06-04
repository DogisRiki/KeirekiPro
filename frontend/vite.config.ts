/// <reference types="vitest" />
import react from "@vitejs/plugin-react";
import { defineConfig, UserConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

// testプロパティがTypeScriptに認識されないため型を定義
interface ExtendedUserConfig extends UserConfig {
    test?: {
        environment: string;
        setupFiles: string[];
    };
}

// https://vite.dev/config/
export default defineConfig({
    plugins: [react(), tsconfigPaths()],
    server: {
        watch: {
            ignored: [
                "**/node_modules/**",
                "**/.git/**",
                "**/dist/**",
                "**/coverage/**",
                "**/.vite/**",
                "**/.idea/**",
                "**/.vscode/**",
            ],
        },
    },
    test: {
        globals: true,
        environment: "happy-dom",
        setupFiles: ["./vitest-setup.ts"],
        reporters: ["default", ["junit", { outputFile: "test-results/junit.xml" }]],
    },
} as ExtendedUserConfig);
