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
    const { message, clearErrors } = useErrorMessageStore();
    const [open, setOpen] = useState(false);

    /**
     * メッセージがストアに格納されたら発火
     */
    useEffect(() => {
        if (message) setOpen(true);
    }, [message]);

    const handleClose = () => setOpen(false);

    const handleExited = () => clearErrors();

    return (
        <Snackbar
            open={open}
            onClose={handleClose}
            TransitionComponent={SlideDown}
            TransitionProps={{ onExited: handleExited }}
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
