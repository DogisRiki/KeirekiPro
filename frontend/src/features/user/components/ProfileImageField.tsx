import PhotoCameraIcon from "@mui/icons-material/PhotoCamera";
import { Avatar, Box, IconButton } from "@mui/material";
import { useRef, useState } from "react";

export interface ProfileImageFieldProps {
    currentImage: string | null;
    onChange: (file: File | null) => void;
}

/**
 * プロフィール画像を表示・更新するフィールド
 */
export const ProfileImageField = ({ currentImage, onChange }: ProfileImageFieldProps) => {
    const fileInputRef = useRef<HTMLInputElement | null>(null);
    const [imgError, setImgError] = useState(false);

    const handleClick = () => fileInputRef.current?.click();

    const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;
        setImgError(false);
        onChange(file);
        e.target.value = "";
    };

    return (
        <Box sx={{ position: "relative", width: "fit-content", mx: "auto" }}>
            <Avatar
                src={!imgError ? (currentImage ?? undefined) : undefined}
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
