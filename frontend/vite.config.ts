import react from "@vitejs/plugin-react";
import type { UserConfig } from "vite";
import { defineConfig } from "vite";

interface ExtendedUserConfig extends UserConfig {
    test?: {
        globals: boolean;
        environment: string;
        setupFiles: string[];
        reporters: (string | [string, { outputFile: string }])[];
        pool: string;
        deps: {
            interopDefault: boolean;
        };
    };
}

export default defineConfig({
    plugins: [react()],
    resolve: {
        tsconfigPaths: true,
    },
    build: {
        rollupOptions: {
            output: {
                manualChunks: (id) => {
                    if (!id.includes("node_modules")) {
                        return;
                    }
                    if (id.includes("@mui") || id.includes("@emotion")) {
                        return "vendor-mui";
                    }
                    if (id.includes("@tanstack")) {
                        return "vendor-query";
                    }
                    return "vendor";
                },
            },
        },
    },
    server: {
        host: true,
        allowedHosts: ["host.docker.internal"],
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
        deps: {
            interopDefault: true,
        },
    },
} as ExtendedUserConfig);
