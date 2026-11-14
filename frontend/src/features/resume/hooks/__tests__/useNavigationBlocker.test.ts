import { vi } from "vitest";

const mockProceed = vi.fn();
const mockReset = vi.fn();
let mockBlockerState = "unblocked";
type ShouldBlock = (args: { currentLocation: { pathname: string }; nextLocation: { pathname: string } }) => boolean;
let capturedShouldBlock: ShouldBlock | undefined;
vi.mock("react-router", () => ({
    useBlocker: (shouldBlock: ShouldBlock) => {
        capturedShouldBlock = shouldBlock;
        return {
            state: mockBlockerState,
            proceed: mockProceed,
            reset: mockReset,
        };
    },
}));

import { useNavigationBlocker, useResumeStore } from "@/features/resume";
import { useLeaveGuardStore, useUserAuthStore } from "@/stores";
import { act, renderHook } from "@testing-library/react";

describe("useNavigationBlocker", () => {
    beforeEach(() => {
        useResumeStore.getState().clearResume();
        mockBlockerState = "unblocked";
        mockProceed.mockReset();
        mockReset.mockReset();
        useLeaveGuardStore.setState({ confirmLeave: null });
        useUserAuthStore.setState({ isAuthenticated: true });
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

    it("保存していない変更があるときは、ほかの画面への移動を止め、ログアウトしたあとの移動は止めないこと", () => {
        useResumeStore.getState().addDirtyEntryId("career-1");
        renderHook(() => useNavigationBlocker());
        const move = { currentLocation: { pathname: "/resume/1" }, nextLocation: { pathname: "/login" } };

        expect(capturedShouldBlock?.(move)).toBe(true);

        useUserAuthStore.setState({ isAuthenticated: false });
        expect(capturedShouldBlock?.(move)).toBe(false);
    });

    it("保存していない変更が無いときは、ログアウトの前の確かめを出さないこと", () => {
        renderHook(() => useNavigationBlocker());

        expect(useLeaveGuardStore.getState().confirmLeave).toBeNull();
    });

    it("ログアウトの前の確かめで離れないほうを選ぶと、falseを返して確かめを閉じること", async () => {
        useResumeStore.getState().addDirtyEntryId("career-1");
        const { result, unmount } = renderHook(() => useNavigationBlocker());

        let answer: Promise<boolean> | undefined;
        act(() => {
            answer = useLeaveGuardStore.getState().confirmLeave?.();
        });
        expect(result.current.dialogProps.open).toBe(true);

        act(() => {
            result.current.dialogProps.onClose(false);
        });

        await expect(answer).resolves.toBe(false);
        expect(result.current.dialogProps.open).toBe(false);
        expect(mockReset).not.toHaveBeenCalled();

        unmount();
        expect(useLeaveGuardStore.getState().confirmLeave).toBeNull();
    });

    it("ログアウトの前の確かめで離れるほうを選ぶと、trueを返すこと", async () => {
        useResumeStore.getState().addDirtyEntryId("career-1");
        const { result } = renderHook(() => useNavigationBlocker());

        let answer: Promise<boolean> | undefined;
        act(() => {
            answer = useLeaveGuardStore.getState().confirmLeave?.();
        });
        act(() => {
            result.current.dialogProps.onClose(true);
        });

        await expect(answer).resolves.toBe(true);
        expect(mockProceed).not.toHaveBeenCalled();
    });
});
