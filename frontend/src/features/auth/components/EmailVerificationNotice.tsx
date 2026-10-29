import { Button } from "@/components/ui";
import { Alert, Typography } from "@mui/material";

/**
 * ログインの 409 の応答の kind(確認がまだのもの)
 */
export type EmailNotVerifiedKind = "PENDING_REGISTRATION" | "UNVERIFIED_ACCOUNT_EMAIL";

export interface EmailVerificationNoticeProps {
    kind: EmailNotVerifiedKind;
    onSend: () => void;
    loading?: boolean;
}

/**
 * ログインの画面に出す、確認がまだであることの文とボタン
 */
export const EmailVerificationNotice = ({ kind, onSend, loading = false }: EmailVerificationNoticeProps) => {
    const isPendingRegistration = kind === "PENDING_REGISTRATION";

    return (
        <Alert severity="warning" sx={{ mb: 3, textAlign: "left" }}>
            <Typography variant="body2">メールアドレスの確認が済んでいません。</Typography>
            <Typography variant="body2">
                {isPendingRegistration
                    ? "登録はまだ済んでいません。確認のメールの中のリンクを押して、登録を済ませてください。"
                    : "確認のメールを送り、メールの中のリンクを押して、メールアドレスの確認を済ませてください。"}
            </Typography>
            <Button sx={{ mt: 1 }} onClick={onSend} disabled={loading}>
                {isPendingRegistration ? "確認のメールを送り直す" : "確認のメールを送る"}
            </Button>
        </Alert>
    );
};
