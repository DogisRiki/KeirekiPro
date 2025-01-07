import { Button } from "@/components/ui";
import { Box } from "@mui/material";
import { useState } from "react";
import VerificationInput from "react-verification-input";

/**
 * 2段階認証フォーム
 */
export const TwoFactorForm = () => {
    const [otp, setOtp] = useState("");

    // 送信処理
    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        // TODO: API呼び出し
        alert(`認証コード: ${otp}`);
    };

    return (
        <Box
            component="form"
            onSubmit={handleSubmit}
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
            }}
        >
            <VerificationInput
                value={otp}
                onChange={setOtp}
                length={6}
                validChars="0-9"
                placeholder=""
                classNames={{
                    container: "verification-container",
                    character: "verification-character",
                    characterInactive: "verification-character--inactive",
                    characterSelected: "verification-character--selected",
                }}
            />
            <Box sx={{ mt: 4 }}>
                <Button type="submit" disabled={otp.length !== 6}>
                    認証
                </Button>
            </Box>
            <style>
                {`
                    .verification-container {
                        display: flex;
                        justify-content: center;
                        gap: 16px;
                    }
                    .verification-character {
                        width: 56px !important;
                        height: 56px !important;
                        min-width: 56px !important;
                        min-height: 56px !important;
                        max-width: 56px !important;
                        max-height: 56px !important;
                        border: 1px solid rgba(0, 0, 0, 0.23);
                        border-radius: 4px;
                        font-size: 1.5rem;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        color: rgba(0, 0, 0, 0.87);
                        padding: 0 !important;
                        outline: none !important;
                    }
                    .verification-character:focus {
                        outline: none !important;
                        box-shadow: 0 0 0 2px #2C3E50;
                    }
                    .verification-character--selected {
                        border-color: #2C3E50;
                        border-width: 2px;
                    }
                    .verification-character--inactive {
                        background-color: transparent;
                    }
                `}
            </style>
        </Box>
    );
};
