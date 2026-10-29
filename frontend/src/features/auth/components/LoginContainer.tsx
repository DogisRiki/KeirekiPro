import type { EmailNotVerifiedKind } from "@/features/auth";
import {
    EmailVerificationNotice,
    LoginForm,
    useAuthorizeOidc,
    useLogin,
    useResendEmailVerificationForLogin,
} from "@/features/auth";
import { Alert } from "@mui/material";
import type { AxiosError } from "axios";
import { useState } from "react";
import { useSearchParams } from "react-router";

const EMAIL_NOT_VERIFIED_KINDS: readonly EmailNotVerifiedKind[] = ["PENDING_REGISTRATION", "UNVERIFIED_ACCOUNT_EMAIL"];

const UNVERIFIED_EMAIL_MESSAGE =
    "このメールアドレスのアカウントがすでにあります。先にメールアドレスとパスワードでログインし、メールアドレスの確認を済ませてください。";

/**
 * ログインの失敗が確認がまだの 409 なら、その kind を返す
 * @param error ログインの失敗
 * @returns 確認がまだの kind。ほかの失敗のときは null
 */
const toEmailNotVerifiedKind = (error: AxiosError | null): EmailNotVerifiedKind | null => {
    if (error?.response?.status !== 409) {
        return null;
    }
    const kind = (error.response.data as { kind?: unknown } | undefined)?.kind;
    return EMAIL_NOT_VERIFIED_KINDS.find((k) => k === kind) ?? null;
};

/**
 * ログインコンテナ
 */
export const LoginContainer = () => {
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [searchParams] = useSearchParams();
    const loginMutation = useLogin();
    const oidcMutation = useAuthorizeOidc();
    const resendMutation = useResendEmailVerificationForLogin();

    const emailNotVerifiedKind = toEmailNotVerifiedKind(loginMutation.error);
    // クエリの文字列は画面に出さず、決まった値のときだけ決まった文を出す
    const showUnverifiedEmailMessage = searchParams.get("error") === "unverified_email";

    return (
        <>
            {showUnverifiedEmailMessage && (
                <Alert severity="info" sx={{ mb: 3, textAlign: "left" }}>
                    {UNVERIFIED_EMAIL_MESSAGE}
                </Alert>
            )}
            {emailNotVerifiedKind && (
                <EmailVerificationNotice
                    kind={emailNotVerifiedKind}
                    onSend={() => resendMutation.mutate({ email, password })}
                    loading={resendMutation.isPending}
                />
            )}
            <LoginForm
                email={email}
                password={password}
                onEmailChange={(v) => {
                    setEmail(v);
                }}
                onPasswordChange={(v) => {
                    setPassword(v);
                }}
                onSubmit={() => loginMutation.mutate({ email, password })}
                onOidcLogin={(provider) => oidcMutation.mutate(provider)}
                loading={loginMutation.isPending || oidcMutation.isPending}
            />
        </>
    );
};
