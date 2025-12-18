import "@testing-library/jest-dom/vitest";
import { beforeAll, vi } from "vitest";

beforeAll(() => {
    vi.stubEnv("MODE", "test");
    vi.stubEnv("VITE_API_URL", "http://localhost:8080/api");
    vi.stubEnv("VITE_APP_NAME", "KeirekiPro");
    vi.stubEnv("VITE_APP_CONTACT_EMAIL", "test@example.com");
    vi.stubEnv("VITE_APP_URL", "http://localhost");
    vi.stubEnv("VITE_GA_MEASUREMENT_ID", "G-dummyId");
});
