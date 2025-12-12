import { vi } from "vitest";

const mockProceed = vi.fn();
const mockReset = vi.fn();
let mockBlockerState = "unblocked";
vi.mock("react-router", () => ({
    useBlocker: () => ({
        state: mockBlockerState,
        proceed: mockProceed,
        reset: mockReset,
    }),
}));

import { useNavigationBlocker, useResumeStore } from "@/features/resume";
import { act, renderHook } from "@testing-library/react";

describe("useNavigationBlocker", () => {
    beforeEach(() => {
        useResumeStore.getState().clearResume();
        mockBlockerState = "unblocked";
        mockProceed.mockReset();
        mockReset.mockReset();
    });

    it("初期状態でdialogProps.openがfalseであること", () => {
        const { result } = renderHook(() => useNavigationBlocker());

        expect(result.current.dialogProps.open).toBe(false);
    });

    it("blockerがblocked状態になるとdialogProps.openがtrueになること", () => {
        mockBlockerState = "blocked";

        const { result } = renderHook(() => useNavigationBlocker());

        expect(result.current.dialogProps.open).toBe(true);
    });

    it("onCloseでtrueを渡すとproceedが呼ばれること", () => {
        mockBlockerState = "blocked";

        const { result } = renderHook(() => useNavigationBlocker());

        act(() => {
            result.current.dialogProps.onClose(true);
        });

        expect(mockProceed).toHaveBeenCalled();
    });

    it("onCloseでfalseを渡すとresetが呼ばれること", () => {
        mockBlockerState = "blocked";

        const { result } = renderHook(() => useNavigationBlocker());

        act(() => {
            result.current.dialogProps.onClose(false);
        });

        expect(mockReset).toHaveBeenCalled();
    });
});
