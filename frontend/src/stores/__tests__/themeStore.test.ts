import { useThemeStore } from "@/stores";

// localStorageのモック
const localStorageMock = {
    getItem: vi.fn(),
    setItem: vi.fn(),
    removeItem: vi.fn(),
    clear: vi.fn(),
};

Object.defineProperty(window, "localStorage", {
    value: localStorageMock,
});

describe("useThemeStore", () => {
    beforeEach(() => {
        // テスト前にストアをリセット（lightモードに戻す）
        const currentMode = useThemeStore.getState().mode;
        if (currentMode === "dark") {
            useThemeStore.getState().toggleMode();
        }
        // localStorageのモックをリセット
        vi.clearAllMocks();
    });

    it("初期状態でmodeがlightであること", () => {
        const { mode } = useThemeStore.getState();
        expect(mode).toBe("light");
    });

    it("toggleModeでlightからdarkに切り替わること", () => {
        // 初期状態を確認
        expect(useThemeStore.getState().mode).toBe("light");

        // toggleModeを実行
        useThemeStore.getState().toggleMode();

        // darkに切り替わっていること
        expect(useThemeStore.getState().mode).toBe("dark");
    });

    it("toggleModeでdarkからlightに切り替わること", () => {
        // darkモードにする
        useThemeStore.getState().toggleMode();
        expect(useThemeStore.getState().mode).toBe("dark");

        // toggleModeを実行
        useThemeStore.getState().toggleMode();

        // lightに切り替わっていること
        expect(useThemeStore.getState().mode).toBe("light");
    });

    it("toggleModeを複数回呼び出すと交互に切り替わること", () => {
        expect(useThemeStore.getState().mode).toBe("light");

        useThemeStore.getState().toggleMode();
        expect(useThemeStore.getState().mode).toBe("dark");

        useThemeStore.getState().toggleMode();
        expect(useThemeStore.getState().mode).toBe("light");

        useThemeStore.getState().toggleMode();
        expect(useThemeStore.getState().mode).toBe("dark");

        useThemeStore.getState().toggleMode();
        expect(useThemeStore.getState().mode).toBe("light");
    });
});
