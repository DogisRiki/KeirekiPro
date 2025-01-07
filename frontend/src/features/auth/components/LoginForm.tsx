import { Button, Link, PasswordTextField, TextField } from "@/components/ui";
import { paths } from "@/config/paths";
import { Box } from "@mui/material";
import { FaGithub } from "react-icons/fa";
import { FcGoogle } from "react-icons/fc";
/**
 * ログインフォーム
 */
export const LoginForm = () => {
    // ボタンの共通スタイル
    const buttonStyle = {
        width: "240px",
    };

    // ログイン処理
    const handleLogin = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert("ログイン");
    };

    return (
        <Box component="form" onSubmit={handleLogin}>
            {/* メールアドレス */}
            <TextField
                type="email"
                label="メールアドレス"
                variant="standard"
                fullWidth
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 2 }}
            />
            {/* パスワード */}
            <PasswordTextField label="パスワード" variant="standard" fullWidth margin="normal" />
            <Box
                sx={{
                    display: "flex",
                    flexDirection: "column",
                    alignItems: "center",
                    mt: 1,
                }}
            >
                {/* パスワードをお忘れですか？ */}
                <Link
                    to={paths.password.resetRquest}
                    variant="caption"
                    sx={{
                        alignSelf: "flex-start",
                        mb: 2,
                    }}
                >
                    パスワードをお忘れですか？
                </Link>
                {/* ログインボタン */}
                <Button type="submit" sx={{ ...buttonStyle, mb: 2 }}>
                    ログイン
                </Button>
                {/* Googleでログインボタン */}
                <Button variant="outlined" startIcon={<FcGoogle />} sx={{ ...buttonStyle, mb: 2 }}>
                    Googleでログイン
                </Button>
                {/* Githubでログインボタン */}
                <Button variant="outlined" startIcon={<FaGithub />} sx={{ ...buttonStyle, mb: 2 }}>
                    Githubでログイン
                </Button>
                {/* 新規登録はこちら */}
                <Link to={paths.register} variant="body2">
                    新規登録はこちら
                </Link>
            </Box>
        </Box>
    );
};
