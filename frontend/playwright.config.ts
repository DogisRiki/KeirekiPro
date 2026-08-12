import { defineConfig } from "@playwright/test";

/**
 * E2Eスモークテスト設定
 *
 * 本番デプロイ前の最低限の起動確認をCIで行う。
 * ビルド済み成果物を vite preview で配信し、バックエンド無しで検証できる範囲に限定する。
 */
export default defineConfig({
    testDir: "./e2e",
    timeout: 30_000,
    fullyParallel: true,
    reporter: [["list"], ["html", { open: "never" }]],
    use: {
        baseURL: process.env.E2E_BASE_URL ?? "http://localhost:4173",
        screenshot: "only-on-failure",
    },
    webServer: {
        command: "pnpm run preview -- --port 4173 --strictPort",
        url: "http://localhost:4173",
        reuseExistingServer: !process.env.CI,
        timeout: 60_000,
    },
});
