import { Button } from "@/components/ui";
import { useErrorMessageStore } from "@/stores";
import { stringListToBulletList } from "@/utils";
import { Box, useTheme } from "@mui/material";
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
    const theme = useTheme();

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
                inputProps={{
                    inputMode: "numeric",
                    autoComplete: "one-time-code",
                    style: {
                        fontSize: "16px", // iOS自動ズーム防止
                    },
                }}
                classNames={{
                    container: "verification-container",
                    character: "verification-character",
                    characterInactive: "verification-character--inactive",
                    characterSelected: "verification-character--selected",
                }}
            />
            {errors.code && (
                <Box
                    sx={{
                        mt: 2,
                        color: "error.main",
                        typography: "caption",
                        whiteSpace: "pre-line",
                    }}
                >
                    {stringListToBulletList(errors.code)}
                </Box>
            )}
            <Box sx={{ mt: 4 }}>
                <Button type="submit" disabled={code.length !== 6 || loading}>
                    認証
                </Button>
            </Box>
            <style>
                {`
                    .verification-container{display:flex;justify-content:center;gap:8px;}
                    .verification-character{width:40px!important;height:48px!important;border:1px solid ${theme.palette.divider};border-radius:4px;font-size:1.25rem;display:flex;align-items:center;justify-content:center;background-color:${theme.palette.background.paper};color:${theme.palette.text.primary};outline:none!important;}
                    .verification-character:focus{outline:none!important;box-shadow:none!important;}
                    .verification-character--selected{border-color:${theme.palette.primary.main};border-width:2px;outline:none!important;box-shadow:none!important;}
                    .verification-character--inactive{background-color:transparent;}
                    @media(min-width:600px){.verification-container{gap:16px;}.verification-character{width:56px!important;height:56px!important;font-size:1.5rem;}}
                `}
            </style>
        </Box>
    );
};
