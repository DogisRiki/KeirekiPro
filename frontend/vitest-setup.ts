import "@testing-library/jest-dom/vitest";

// テスト実行時のランタイム環境変数をダミーで埋める
Object.assign(import.meta.env, {
    VITE_API_URL: "http://localhost:8080/api",
    VITE_APP_NAME: "KeirekiPro",
    VITE_APP_CONTACT_EMAIL: "test@example.com",
    VITE_APP_URL: "http://localhost",
    VITE_GA_MEASUREMENT_ID: "G-dummyId",
});
