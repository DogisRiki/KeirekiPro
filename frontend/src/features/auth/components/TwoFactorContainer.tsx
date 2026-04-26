import { TwoFactorForm, useVerifyTwoFactor } from "@/features/auth";
import { useState } from "react";

/**
 * 二段階認証コンテナ
 */
export const TwoFactorContainer = () => {
    const [code, setCode] = useState("");
    const verifyMutation = useVerifyTwoFactor();

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
