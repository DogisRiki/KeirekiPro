import { Button, PasswordTextField, TextField } from "@/components/ui";
import { useErrorMessageStore } from "@/stores";
import { Box } from "@mui/material";

export interface SetEmailAndPasswordFormProps {
    showEmailField: boolean;
    email: string;
    password: string;
    confirmPassword: string;
    onEmailChange: (v: string) => void;
    onPasswordChange: (v: string) => void;
    onConfirmPasswordChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * メールアドレス+パスワード設定フォーム
 */
export const SetEmailAndPasswordForm = ({
    showEmailField,
    email,
    password,
    confirmPassword,
    onEmailChange,
    onPasswordChange,
    onConfirmPasswordChange,
    onSubmit,
    loading = false,
}: SetEmailAndPasswordFormProps) => {
    const { errors } = useErrorMessageStore();
    return (
        <Box
            component="form"
            sx={{ display: "flex", flexDirection: "column", justifyContent: "center" }}
            onSubmit={(e) => {
                e.preventDefault();
                onSubmit();
            }}
        >
            {showEmailField && (
                <TextField
                    type="email"
                    label="メールアドレス"
                    fullWidth
                    required
                    value={email}
                    onChange={(e) => onEmailChange(e.target.value)}
                    error={!!errors.email?.length}
                    helperText={errors.email?.[0] ?? ""}
                    margin="normal"
                    slotProps={{
                        inputLabel: { shrink: true },
                        htmlInput: {
                            maxLength: 255,
                        },
                    }}
                    sx={{ mb: 4 }}
                />
            )}
            <PasswordTextField
                label="パスワード"
                fullWidth
                required
                value={password}
                onChange={(e) => onPasswordChange(e.target.value)}
                error={!!errors.password?.length}
                helperText={errors.password?.[0] ?? ""}
                margin="normal"
                sx={{ mb: 4 }}
            />
            <PasswordTextField
                label="パスワード（確認）"
                fullWidth
                required
                value={confirmPassword}
                onChange={(e) => onConfirmPasswordChange(e.target.value)}
                error={!!errors.confirmPassword?.length}
                helperText={errors.confirmPassword?.[0] ?? ""}
                margin="normal"
                sx={{ mb: 4 }}
            />
            <Button type="submit" sx={{ width: 240, mx: "auto" }} disabled={loading}>
                設定
            </Button>
        </Box>
    );
};
