import { Button } from "@/components/ui";
import { useSendEmailVerification } from "@/features/user";
import { Alert, Box, Typography } from "@mui/material";

export interface EmailVerificationStatusProps {
    email: string | null;
    emailVerified: boolean;
    pendingEmail: string | null;
}

/**
 * 確認待ちのメールアドレスと、確認のメールを送るボタンを表示
 */
export const EmailVerificationStatus = ({ email, emailVerified, pendingEmail }: EmailVerificationStatusProps) => {
    const sendEmailVerificationMutation = useSendEmailVerification();

    // 設定待ちのメールアドレスを優先し、無ければ確認がまだのメールアドレスを出す
    const awaitingEmail = pendingEmail ?? (!emailVerified ? email : null);
    if (!awaitingEmail) return null;

    return (
        <Box sx={{ mb: 4 }}>
            <Alert severity="warning" sx={{ textAlign: "left" }}>
                <Typography variant="body2">確認待ちのメールアドレス: {awaitingEmail}</Typography>
                <Typography variant="body2">
                    確認のメールの中のリンクを押すと、メールアドレスの確認が済みます。
                </Typography>
                <Button
                    sx={{ mt: 1 }}
                    onClick={() => sendEmailVerificationMutation.mutate()}
                    disabled={sendEmailVerificationMutation.isPending}
                >
                    確認のメールを送る
                </Button>
            </Alert>
        </Box>
    );
};
