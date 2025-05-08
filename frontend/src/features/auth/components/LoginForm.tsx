import { Button, Link, PasswordTextField, TextField } from "@/components/ui";
import { paths } from "@/config/paths";
import { useErrorMessageStore } from "@/stores";
import { Box } from "@mui/material";
import { FaGithub } from "react-icons/fa";
import { FcGoogle } from "react-icons/fc";

export interface LoginFormProps {
    email: string;
    password: string;
    onEmailChange: (v: string) => void;
    onPasswordChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * ログインフォーム
 */
export const LoginForm = ({
    email,
    password,
    onEmailChange,
    onPasswordChange,
    onSubmit,
    loading = false,
}: LoginFormProps) => {
    // ボタンの共通スタイル
    const buttonStyle = { width: "240px" };
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
                variant="standard"
                fullWidth
                margin="normal"
                value={email}
                onChange={(e) => onEmailChange(e.target.value)}
                error={!!errors.email?.length}
                helperText={errors.email?.[0] ?? ""}
                slotProps={{ inputLabel: { shrink: true } }}
                sx={{ mb: 2 }}
            />
            <PasswordTextField
                label="パスワード"
                variant="standard"
                fullWidth
                margin="normal"
                value={password}
                onChange={(e) => onPasswordChange(e.target.value)}
                error={!!errors.password?.length}
                helperText={errors.password?.[0] ?? ""}
            />
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    mt: 1,
                }}
            >
                <Link to={paths.password.resetRquest} variant="caption" sx={{ alignSelf: "flex-start", mb: 2 }}>
                    パスワードをお忘れですか？
                </Link>
                <Button type="submit" sx={{ ...buttonStyle, mb: 2 }} disabled={loading}>
                    ログイン
                </Button>
                <Button variant="outlined" startIcon={<FcGoogle />} sx={{ ...buttonStyle, mb: 2 }}>
                    Googleでログイン
                </Button>
                <Button variant="outlined" startIcon={<FaGithub />} sx={{ ...buttonStyle, mb: 2 }}>
                    Githubでログイン
                </Button>
                <Link to={paths.register} variant="body2">
                    新規登録はこちら
                </Link>
            </Box>
        </Box>
    );
};
