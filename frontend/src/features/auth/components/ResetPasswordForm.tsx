import { Button, PasswordTextField } from "@/components/ui";
import { useErrorMessageStore } from "@/stores";
import { stringListToBulletList } from "@/utils";
import { Box } from "@mui/material";

export interface ResetPasswordFormProps {
    password: string;
    confirmPassword: string;
    onPasswordChange: (v: string) => void;
    onConfirmPasswordChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * パスワードリセットフォーム
 */
export const ResetPasswordForm = ({
    password,
    confirmPassword,
    onPasswordChange,
    onConfirmPasswordChange,
    onSubmit,
    loading = false,
}: ResetPasswordFormProps) => {
    const { errors } = useErrorMessageStore();

    return (
        <Box
            component="form"
            onSubmit={(e) => {
                e.preventDefault();
                onSubmit();
            }}
        >
            <PasswordTextField
                label="新しいパスワード"
                placeholder="新しいパスワード"
                fullWidth
                required
                margin="normal"
                value={password}
                onChange={(e) => onPasswordChange(e.target.value)}
                error={!!errors.password?.length}
                helperText={stringListToBulletList(errors.password)}
                slotProps={{
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
            />
            <PasswordTextField
                label="新しいパスワード(確認)"
                placeholder="新しいパスワード(確認)"
                fullWidth
                required
                margin="normal"
                value={confirmPassword}
                onChange={(e) => onConfirmPasswordChange(e.target.value)}
                error={!!errors.confirmPassword?.length || !!errors.passwordMatching?.length}
                helperText={stringListToBulletList(
                    errors.confirmPassword?.length ? errors.confirmPassword : errors.passwordMatching,
                )}
                slotProps={{
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
            />
            <Button type="submit" sx={{ mt: 2 }} disabled={loading}>
                パスワードを変更
            </Button>
        </Box>
    );
};
