import "@testing-library/jest-dom/vitest";
import { afterEach, beforeAll, vi } from "vitest";

beforeAll(() => {
    vi.stubEnv("MODE", "test");
});

afterEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("MODE", "test");
});

Object.assign(import.meta.env, {
    VITE_API_URL: "http://localhost:8080/api",
    VITE_APP_NAME: "KeirekiPro",
    VITE_APP_CONTACT_EMAIL: "test@example.com",
    VITE_APP_URL: "http://localhost",
    VITE_GA_MEASUREMENT_ID: "G-dummyId",
});
