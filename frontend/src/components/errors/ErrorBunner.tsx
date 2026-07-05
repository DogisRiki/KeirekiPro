import { useErrorMessageStore } from "@/stores";
import CloseIcon from "@mui/icons-material/Close";
import { Alert, IconButton, Slide, Snackbar } from "@mui/material";
import type { TransitionProps } from "@mui/material/transitions";
import React, { useState } from "react";

const SlideDown = React.forwardRef(function SlideDown(
    props: TransitionProps & { children: React.ReactElement<any, any> },
    ref: React.Ref<unknown>,
) {
    return <Slide {...props} direction="down" ref={ref} />;
});

/**
 * ジェネラルエラー表示バナー
 */
export const ErrorBanner = () => {
    const { message, errorId } = useErrorMessageStore();
    const [dismissedErrorId, setDismissedErrorId] = useState<string | null>(null);

    // 10秒でバナーを自動で閉じる
    const duration = 10000;
    const open = Boolean(message && errorId !== dismissedErrorId);

    const handleClose = (_: React.SyntheticEvent | Event, reason?: string) => {
        if (reason === "clickaway") return;
        setDismissedErrorId(errorId); // 閉じたエラーを記憶
    };

    // 表示条件：メッセージがある
    if (!message) return null;

    return (
        <Snackbar
            open={open}
            onClose={handleClose}
            autoHideDuration={duration}
            slots={{ transition: SlideDown }}
            anchorOrigin={{ vertical: "top", horizontal: "center" }}
            sx={{ mt: 2 }}
        >
            <Alert
                severity="error"
                variant="filled"
                sx={{
                    alignItems: "center",
                    whiteSpace: "pre-line", // \nを改行として表示
                }}
                action={
                    <IconButton aria-label="close" size="small" color="inherit" onClick={handleClose}>
                        <CloseIcon fontSize="small" />
                    </IconButton>
                }
            >
                {message}
            </Alert>
        </Snackbar>
    );
};
