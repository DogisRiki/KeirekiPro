import {
    Button,
    DialogActions,
    DialogContent,
    DialogContentText,
    DialogTitle,
    Dialog as MuiDialog,
} from "@mui/material";
import { useEffect, useRef } from "react";

export interface DialogProps {
    /** ダイアログの開閉状態 */
    open: boolean;
    /** ダイアログタイトル */
    title?: string;
    /** ダイアログ本文 */
    description?: string;
    /** ダイアログの種類: confirm（確認）または warning（警告） */
    variant?: "confirm" | "warning";
    /**
     * ダイアログを閉じるときに呼び出される
     * @param confirmed 「はい」または「OK」が押されたら true、「いいえ」なら false
     */
    onClose: (confirmed: boolean) => void;
}

/**
 * ダイアログ
 */
export const Dialog = ({ open, title, description, variant, onClose }: DialogProps) => {
    // ボタンを参照
    const buttonRef = useRef<HTMLButtonElement>(null);

    // ダイアログが開いたらボタンにフォーカスを移す
    useEffect(() => {
        if (open && buttonRef.current) {
            buttonRef.current.focus();
        }
    }, [open]);

    const handleYes = () => {
        onClose(true);
    };

    const handleNo = () => {
        onClose(false);
    };

    return (
        <MuiDialog open={open} onClose={handleNo} aria-labelledby="confirm-dialog-title">
            <DialogTitle id="confirm-dialog-title">{title}</DialogTitle>
            {description && (
                <DialogContent>
                    <DialogContentText>{description}</DialogContentText>
                </DialogContent>
            )}
            <DialogActions>
                {variant === "confirm" ? (
                    <>
                        <Button onClick={handleNo} ref={buttonRef}>
                            いいえ
                        </Button>
                        <Button onClick={handleYes}>はい</Button>
                    </>
                ) : (
                    <Button onClick={handleYes} ref={buttonRef}>
                        OK
                    </Button>
                )}
            </DialogActions>
        </MuiDialog>
    );
};
