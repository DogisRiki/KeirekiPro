import react from "@vitejs/plugin-react";
import type { UserConfig } from "vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

interface ExtendedUserConfig extends UserConfig {
    test?: {
        globals: boolean;
        environment: string;
        setupFiles: string[];
        reporters: (string | [string, { outputFile: string }])[];
        pool: string;
        poolOptions: {
            forks: {
                singleFork: boolean;
            };
        };
        deps: {
            interopDefault: boolean;
        };
    };
}

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
        pool: "forks",
        poolOptions: {
            forks: {
                singleFork: true,
            },
        },
        deps: {
            interopDefault: true,
        },
    },
} as ExtendedUserConfig);
