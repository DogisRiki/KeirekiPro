import { Button, ConfirmDialog, TextField } from "@/components/ui";
import {
    AuthProviderField,
    AuthProviderWarningMessage,
    PasswordStatusBox,
    ProfileImageField,
    SettingMessages,
    TwoFactorSwitch,
} from "@/features/user";
import { useErrorMessageStore } from "@/stores";
import { AuthProvider } from "@/types";
import { stringListToBulletList } from "@/utils";
import { Box, FormControl, FormHelperText } from "@mui/material";
import { useState } from "react";

export interface SettingUserFormProps {
    email: string | null;
    username: string;
    onUsernameChange: (v: string) => void;
    profileImageUrl: string | null;
    onProfileImageChange: (file: File | null) => void;
    twoFactorEnabled: boolean;
    twoFactorDisabled: boolean;
    onToggleTwoFactor: (v: boolean) => void;
    authProviders: AuthProvider[];
    canRemoveProvider: boolean;
    onRemoveProvider: (p: AuthProvider) => void;
    messages: SettingMessages;
    onSave: () => void;
    onDelete: () => void;
    loading?: boolean;
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
    onDelete,
    loading = false,
}: SettingUserFormProps) => {
    const { errors } = useErrorMessageStore();
    const [dialogOpen, setDialogOpen] = useState(false);

    const handleDeleteClick = () => {
        setDialogOpen(true);
    };

    const handleDialogClose = (confirmed: boolean) => {
        setDialogOpen(false);
        if (confirmed) {
            onDelete();
        }
    };

    return (
        <>
            <Box
                component="form"
                onSubmit={(e) => {
                    e.preventDefault();
                    onSave();
                }}
                sx={{ position: "relative", width: "fit-content", mx: "auto", my: 4 }}
            >
                <FormControl fullWidth error={!!errors.profileImage?.length}>
                    <ProfileImageField currentImage={profileImageUrl} onChange={onProfileImageChange} />
                    <FormHelperText sx={{ whiteSpace: "pre-line" }}>
                        {stringListToBulletList(errors.profileImage)}
                    </FormHelperText>
                </FormControl>

                <TextField
                    type="email"
                    label={email ? "メールアドレス（変更できません）" : "メールアドレスが設定されていません"}
                    value={email ?? ""}
                    fullWidth
                    disabled
                    margin="normal"
                    error={!!errors.email?.length}
                    helperText={stringListToBulletList(errors.email)}
                    slotProps={{
                        formHelperText: { sx: { whiteSpace: "pre-line" } },
                    }}
                    sx={{ mt: 4, mb: 4 }}
                />

                <TextField
                    label="ユーザー名"
                    fullWidth
                    required
                    value={username}
                    onChange={(e) => onUsernameChange(e.target.value)}
                    error={!!errors.username?.length}
                    helperText={stringListToBulletList(errors.username)}
                    slotProps={{
                        formHelperText: { sx: { whiteSpace: "pre-line" } },
                        htmlInput: { maxLength: 50 },
                    }}
                    margin="normal"
                    sx={{ mb: 4 }}
                />

                <FormControl fullWidth sx={{ mb: 4 }} error={!!errors.twoFactorAuthEnabled?.length}>
                    <TwoFactorSwitch
                        enabled={twoFactorEnabled}
                        disabled={twoFactorDisabled}
                        onToggle={onToggleTwoFactor}
                    />
                    <FormHelperText sx={{ whiteSpace: "pre-line" }}>
                        {stringListToBulletList(errors.twoFactorAuthEnabled)}
                    </FormHelperText>
                </FormControl>

                <PasswordStatusBox
                    statusLabel={messages.emailPasswordStatusLabel}
                    navigationMessage={messages.emailPasswordNavigationMessage}
                    isWarning={messages.emailPasswordIsWarning}
                    linkPath={messages.emailPasswordLinkPath}
                />

                <AuthProviderWarningMessage messages={messages} />

                <FormControl fullWidth sx={{ mb: 4 }} error={!!errors.authProviders?.length}>
                    <AuthProviderField
                        connected={authProviders}
                        canRemoveProvider={canRemoveProvider}
                        onRemove={onRemoveProvider}
                    />
                    <FormHelperText sx={{ whiteSpace: "pre-line" }}>
                        {stringListToBulletList(errors.authProviders)}
                    </FormHelperText>
                </FormControl>

                <Box sx={{ display: "flex", justifyContent: "center", mb: 4 }}>
                    <Button type="submit" sx={{ width: 240 }} disabled={loading}>
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
                        onClick={handleDeleteClick}
                    >
                        退会
                    </Button>
                </Box>
            </Box>

            <ConfirmDialog
                open={dialogOpen}
                title="退会のご確認"
                description="本当に退会しますか？この操作は取り消せません。"
                onClose={handleDialogClose}
            />
        </>
    );
};
