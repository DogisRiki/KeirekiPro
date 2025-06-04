import { SettingMessages } from "@/features/user";
import { Alert, Box } from "@mui/material";

export interface AuthProviderWarningMessageProps {
    messages: SettingMessages;
}

/**
 * 外部連携情報の警告メッセージを表示
 */
export const AuthProviderWarningMessage = ({ messages }: AuthProviderWarningMessageProps) => {
    if (!messages.providerMessage) return null;
    return (
        <Box sx={{ mb: 4 }}>
            <Alert severity="warning" variant="outlined">
                {messages.providerMessage}
            </Alert>
        </Box>
    );
};
