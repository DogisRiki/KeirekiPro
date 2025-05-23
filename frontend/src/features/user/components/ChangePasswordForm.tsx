import { Button, PasswordTextField } from "@/components/ui";
import { useErrorMessageStore } from "@/stores";
import { Box } from "@mui/material";

export interface ChangePasswordFormProps {
    nowPassword: string;
    newPassword: string;
    onNowPasswordChange: (v: string) => void;
    onNewPasswordChange: (v: string) => void;
    onSubmit: () => void;
}

/**
 * パスワード変更フォーム
 */
export const ChangePasswordForm = ({
    nowPassword,
    newPassword,
    onNowPasswordChange,
    onNewPasswordChange,
    onSubmit,
}: ChangePasswordFormProps) => {
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
            <PasswordTextField
                label="現在のパスワード"
                fullWidth
                margin="normal"
                value={nowPassword}
                required
                placeholder="現在のパスワード"
                onChange={(e) => onNowPasswordChange(e.target.value)}
                error={!!errors.nowPassword?.length}
                helperText={errors.nowPassword?.[0] ?? ""}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            <PasswordTextField
                label="新しいパスワード"
                fullWidth
                margin="normal"
                value={newPassword}
                required
                placeholder="新しいパスワード"
                onChange={(e) => onNewPasswordChange(e.target.value)}
                error={!!errors.newPassword?.length}
                helperText={errors.newPassword?.[0] ?? ""}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            <Button type="submit" sx={{ width: 240, mx: "auto" }}>
                変更
            </Button>
        </Box>
    );
};
