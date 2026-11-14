import { useResumeStore } from "@/features/resume";
import { useLeaveGuardStore, useUserAuthStore } from "@/stores";
import { useCallback, useEffect, useState } from "react";
import type { BlockerFunction } from "react-router";
import { useBlocker } from "react-router";

/**
 * 離脱防止フックの戻り値
 */
interface UseNavigationBlockerReturn {
    /** 離脱確認ダイアログを表示するためのprops */
    dialogProps: {
        open: boolean;
        onClose: (confirmed: boolean) => void;
    };
}

/**
 * 未保存の変更がある場合に離脱を防止するカスタムフック
 */
export const useNavigationBlocker = (): UseNavigationBlockerReturn => {
    const isDirty = useResumeStore((state) => state.isDirty);
    const setConfirmLeave = useLeaveGuardStore((state) => state.setConfirmLeave);
    // 画面の移動を伴わない操作(ログアウトなど)の確かめの答えを返す関数
    const [resolveLeave, setResolveLeave] = useState<((confirmed: boolean) => void) | null>(null);

    // React Router内のナビゲーションをブロック
    const shouldBlock = useCallback<BlockerFunction>(
        ({ currentLocation, nextLocation }) => {
            if (currentLocation.pathname === nextLocation.pathname) {
                return false;
            }
            // ログアウトしたあとのログイン画面への移動は、確かめを済ませているので止めない
            if (!useUserAuthStore.getState().isAuthenticated) {
                return false;
            }
            return isDirty;
        },
        [isDirty],
    );

    const blocker = useBlocker(shouldBlock);

    // 保存していない変更があるあいだ、画面の移動を伴わない操作の前に確かめを出せるようにする
    useEffect(() => {
        if (!isDirty) return;
        setConfirmLeave(() => new Promise<boolean>((resolve) => setResolveLeave(() => resolve)));
        return () => setConfirmLeave(null);
    }, [isDirty, setConfirmLeave]);

    // ブラウザのbeforeunloadイベント
    useEffect(() => {
        const handleBeforeUnload = (event: BeforeUnloadEvent) => {
            if (isDirty) {
                event.preventDefault();
            }
        };

        window.addEventListener("beforeunload", handleBeforeUnload);
        return () => {
            window.removeEventListener("beforeunload", handleBeforeUnload);
        };
    }, [isDirty]);

    const handleDialogClose = useCallback(
        (confirmed: boolean) => {
            if (resolveLeave) {
                resolveLeave(confirmed);
                setResolveLeave(null);
            } else if (confirmed) {
                blocker.proceed?.();
            } else {
                blocker.reset?.();
            }
        },
        [blocker, resolveLeave],
    );

    return {
        dialogProps: {
            open: blocker.state === "blocked" || resolveLeave !== null,
            onClose: handleDialogClose,
        },
    };
};
