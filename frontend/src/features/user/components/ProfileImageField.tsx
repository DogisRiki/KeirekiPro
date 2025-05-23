import { PhotoCamera as PhotoCameraIcon } from "@mui/icons-material";
import { Avatar, Box, IconButton } from "@mui/material";
import { useRef, useState } from "react";

export interface ProfileImageFieldProps {
    // 現在保存済みの画像URL
    currentImage: string | null;
    //  画像変更時コールバック (未選択はnull)
    onChange: (file: File | null) => void;
}

/**
 * プロフィール画像を表示・更新するフィールド
 */
export const ProfileImageField = ({ currentImage, onChange }: ProfileImageFieldProps) => {
    const fileInputRef = useRef<HTMLInputElement | null>(null);
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);
    const [imgError, setImgError] = useState(false);

    /**
     * ファイル選択ボタン押下ハンドラ
     */
    const handleClick = () => fileInputRef.current?.click();

    /**
     * ファイル選択ハンドラ
     */
    const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;
        setPreviewUrl(URL.createObjectURL(file));
        setImgError(false);
        onChange(file);
    };

    return (
        <Box sx={{ position: "relative", width: "fit-content", mx: "auto" }}>
            <Avatar
                src={!imgError ? (previewUrl ?? currentImage ?? undefined) : undefined}
                alt="プロフィール画像"
                sx={{ width: 120, height: 120 }}
                onError={() => setImgError(true)}
            />
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
                onClick={handleClick}
            >
                <PhotoCameraIcon />
            </IconButton>
            <input ref={fileInputRef} hidden type="file" accept="image/*" onChange={handleFileChange} />
        </Box>
    );
};
