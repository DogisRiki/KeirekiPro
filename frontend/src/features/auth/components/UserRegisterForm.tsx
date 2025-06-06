import { Button, Checkbox, Link, PasswordTextField, TextField } from "@/components/ui";
import { paths } from "@/config/paths";
import { useErrorMessageStore } from "@/stores";
import { stringListToBulletList } from "@/utils";
import { Box, FormControlLabel, FormGroup } from "@mui/material";
import { useState } from "react";

export interface UserRegisterFormProps {
    email: string;
    username: string;
    password: string;
    confirmPassword: string;
    onEmailChange: (v: string) => void;
    onUsernameChange: (v: string) => void;
    onPasswordChange: (v: string) => void;
    onConfirmPasswordChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * ユーザー新規登録フォーム
 */
export const UserRegisterForm = ({
    email,
    username,
    password,
    confirmPassword,
    onEmailChange,
    onUsernameChange,
    onPasswordChange,
    onConfirmPasswordChange,
    onSubmit,
    loading = false,
}: UserRegisterFormProps) => {
    const [isChecked, setIsChecked] = useState({ terms: false, privacy: false });
    const { errors } = useErrorMessageStore();

    const handleCheck = (event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, checked } = event.target;
        setIsChecked((prev) => ({
            ...prev,
            [name]: checked,
        }));
    };

    const buttonStyle = {
        width: "240px",
    };

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
                value={email}
                onChange={(e) => onEmailChange(e.target.value)}
                error={!!errors.email?.length}
                helperText={stringListToBulletList(errors.email)}
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                    htmlInput: {
                        maxLength: 255,
                    },
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
                sx={{ mb: 2 }}
            />
            <TextField
                label="ユーザー名"
                fullWidth
                required
                value={username}
                onChange={(e) => onUsernameChange(e.target.value)}
                error={!!errors.username?.length}
                helperText={stringListToBulletList(errors.username)}
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                    htmlInput: {
                        maxLength: 50,
                    },
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
            />
            <PasswordTextField
                label="パスワード"
                fullWidth
                required
                value={password}
                onChange={(e) => onPasswordChange(e.target.value)}
                error={!!errors.password?.length}
                helperText={stringListToBulletList(errors.password)}
                margin="normal"
                slotProps={{
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
            />
            <PasswordTextField
                label="パスワード（確認）"
                fullWidth
                required
                value={confirmPassword}
                onChange={(e) => onConfirmPasswordChange(e.target.value)}
                error={!!errors.confirmPassword?.length}
                helperText={stringListToBulletList(errors.confirmPassword)}
                margin="normal"
                slotProps={{
                    formHelperText: { sx: { whiteSpace: "pre-line" } },
                }}
            />
            <FormGroup sx={{ mt: 1 }}>
                <FormControlLabel
                    control={<Checkbox name="terms" required checked={isChecked.terms} onChange={handleCheck} />}
                    label={
                        <Box component="span" sx={{ typography: "body2" }}>
                            <Link
                                to={paths.terms}
                                target="_blank"
                                rel="noopener noreferrer"
                                sx={{ typography: "body2" }}
                            >
                                利用規約
                            </Link>
                            に同意します。
                        </Box>
                    }
                />
                <FormControlLabel
                    control={<Checkbox name="privacy" required checked={isChecked.privacy} onChange={handleCheck} />}
                    label={
                        <Box component="span" sx={{ typography: "body2" }}>
                            <Link
                                to={paths.privacy}
                                target="_blank"
                                rel="noopener noreferrer"
                                sx={{ typography: "body2" }}
                            >
                                プライバシーポリシー
                            </Link>
                            に同意します。
                        </Box>
                    }
                />
            </FormGroup>
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    mt: 2,
                }}
            >
                <Button
                    type="submit"
                    sx={{ ...buttonStyle, mb: 2 }}
                    disabled={!(isChecked.terms && isChecked.privacy) || loading}
                >
                    登録
                </Button>
                <Link to={paths.login} variant="body2">
                    アカウントをお持ちの方はこちら
                </Link>
            </Box>
        </Box>
    );
};
