import { useNotificationStore } from "@/stores/notificationStore";
import { Alert, Snackbar } from "@mui/material";
import { useEffect } from "react";

/**
 * 通知プロバイダー
 */
export const NotificationProvider = () => {
    const { message, type, isShow, clearNotification, setNotification } = useNotificationStore();

    // 5秒でトーストを自動で閉じる
    const duration = 5000;

    const handleClose = (_: React.SyntheticEvent | Event, reason?: string) => {
        if (reason === "clickaway") return;
        clearNotification();
    };

    useEffect(() => {
        // セッションに保存された通知があれば取り出して再表示
        const cached = sessionStorage.getItem("global-toast");
        if (cached) {
            const { m, t } = JSON.parse(cached) as { m: string; t: "success" | "error" };
            setNotification(m, t); // 通知状態に反映
            sessionStorage.removeItem("global-toast"); // 表示後は削除しておく
        }
    }, [setNotification]);

    return (
        <Snackbar
            open={isShow}
            onClose={handleClose}
            autoHideDuration={duration}
            anchorOrigin={{ vertical: "top", horizontal: "right" }}
        >
            {message && type ? (
                <Alert
                    onClose={clearNotification}
                    severity={type}
                    variant="filled"
                    sx={{ width: "100%", whiteSpace: "pre-line" }}
                >
                    {message}
                </Alert>
            ) : undefined}
        </Snackbar>
    );
};
