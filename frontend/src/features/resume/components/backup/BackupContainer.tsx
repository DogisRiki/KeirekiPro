import { NoData } from "@/components/errors";
import { BackupSection, RestoreSection, useGetResumeList } from "@/features/resume";
import { Box, Divider, Paper, Typography } from "@mui/material";

/**
 * バックアップコンテナ
 */
export const BackupContainer = () => {
    const { data } = useGetResumeList();
    const resumeList = data?.resumes ?? [];

    return (
        <Paper elevation={1} sx={{ p: 3 }}>
            {/* バックアップセクション */}
            {resumeList.length > 0 ? (
                <BackupSection resumeList={resumeList} />
            ) : (
                <Box>
                    <Typography variant="h6" gutterBottom sx={{ mb: 2 }}>
                        バックアップ
                    </Typography>
                    <NoData message="バックアップ可能な職務経歴書がありません。" />
                </Box>
            )}

            <Divider sx={{ my: 3 }} />

            {/* リストアセクション */}
            <RestoreSection />

            {/* 注意事項 */}
            <Box sx={{ mt: 3 }}>
                <Typography variant="body2" color="text.secondary">
                    ※ リストアすると新しい職務経歴書として作成されます
                </Typography>
                <Typography variant="body2" color="text.secondary">
                    ※ 同名の職務経歴書が存在する場合はエラーとなります
                </Typography>
            </Box>
        </Paper>
    );
};
