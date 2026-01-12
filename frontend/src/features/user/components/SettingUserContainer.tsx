import type { SettingMessages } from "@/features/user";
import {
    createUserSettingMessages,
    isProviderRemovable,
    isTwoFactorDisabled,
    SettingUserForm,
    useDeleteUser,
    useRemoveAuthProvider,
    UserState,
    useUpdateUserInfo,
    useUserState,
} from "@/features/user";
import { useGetUserInfo } from "@/hooks";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { useCallback, useEffect, useMemo, useState } from "react";

/**
 * 許可する最大ファイルサイズ（1MB）
 */
const MAX_FILE_SIZE = 1024 * 1024;

/**
 * ユーザー設定コンテナ
 */
export const SettingUserContainer = () => {
    const { user, setLogin } = useUserAuthStore();
    const { setErrors } = useErrorMessageStore();
    const userState = useUserState();

    const [username, setUsername] = useState(user?.username ?? "");
    const [profileImageFile, setProfileImageFile] = useState<File | null>(null);
    const [profileImageUrl, setProfileImageUrl] = useState<string | null>(user?.profileImage ?? null);
    const [twoFactor, setTwoFactor] = useState<boolean>(user?.twoFactorAuthEnabled ?? false);

    const twoFactorDisabled = isTwoFactorDisabled(userState);
    const canRemoveProvider = isProviderRemovable(userState, user?.authProviders);
    const providerCount = Array.isArray(user?.authProviders) ? user.authProviders.length : 0;

    const messages: SettingMessages = useMemo(
        () => createUserSettingMessages(userState, providerCount),
        [userState, providerCount],
    );

    const { data, isSuccess } = useGetUserInfo();
    const updateMutation = useUpdateUserInfo();
    const removeProviderMutation = useRemoveAuthProvider();
    const deleteUserMutation = useDeleteUser();

    useEffect(() => {
        if (isSuccess && data) {
            setLogin(data);
        }
    }, [isSuccess, data, setLogin]);

    /**
     * 画像選択ハンドラ
     */
    const handleProfileImageChange = (file: File | null) => {
        if (!file) return;

        if (file.size > MAX_FILE_SIZE) {
            setErrors({
                message: "プロフィール画像のサイズは1MB以下である必要があります。",
                errors: {},
            });
            return;
        }

        setProfileImageFile(file);
        setProfileImageUrl(URL.createObjectURL(file));
    };

    const handleSave = useCallback(() => {
        if (!user) return;

        updateMutation.mutate({
            username: username !== user.username ? username : undefined,
            profileImage: profileImageFile ?? undefined,
            twoFactorAuthEnabled: twoFactor !== user.twoFactorAuthEnabled ? twoFactor : undefined,
        });
    }, [username, profileImageFile, twoFactor, user, updateMutation]);

    const handleDelete = () => {
        deleteUserMutation.mutate();
    };

    if (!user || userState === UserState.UNKNOWN) return <></>;

    return (
        <SettingUserForm
            email={user.email}
            username={username}
            onUsernameChange={setUsername}
            profileImageUrl={profileImageUrl}
            onProfileImageChange={handleProfileImageChange}
            twoFactorEnabled={twoFactor}
            twoFactorDisabled={twoFactorDisabled}
            onToggleTwoFactor={setTwoFactor}
            authProviders={user.authProviders}
            canRemoveProvider={canRemoveProvider}
            onRemoveProvider={(p) => removeProviderMutation.mutate(p)}
            messages={messages}
            onSave={handleSave}
            onDelete={handleDelete}
            loading={updateMutation.isPending || removeProviderMutation.isPending || deleteUserMutation.isPending}
        />
    );
};
