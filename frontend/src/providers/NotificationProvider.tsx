import { useNotificationStore } from "@/stores/notificationStore";
import { Alert, Snackbar } from "@mui/material";

/**
 * 通知プロバイダー
 */
export const NotificationProvider = () => {
    const { message, type, isShow, clearNotification } = useNotificationStore();
    return (
        <Snackbar open={isShow} onClose={clearNotification} autoHideDuration={3000}>
            {message && type ? (
                <Alert onClose={clearNotification} severity={type} variant="filled" sx={{ width: "100%" }}>
                    {message}
                </Alert>
            ) : undefined}
        </Snackbar>
    );
};
