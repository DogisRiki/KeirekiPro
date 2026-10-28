import { Button, Link, Loading } from "@/components/ui";
import { paths } from "@/config/paths";
import type { VerifyEmailResponse } from "@/features/auth";
import { ResetPasswordForm, useResendEmailVerification, useResetPassword, useVerifyEmail } from "@/features/auth";
import { Box, Typography } from "@mui/material";
import { useEffect, useState } from "react";
import { useLocation, useNavigate } from "react-router";

const INVALID_MESSAGE = "このリンクは正しくありません。";

/**
 * 確認が済んだあとに出す、パスワードの再設定の入力欄
 */
const PasswordResetSection = ({ passwordResetToken }: { passwordResetToken: string }) => {
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const resetPasswordMutation = useResetPassword();

    return (
        <>
            <Typography variant="body1" sx={{ mb: 2 }}>
                メールアドレスの確認が済みました。続けて新しいパスワードを設定してください。
            </Typography>
            <ResetPasswordForm
                password={password}
                confirmPassword={confirmPassword}
                onPasswordChange={setPassword}
                onConfirmPasswordChange={setConfirmPassword}
                onSubmit={() => resetPasswordMutation.mutate({ token: passwordResetToken, password, confirmPassword })}
                loading={resetPasswordMutation.isPending}
            />
        </>
    );
};

/**
 * 確認のリンクの結果ごとの文とボタン
 */
const VerificationResult = ({ response, token }: { response: VerifyEmailResponse; token: string }) => {
    const navigate = useNavigate();
    const resendMutation = useResendEmailVerification();

    const loginButton = (
        <Button sx={{ mt: 2 }} onClick={() => navigate(paths.login, { replace: true })}>
            ログイン画面へ
        </Button>
    );

    switch (response.result) {
        case "VERIFIED":
            return (
                <>
                    <Typography variant="body1">メールアドレスの確認が済みました。ログインしてください。</Typography>
                    {loginButton}
                </>
            );
        case "PASSWORD_RESET_READY":
            return response.passwordResetToken ? (
                <PasswordResetSection passwordResetToken={response.passwordResetToken} />
            ) : (
                <Typography variant="body1">{INVALID_MESSAGE}</Typography>
            );
        case "ALREADY_VERIFIED":
            return (
                <>
                    <Typography variant="body1">
                        メールアドレスの確認はすでに済んでいます。ログインしてください。
                    </Typography>
                    {loginButton}
                </>
            );
        case "EXPIRED":
            return (
                <>
                    <Typography variant="body1">
                        このリンクは使えなくなっています。確認のメールを送り直してください。
                    </Typography>
                    <Button
                        sx={{ mt: 2 }}
                        onClick={() => resendMutation.mutate({ token })}
                        disabled={resendMutation.isPending}
                    >
                        確認のメールを送り直す
                    </Button>
                </>
            );
        case "REGISTRATION_GONE":
            return (
                <>
                    <Typography variant="body1" sx={{ mb: 2 }}>
                        このリンクは使えなくなっています。お手数ですが、もう一度登録してください。
                    </Typography>
                    <Link to={paths.register} variant="body2">
                        登録の画面へ
                    </Link>
                </>
            );
        case "EMAIL_TAKEN":
            return (
                <Typography variant="body1">
                    このメールアドレスは、すでにほかのアカウントが使っているため、使えません。
                </Typography>
            );
        default:
            return <Typography variant="body1">{INVALID_MESSAGE}</Typography>;
    }
};

/**
 * 確認のリンクの画面のコンテナ
 * URL の # 以降からトークンを読み、確認の API を1回だけ呼んで、結果ごとの文とボタンを出す
 */
export const EmailVerificationContainer = () => {
    const { hash } = useLocation();
    const [token] = useState(() => hash.replace(/^#/, ""));
    const { data, isPending, isError } = useVerifyEmail(token);

    // トークンを読んだあと、ブラウザの履歴とアドレスバーにトークンを残さない
    useEffect(() => {
        if (window.location.hash) {
            window.history.replaceState(
                window.history.state,
                "",
                `${window.location.pathname}${window.location.search}`,
            );
        }
    }, []);

    if (!token || isError) {
        return <Typography variant="body1">{INVALID_MESSAGE}</Typography>;
    }

    if (isPending) {
        return <Loading active variant="content" />;
    }

    return (
        <Box>
            <VerificationResult response={data} token={token} />
        </Box>
    );
};
