import { Button, Checkbox, Link, PasswordTextField, TextField } from "@/components/ui";
import { env } from "@/config/env";
import { paths } from "@/config/paths";
import { Box, FormControlLabel, FormGroup } from "@mui/material";
import { useState } from "react";
import { FaGithub } from "react-icons/fa";
import { FcGoogle } from "react-icons/fc";

/**
 * 新規登録フォーム
 */
export const RegisterForm = () => {
    // チェックボックスのチェック状態
    const [isChecked, setIsChecked] = useState({ terms: false, privacy: false });

    // チェックボックスのハンドラー
    const handleCheck = (event: React.ChangeEvent<HTMLInputElement>) => {
        const { name, checked } = event.target;
        setIsChecked((prev) => ({
            ...prev,
            [name]: checked,
        }));
    };

    // 登録処理
    const handleRegister = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert("登録");
    };

    // ボタンの共通スタイル
    const buttonStyle = {
        width: "240px",
    };

    return (
        <Box component="form" onSubmit={handleRegister}>
            {/* メールアドレス */}
            <TextField
                type="email"
                label="メールアドレス"
                fullWidth
                required
                placeholder={env.APP_EMAIL}
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 2 }}
            />
            {/* ユーザー名 */}
            <TextField
                label="ユーザー名"
                fullWidth
                required
                placeholder="山田 太郎"
                margin="normal"
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
            {/* パスワード */}
            <PasswordTextField label="パスワード" fullWidth required margin="normal" />
            <FormGroup sx={{ mt: 1 }}>
                {/* 利用規約 */}
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
                {/* プライバシーポリシー */}
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
                {/* 登録ボタン */}
                <Button type="submit" sx={{ ...buttonStyle, mb: 2 }} disabled={!(isChecked.terms && isChecked.privacy)}>
                    登録
                </Button>
                {/* Googleで登録ボタン */}
                <Button variant="outlined" startIcon={<FcGoogle />} sx={{ ...buttonStyle, mb: 2 }}>
                    Googleで登録
                </Button>
                {/* Githubで登録ボタン */}
                <Button variant="outlined" startIcon={<FaGithub />} sx={{ ...buttonStyle, mb: 2 }}>
                    Githubで登録
                </Button>
                {/* アカウントをお持ちの方はこちら */}
                <Link to={paths.login} variant="body2">
                    アカウントをお持ちの方はこちら
                </Link>
            </Box>
        </Box>
    );
};
