import { Button, Dialog, Select } from "@/components/ui";
import type { ResumeSummary } from "@/features/resume";
import { useBackupResume } from "@/features/resume";
import BackupIcon from "@mui/icons-material/Backup";
import { Box, FormControl, InputLabel, MenuItem, Typography } from "@mui/material";
import { useState } from "react";

interface BackupSectionProps {
    resumeList: ResumeSummary[];
}

/**
 * バックアップセクション
 */
export const BackupSection = ({ resumeList }: BackupSectionProps) => {
    const [selectedResumeId, setSelectedResumeId] = useState("");
    const [dialogOpen, setDialogOpen] = useState(false);
    const backupMutation = useBackupResume();

    /**
     * バックアップボタン押下時のハンドラー
     */
    const handleBackupClick = () => {
        setDialogOpen(true);
    };

    /**
     * 確認ダイアログのクローズハンドラー
     */
    const handleDialogClose = (confirmed: boolean) => {
        setDialogOpen(false);
        if (confirmed && selectedResumeId) {
            backupMutation.mutate(selectedResumeId);
        }
    };

    return (
        <Box>
            <Typography variant="h6" gutterBottom sx={{ mb: 2 }}>
                バックアップ
            </Typography>
            <Box sx={{ display: "flex", flexDirection: "column", gap: 2 }}>
                <FormControl fullWidth>
                    <InputLabel shrink>職務経歴書を選択</InputLabel>
                    <Select
                        value={selectedResumeId}
                        onChange={(e) => setSelectedResumeId(e.target.value)}
                        label="職務経歴書を選択"
                        displayEmpty
                        notched
                        renderValue={(selected) => {
                            if (!selected) {
                                return (
                                    <Box sx={{ color: (theme) => theme.palette.text.disabled }}>選択してください</Box>
                                );
                            }
                            const option = resumeList.find((resume) => resume.id === selected);
                            return option?.resumeName ?? "";
                        }}
                    >
                        {resumeList.map((resume) => (
                            <MenuItem key={resume.id} value={resume.id}>
                                {resume.resumeName}
                            </MenuItem>
                        ))}
                    </Select>
                </FormControl>
                <Button
                    startIcon={<BackupIcon />}
                    onClick={handleBackupClick}
                    disabled={!selectedResumeId || backupMutation.isPending}
                    sx={{ alignSelf: "flex-start" }}
                >
                    バックアップ
                </Button>
            </Box>
            <Dialog
                open={dialogOpen}
                title="確認"
                description="バックアップを実行します。"
                variant="confirm"
                onClose={handleDialogClose}
            />
        </Box>
    );
};
