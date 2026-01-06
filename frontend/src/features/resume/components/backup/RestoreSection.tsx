import { Button } from "@/components/ui";
import { useRestoreResume } from "@/features/resume";
import CancelIcon from "@mui/icons-material/Cancel";
import CloudUploadIcon from "@mui/icons-material/CloudUpload";
import InsertDriveFileIcon from "@mui/icons-material/InsertDriveFile";
import RestoreIcon from "@mui/icons-material/Restore";
import { Box, IconButton, Tooltip, Typography } from "@mui/material";
import { useCallback, useState } from "react";
import { useDropzone } from "react-dropzone";

/**
 * リストアセクション
 */
export const RestoreSection = () => {
    const [selectedFile, setSelectedFile] = useState<File | null>(null);
    const [fileError, setFileError] = useState<string | null>(null);
    const restoreMutation = useRestoreResume();

    /**
     * ファイルドロップ時のハンドラー
     */
    const onDrop = useCallback((acceptedFiles: File[], rejectedFiles: any[]) => {
        setFileError(null);

        if (rejectedFiles.length > 0) {
            setFileError("JSONファイルのみ選択可能です。");
            setSelectedFile(null);
            return;
        }

        if (acceptedFiles.length > 0) {
            setSelectedFile(acceptedFiles[0]);
        }
    }, []);

    const { getRootProps, getInputProps, isDragActive, isDragReject } = useDropzone({
        onDrop,
        accept: {
            "application/json": [".json"],
        },
        multiple: false,
    });

    /**
     * ファイル選択解除
     */
    const handleClearFile = (e: React.MouseEvent) => {
        e.stopPropagation();
        setSelectedFile(null);
        setFileError(null);
    };

    /**
     * リストアボタン押下時のハンドラー
     */
    const handleRestore = () => {
        if (selectedFile) {
            restoreMutation.mutate(selectedFile);
        }
    };

    /**
     * ドロップゾーンの枠線色を決定
     */
    const getBorderColor = () => {
        if (isDragReject || fileError) return "error.main";
        if (isDragActive) return "primary.main";
        if (selectedFile) return "success.main";
        return "grey.400";
    };

    /**
     * ドロップゾーンの背景色を決定
     */
    const getBgColor = () => {
        if (isDragReject || fileError) return "error.lighter";
        if (isDragActive) return "action.hover";
        if (selectedFile) return "success.lighter";
        return "background.paper";
    };

    return (
        <Box>
            <Typography variant="h6" gutterBottom sx={{ mb: 2 }}>
                リストア
            </Typography>
            <Box sx={{ display: "flex", flexDirection: "column", gap: 2 }}>
                <Box
                    {...getRootProps()}
                    sx={{
                        border: "2px dashed",
                        borderColor: getBorderColor(),
                        borderRadius: 2,
                        p: 3,
                        textAlign: "center",
                        cursor: "pointer",
                        bgcolor: getBgColor(),
                        transition: "all 0.2s ease",
                        "&:hover": {
                            borderColor: selectedFile ? "success.main" : "primary.main",
                            bgcolor: selectedFile ? "success.lighter" : "action.hover",
                        },
                        minHeight: 120,
                        display: "flex",
                        flexDirection: "column",
                        justifyContent: "center",
                        alignItems: "center",
                    }}
                >
                    <input {...getInputProps()} />

                    {selectedFile ? (
                        <Box sx={{ display: "flex", alignItems: "center", gap: 1, maxWidth: "100%" }}>
                            <InsertDriveFileIcon sx={{ fontSize: 32, color: "success.main", flexShrink: 0 }} />
                            <Tooltip title={selectedFile.name} placement="top">
                                <Typography
                                    variant="body1"
                                    sx={{
                                        color: "text.primary",
                                        fontWeight: 500,
                                        overflow: "hidden",
                                        textOverflow: "ellipsis",
                                        whiteSpace: "nowrap",
                                        maxWidth: 300,
                                    }}
                                >
                                    {selectedFile.name}
                                </Typography>
                            </Tooltip>
                            <Tooltip title="選択解除" placement="top">
                                <IconButton size="small" onClick={handleClearFile} sx={{ flexShrink: 0 }}>
                                    <CancelIcon sx={{ color: "text.secondary" }} />
                                </IconButton>
                            </Tooltip>
                        </Box>
                    ) : (
                        <>
                            <CloudUploadIcon
                                sx={{
                                    fontSize: 40,
                                    color: isDragReject ? "error.main" : "text.secondary",
                                    mb: 1,
                                }}
                            />
                            <Typography variant="body2" color={isDragReject ? "error.main" : "text.secondary"}>
                                {isDragReject
                                    ? "JSONファイルのみ選択可能です"
                                    : isDragActive
                                      ? "ファイルをドロップしてください"
                                      : "ファイルをドラッグ＆ドロップ または クリックして選択"}
                            </Typography>
                        </>
                    )}
                </Box>
                <Button
                    startIcon={<RestoreIcon />}
                    onClick={handleRestore}
                    disabled={!selectedFile || restoreMutation.isPending}
                    sx={{ alignSelf: "flex-start" }}
                >
                    リストア
                </Button>
            </Box>
        </Box>
    );
};
