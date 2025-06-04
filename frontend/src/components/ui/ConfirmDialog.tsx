import { Button, Dialog, DialogActions, DialogContent, DialogContentText, DialogTitle } from "@mui/material";
import { useEffect, useRef } from "react";

export interface ConfirmDialogProps {
    // ダイアログの開閉状態
    open: boolean;
    // ダイアログタイトル
    title?: string;
    // ダイアログ本文
    description?: string;
    /**
     * ダイアログを閉じるときに呼び出される
     * @param confirmed 「はい」が押されたら true、「いいえ」なら false
     */
    onClose: (confirmed: boolean) => void;
}

/**
 * 確認ダイアログ
 */
export const ConfirmDialog = ({ open, title = "確認", description, onClose }: ConfirmDialogProps) => {
    // 「いいえ」ボタンを参照
    const noButtonRef = useRef<HTMLButtonElement>(null);

    // ダイアログが開いたら「いいえ」ボタンにフォーカスを移す
    useEffect(() => {
        if (open && noButtonRef.current) {
            noButtonRef.current.focus();
        }
    }, [open]);

    const handleYes = () => {
        onClose(true);
    };
    const handleNo = () => {
        onClose(false);
    };

    return (
        <Dialog open={open} onClose={handleNo} aria-labelledby="confirm-dialog-title">
            <DialogTitle id="confirm-dialog-title">{title}</DialogTitle>
            {description && (
                <DialogContent>
                    <DialogContentText>{description}</DialogContentText>
                </DialogContent>
            )}
            <DialogActions>
                <Button onClick={handleNo} ref={noButtonRef}>
                    いいえ
                </Button>
                <Button onClick={handleYes}>はい</Button>
            </DialogActions>
        </Dialog>
    );
};
