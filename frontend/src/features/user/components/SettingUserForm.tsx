import { Button, TextField } from "@/components/ui";
import {
    AuthProviderField,
    AuthProviderWarningMessage,
    PasswordStatusBox,
    ProfileImageField,
    SettingMessages,
    TwoFactorSwitch,
} from "@/features/user";
import { useErrorMessageStore } from "@/stores";
import { Box } from "@mui/material";

export interface SettingUserFormProps {
    email: string | null;
    username: string;
    onUsernameChange: (v: string) => void;
    profileImageUrl: string | null;
    onProfileImageChange: (file: File | null) => void;
    twoFactorEnabled: boolean;
    twoFactorDisabled: boolean;
    onToggleTwoFactor: (v: boolean) => void;
    authProviders: ("google" | "github")[];
    canRemoveProvider: boolean;
    onRemoveProvider: (p: "google" | "github") => void;
    messages: SettingMessages;
    onSave: () => void;
    saving?: boolean;
}

/**
 * ユーザー設定フォーム
 */
export const SettingUserForm = ({
    email,
    username,
    onUsernameChange,
    profileImageUrl,
    onProfileImageChange,
    twoFactorEnabled,
    twoFactorDisabled,
    onToggleTwoFactor,
    authProviders,
    canRemoveProvider,
    onRemoveProvider,
    messages,
    onSave,
    saving = false,
}: SettingUserFormProps) => {
    const { errors } = useErrorMessageStore();

    return (
        <Box
            component="form"
            onSubmit={(e) => {
                e.preventDefault();
                onSave();
            }}
            sx={{ position: "relative", width: "fit-content", mx: "auto", my: 4 }}
        >
            <ProfileImageField currentImage={profileImageUrl} onChange={onProfileImageChange} />

            <TextField
                type="email"
                label="メールアドレス（変更できません）"
                value={email ?? ""}
                fullWidth
                disabled
                margin="normal"
                error={!!errors.email?.length}
                helperText={errors.email?.[0] ?? ""}
                sx={{ mt: 4, mb: 4 }}
            />

            <TextField
                label="ユーザー名"
                fullWidth
                required
                value={username}
                onChange={(e) => onUsernameChange(e.target.value)}
                error={!!errors.username?.length}
                helperText={errors.username?.[0] ?? ""}
                margin="normal"
                sx={{ mb: 4 }}
            />

            <TwoFactorSwitch enabled={twoFactorEnabled} disabled={twoFactorDisabled} onToggle={onToggleTwoFactor} />

            <PasswordStatusBox
                statusLabel={messages.emailPasswordStatusLabel}
                navigationMessage={messages.emailPasswordNavigationMessage}
                isWarning={messages.emailPasswordIsWarning}
                linkPath={messages.emailPasswordLinkPath}
            />

            <AuthProviderWarningMessage messages={messages} />

            <AuthProviderField
                connected={authProviders}
                canRemoveProvider={canRemoveProvider}
                onRemove={onRemoveProvider}
            />

            <Box sx={{ display: "flex", justifyContent: "center", mb: 4 }}>
                <Button type="submit" sx={{ width: 240 }} disabled={saving}>
                    保存
                </Button>
            </Box>

            <Box sx={{ display: "flex", justifyContent: "center" }}>
                <Button
                    color="error"
                    variant="outlined"
                    sx={{
                        width: 240,
                        "&:hover": {
                            bgcolor: "error.main",
                            color: "error.contrastText",
                            borderColor: "error.main",
                        },
                    }}
                >
                    退会
                </Button>
            </Box>
        </Box>
    );
};
