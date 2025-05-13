import { paths } from "@/config/paths";
import { TwoFactorForm, useTwoFactorStore, useVerifyTwoFactor } from "@/features/auth";
import { useState } from "react";
import { Navigate } from "react-router";

/**
 * 二段階認証コンテナ
 */
export const TwoFactorContainer = () => {
    const { userId } = useTwoFactorStore();
    const [code, setCode] = useState("");
    const verifyMutation = useVerifyTwoFactor();

    // userIdがない場合不正アクセスなので直ちにトップへ戻す
    if (!userId) return <Navigate to={paths.top} replace />;

    return (
        <TwoFactorForm
            code={code}
            onCodeChange={(v) => {
                setCode(v);
            }}
            onSubmit={() => verifyMutation.mutate(code)}
            loading={verifyMutation.isPending}
        />
    );
};
