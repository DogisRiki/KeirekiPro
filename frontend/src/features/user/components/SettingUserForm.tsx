import { Button, TextField } from "@/components/ui";
import { paths } from "@/config/paths";
import { useUserAuthStore } from "@/stores";
import {
    Cancel as CancelIcon,
    CheckCircle as CheckCircleIcon,
    Person as PersonIcon,
    PhotoCamera as PhotoCameraIcon,
} from "@mui/icons-material";
import { Avatar, Box, FormControlLabel, FormGroup, IconButton, Switch, Typography } from "@mui/material";
import { useRef, useState } from "react";
import { useNavigate } from "react-router";

/**
 * ユーザー設定フォーム
 */
export const SettingUserForm = () => {
    const { user, updateProfile } = useUserAuthStore();
    const navigate = useNavigate();

    // ファイル選択ボタン押下時の挙動
    const fileInputRef = useRef<HTMLInputElement | null>(null);

    // プロフィール画像のプレビュー用
    const [tempProfileImage, setTempProfileImage] = useState<string | null>(null);

    // Button内のinput属性への参照
    const handleInputButtonClick = () => {
        fileInputRef.current?.click();
    };

    // プロフィール画像変更ハンドラー
    const handleProfileImageChange = (event: React.ChangeEvent<HTMLInputElement>) => {
        if (event.target.files && event.target.files.length > 0) {
            const file = event.target.files[0];
            // 選択した画像をプレビュー表示
            const previewUrl = URL.createObjectURL(file);
            setTempProfileImage(previewUrl);
        }
    };

    // 保存処理
    const handleSave = () => {
        if (tempProfileImage) {
            updateProfile({
                profileImage: tempProfileImage,
            });
        }
    };

    return (
        <Box>
            <Box sx={{ position: "relative", width: "fit-content", mx: "auto", my: 4 }}>
                <Avatar
                    alt="プロフィール画像"
                    src={tempProfileImage || user?.profileImage || undefined}
                    sx={{ width: 120, height: 120 }}
                >
                    {/* srcがない場合に表示するデフォルトのアイコン */}
                    {!(tempProfileImage || user?.profileImage) && <PersonIcon sx={{ width: 80, height: 80 }} />}
                </Avatar>
                <IconButton
                    color="primary"
                    sx={{
                        position: "absolute",
                        right: -10,
                        bottom: -10,
                        bgcolor: "background.paper",
                        boxShadow: 1,
                        "&:hover": { bgcolor: "background.paper" },
                    }}
                    onClick={handleInputButtonClick}
                >
                    <PhotoCameraIcon />
                </IconButton>
                <input type="file" hidden ref={fileInputRef} accept="image/*" onChange={handleProfileImageChange} />
            </Box>
            <Box>
                {/* メールアドレス */}
                <TextField
                    label="メールアドレス（変更できません）"
                    value={user?.email}
                    fullWidth
                    disabled
                    sx={{ mb: 4 }}
                />
                {/* ユーザー名 */}
                <TextField label="ユーザー名" value={user?.userName} fullWidth required sx={{ mb: 4 }} />
                {/* 二段階認証 */}
                <FormGroup sx={{ mb: 4 }}>
                    <FormControlLabel
                        control={<Switch color="primary" checked={user?.twoFactorAuthEnabled} />}
                        label={
                            <Box>
                                <Typography variant="subtitle1">二段階認証</Typography>
                                <Typography variant="body2" color="text.secondary">
                                    アカウントのセキュリティを強化します
                                </Typography>
                            </Box>
                        }
                    />
                </FormGroup>
                {/* パスワード */}
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        gap: 2,
                        mb: 4,
                        p: 2,
                        borderRadius: 1,
                        bgcolor: "grey.50",
                        border: 1,
                        borderColor: user?.hasPassword ? "success.light" : "error.light",
                    }}
                >
                    <Box sx={{ display: "flex", alignItems: "center", flex: 1 }}>
                        {user?.hasPassword ? (
                            <>
                                <CheckCircleIcon
                                    sx={{
                                        mr: 1.5,
                                        color: "success.light",
                                        fontSize: 20,
                                    }}
                                />
                                <Box>
                                    <Typography
                                        variant="body1"
                                        sx={{
                                            fontWeight: 500,
                                            color: "text.primary",
                                            mb: 0.5,
                                        }}
                                    >
                                        パスワード設定済み
                                    </Typography>
                                    <Typography variant="body2" sx={{ color: "text.secondary" }}>
                                        パスワードを変更する場合は右のボタンをクリックしてください。
                                    </Typography>
                                </Box>
                            </>
                        ) : (
                            <>
                                <CancelIcon
                                    sx={{
                                        mr: 1.5,
                                        color: "error.light",
                                        fontSize: 20,
                                    }}
                                />
                                <Box>
                                    <Typography
                                        variant="body1"
                                        sx={{
                                            fontWeight: 500,
                                            color: "text.primary",
                                            mb: 0.5,
                                        }}
                                    >
                                        パスワード未設定
                                    </Typography>
                                    <Typography variant="body2" sx={{ color: "text.secondary" }}>
                                        セキュリティ強化のためパスワードを設定してください。
                                    </Typography>
                                </Box>
                            </>
                        )}
                    </Box>
                    <Button
                        variant="text"
                        onClick={() => navigate(paths.password.change)}
                        sx={{
                            whiteSpace: "nowrap",
                            color: user?.hasPassword ? "success.main" : "error.main",
                        }}
                    >
                        {user?.hasPassword ? "パスワードを変更" : "パスワードを設定"}
                    </Button>
                </Box>
                {/* 保存ボタン */}
                <Box sx={{ display: "flex", justifyContent: "center", mb: 4 }}>
                    <Button onClick={handleSave} sx={{ width: 240 }}>
                        保存
                    </Button>
                </Box>
                {/* 退会ボタン */}
                <Box sx={{ display: "flex", justifyContent: "center" }}>
                    <Button
                        color="error"
                        variant="outlined"
                        sx={{
                            width: 240,
                            "&:hover": {
                                backgroundColor: "error.main",
                                color: "error.contrastText",
                                borderColor: "error.main",
                            },
                        }}
                    >
                        退会
                    </Button>
                </Box>
            </Box>
        </Box>
    );
};
