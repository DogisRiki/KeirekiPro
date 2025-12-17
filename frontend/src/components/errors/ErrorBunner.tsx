import { useErrorMessageStore } from "@/stores";
import CloseIcon from "@mui/icons-material/Close";
import { Alert, IconButton, Slide, Snackbar } from "@mui/material";
import type { TransitionProps } from "@mui/material/transitions";
import React, { useEffect, useState } from "react";

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
    const { message } = useErrorMessageStore();
    const [open, setOpen] = useState(false);
    const [dismissed, setDismissed] = useState(false);

    // 10秒でバナーを自動で閉じる
    const duration = 10000;

    useEffect(() => {
        if (message) {
            setDismissed(false); // 新しいエラーが来たら再表示できるように
            setOpen(true);
        } else {
            // messageがクリアされたらバナーを閉じる
            setOpen(false);
        }
    }, [message]);

    const handleClose = (_: React.SyntheticEvent | Event, reason?: string) => {
        if (reason === "clickaway") return;
        setOpen(false); // バナーを閉じる
        setDismissed(true); // 閉じたことを記憶
    };

    // 表示条件：メッセージがあり、まだ手動で閉じられていない
    if (!message || dismissed) return null;

    return (
        <Snackbar
            open={open}
            onClose={handleClose}
            autoHideDuration={duration}
            TransitionComponent={SlideDown}
            anchorOrigin={{ vertical: "top", horizontal: "center" }}
            sx={{ mt: 2 }}
        >
            <Alert
                severity="error"
                variant="filled"
                sx={{ alignItems: "center" }}
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
