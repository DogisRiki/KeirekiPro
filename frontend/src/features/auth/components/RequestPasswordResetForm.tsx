import { Button, TextField } from "@/components/ui";
import { env } from "@/config/env";
import { useErrorMessageStore } from "@/stores";
import { Box } from "@mui/material";

export interface RequestPasswordResetFormProps {
    email: string;
    onEmailChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * パスワードリセット要求フォーム
 */
export const RequestPasswordResetForm = ({
    email,
    onEmailChange,
    onSubmit,
    loading = false,
}: RequestPasswordResetFormProps) => {
    const { errors } = useErrorMessageStore();

    return (
        <Box
            component="form"
            onSubmit={(e) => {
                e.preventDefault();
                onSubmit();
            }}
        >
            <TextField
                type="email"
                label="メールアドレス"
                fullWidth
                required
                placeholder={env.APP_EMAIL}
                value={email}
                onChange={(e) => onEmailChange(e.target.value)}
                error={!!errors.email?.length}
                helperText={errors.email?.[0] ?? ""}
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
            <Button type="submit" sx={{ mt: 2 }} disabled={loading}>
                送信
            </Button>
        </Box>
    );
};
