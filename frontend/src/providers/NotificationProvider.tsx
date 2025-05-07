import { useNotificationStore } from "@/stores/notificationStore";
import { Alert, Snackbar } from "@mui/material";

/**
 * 通知プロバイダー
 */
export const NotificationProvider = () => {
    const { message, type, isShow, clearNotification } = useNotificationStore();

    // 成功時は3秒、エラー時は5秒
    const duration = type === "success" ? 3000 : 5000;

    return (
        <Snackbar open={isShow} onClose={clearNotification} autoHideDuration={duration}>
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
