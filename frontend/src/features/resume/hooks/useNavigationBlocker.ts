import { useResumeStore } from "@/features/resume";
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
    const [showDialog, setShowDialog] = useState(false);

    // React Router内のナビゲーションをブロック
    const shouldBlock = useCallback<BlockerFunction>(
        ({ currentLocation, nextLocation }) => {
            if (currentLocation.pathname === nextLocation.pathname) {
                return false;
            }
            return isDirty;
        },
        [isDirty],
    );

    const blocker = useBlocker(shouldBlock);

    // blockerがブロック状態になったらダイアログを表示
    useEffect(() => {
        if (blocker.state === "blocked") {
            setShowDialog(true);
        }
    }, [blocker.state]);

    // ブラウザのbeforeunloadイベント
    useEffect(() => {
        const handleBeforeUnload = (event: BeforeUnloadEvent) => {
            if (isDirty) {
                event.preventDefault();
                event.returnValue = "";
                return "";
            }
        };

        window.addEventListener("beforeunload", handleBeforeUnload);
        return () => {
            window.removeEventListener("beforeunload", handleBeforeUnload);
        };
    }, [isDirty]);

    const handleDialogClose = useCallback(
        (confirmed: boolean) => {
            setShowDialog(false);
            if (confirmed) {
                blocker.proceed?.();
            } else {
                blocker.reset?.();
            }
        },
        [blocker],
    );

    return {
        dialogProps: {
            open: showDialog,
            onClose: handleDialogClose,
        },
    };
};
