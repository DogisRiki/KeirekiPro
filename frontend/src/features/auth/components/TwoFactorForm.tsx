import { Button } from "@/components/ui";
import { useErrorMessageStore } from "@/stores";
import { Box } from "@mui/material";
import VerificationInput from "react-verification-input";

export interface TwoFactorFormProps {
    code: string;
    onCodeChange: (v: string) => void;
    onSubmit: () => void;
    loading?: boolean;
}

/**
 * 二段階認証フォーム
 */
export const TwoFactorForm = ({ code, onCodeChange, onSubmit, loading = false }: TwoFactorFormProps) => {
    const { errors } = useErrorMessageStore();

    return (
        <Box
            component="form"
            onSubmit={(e) => {
                e.preventDefault();
                onSubmit();
            }}
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
            }}
        >
            <VerificationInput
                value={code}
                onChange={onCodeChange}
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
            {errors.code && <Box sx={{ mt: 2, color: "error.main", typography: "caption" }}>{errors.code[0]}</Box>}
            <Box sx={{ mt: 4 }}>
                <Button type="submit" disabled={code.length !== 6 || loading}>
                    認証
                </Button>
            </Box>
            <style>
                {`
                    .verification-container{display:flex;justify-content:center;gap:16px;}
                    .verification-character{width:56px!important;height:56px!important;border:1px solid rgba(0,0,0,0.23);border-radius:4px;font-size:1.5rem;display:flex;align-items:center;justify-content:center;}
                    .verification-character:focus{box-shadow:0 0 0 2px #2C3E50;}
                    .verification-character--selected{border-color:#2C3E50;border-width:2px;}
                    .verification-character--inactive{background-color:transparent;}
                `}
            </style>
        </Box>
    );
};
