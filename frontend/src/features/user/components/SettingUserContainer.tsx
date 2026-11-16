import type { SettingMessages } from "@/features/user";
import {
    createUserSettingMessages,
    isProviderRemovable,
    isTwoFactorDisabled,
    PROFILE_IMAGE_TYPES,
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
    // 選んだ画像のプレビュー。選んでいないときは今の画像を出す
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);
    // 利用者が触ったスイッチの値。触っていないときは、サーバーから届いた最新の設定を出す
    const [twoFactorInput, setTwoFactorInput] = useState<boolean | null>(null);
    const twoFactor = twoFactorInput ?? user?.twoFactorAuthEnabled ?? false;

    const twoFactorDisabled = isTwoFactorDisabled(user);
    const canRemoveProvider = isProviderRemovable(user);
    const providerCount = Array.isArray(user?.authProviders) ? user.authProviders.length : 0;
    const emailVerified = user?.emailVerified ?? false;

    const messages: SettingMessages = useMemo(
        () => createUserSettingMessages(userState, providerCount, emailVerified),
        [userState, providerCount, emailVerified],
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

    // 画像を選び直したときと画面を離れるときに、前のプレビューをブラウザのメモリから外す
    useEffect(() => {
        if (!previewUrl) return;
        return () => URL.revokeObjectURL(previewUrl);
    }, [previewUrl]);

    /**
     * 画像選択ハンドラ
     */
    const handleProfileImageChange = (file: File | null) => {
        if (!file) return;

        if (!PROFILE_IMAGE_TYPES.includes(file.type)) {
            setErrors({
                message: "プロフィール画像はJPEG、PNG、GIFのいずれかである必要があります。",
                errors: {},
            });
            return;
        }

        if (file.size > MAX_FILE_SIZE) {
            setErrors({
                message: "プロフィール画像のサイズは1MB以下である必要があります。",
                errors: {},
            });
            return;
        }

        setProfileImageFile(file);
        setPreviewUrl(URL.createObjectURL(file));
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
            emailVerified={user.emailVerified}
            pendingEmail={user.pendingEmail}
            username={username}
            onUsernameChange={setUsername}
            profileImageUrl={previewUrl ?? user.profileImage}
            onProfileImageChange={handleProfileImageChange}
            twoFactorEnabled={twoFactor}
            twoFactorDisabled={twoFactorDisabled}
            onToggleTwoFactor={setTwoFactorInput}
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
