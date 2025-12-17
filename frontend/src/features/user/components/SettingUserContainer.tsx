import type { SettingMessages } from "@/features/user";
import {
    createUserSettingMessages,
    SettingUserForm,
    useDeleteUser,
    useRemoveAuthProvider,
    UserState,
    useUpdateUserInfo,
    useUserState,
} from "@/features/user";
import { isProviderRemovable, isTwoFactorDisabled } from "@/features/user/utils/userSettingRules";
import { useGetUserInfo } from "@/hooks";
import { useUserAuthStore } from "@/stores";
import { useCallback, useEffect, useMemo, useState } from "react";

/**
 * ユーザー設定コンテナ
 */
export const SettingUserContainer = () => {
    const { user, setLogin } = useUserAuthStore();
    const userState = useUserState();

    const [username, setUsername] = useState(user?.username ?? "");
    const [profileImageFile, setProfileImageFile] = useState<File | null>(null);
    const [profileImageUrl, setProfileImageUrl] = useState<string | null>(user?.profileImage ?? null);
    const [twoFactor, setTwoFactor] = useState<boolean>(user?.twoFactorAuthEnabled ?? false);

    // 二段階認証設定の設定可否
    const twoFactorDisabled = isTwoFactorDisabled(userState);

    // 外部連携認証情報の解除可否
    const canRemoveProvider = isProviderRemovable(userState, user?.authProviders);

    // プロバイダー数
    const providerCount = Array.isArray(user?.authProviders) ? user.authProviders.length : 0;

    /**
     * 表示用メッセージ生成
     */
    const messages: SettingMessages = useMemo(
        () => createUserSettingMessages(userState, providerCount),
        [userState, providerCount],
    );

    const { data, isSuccess } = useGetUserInfo();
    const updateMutation = useUpdateUserInfo();
    const removeProviderMutation = useRemoveAuthProvider();
    const deleteUserMutation = useDeleteUser();

    /**
     * ユーザー情報を取得
     */
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
        setProfileImageFile(file);
        setProfileImageUrl(URL.createObjectURL(file));
    };

    /**
     * ユーザー情報更新ハンドラ
     */
    const handleSave = useCallback(() => {
        if (!user) return;

        updateMutation.mutate({
            username: username !== user.username ? username : undefined,
            profileImage: profileImageFile ?? undefined,
            twoFactorAuthEnabled: twoFactor !== user.twoFactorAuthEnabled ? twoFactor : undefined,
        });
    }, [username, profileImageFile, twoFactor, user, updateMutation]);

    /**
     * 退会ハンドラ
     */
    const handleDelete = () => {
        deleteUserMutation.mutate();
    };

    // ユーザー未取得時レンダリングしない
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
