import react from "@vitejs/plugin-react";
import type { UserConfig } from "vite";
import { defineConfig } from "vite";

interface ExtendedUserConfig extends UserConfig {
    test?: {
        globals: boolean;
        environment: string;
        include: string[];
        setupFiles: string[];
        reporters: (string | [string, { outputFile: string }])[];
        pool: string;
        deps: {
            interopDefault: boolean;
        };
        server: {
            deps: {
                external: string[];
            };
        };
        coverage: {
            reporter: string[];
            thresholds: {
                statements: number;
                branches: number;
                functions: number;
                lines: number;
            };
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
        // ユニットテストは src 配下の *.test.* のみ(e2e/ は Playwright 管轄のため除外)
        include: ["src/**/*.test.{ts,tsx}"],
        setupFiles: ["./vitest-setup.ts"],
        reporters: ["default", ["junit", { outputFile: "test-results/junit.xml" }]],
        pool: "forks",
        deps: {
            interopDefault: true,
        },
        server: {
            deps: {
                external: ["axios-auth-refresh"],
            },
        },
        // カバレッジ閾値(drain-then-ratchet 運用)
        // 初期値は 2026-08-10 時点の実測値(Stmts 79.31 / Branch 59.65 / Funcs 80.6 / Lines 80.86)を
        // わずかに下回る値で固定。下げる変更は禁止、実測の向上に合わせて段階的に引き上げる。
        // このファイルは CODEOWNERS 保護対象。
        coverage: {
            reporter: ["text", "html", "json-summary"],
            thresholds: {
                statements: 79,
                branches: 59,
                functions: 80,
                lines: 80,
            },
        },
    },
} as ExtendedUserConfig);
