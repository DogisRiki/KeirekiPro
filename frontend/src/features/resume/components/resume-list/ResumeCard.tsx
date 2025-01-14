import { ResumeCardMenu } from "@/features/resume";
import { DateRange as DateRangeIcon } from "@mui/icons-material";
import { Box, Card, CardContent, Typography } from "@mui/material";

interface resumeCardProps {
    resumeId: string;
    resumeName: string;
    createdAt: string;
    updatedAt: string;
}

/**
 * 職務経歴書カード
 */
export const ResumeCard = ({ resumeId, resumeName, createdAt, updatedAt }: resumeCardProps) => {
    return (
        <Card
            key={resumeId}
            sx={{
                cursor: "pointer",
                transition: "0.3s",
                "&:hover": {
                    opacity: 0.7,
                },
            }}
        >
            <CardContent sx={{ position: "relative" }}>
                {/* メニュー */}
                <ResumeCardMenu resumeId={resumeId} />
                {/* 職務経歴書名 */}
                <Typography variant="h6" gutterBottom>
                    {resumeName}
                </Typography>
                {/* 作成日時 */}
                <Box sx={{ display: "flex", alignItems: "center", mb: 1 }}>
                    <DateRangeIcon sx={{ mr: 1 }} />
                    <Typography variant="body2" color="text.secondary">
                        作成日時: {createdAt}
                    </Typography>
                </Box>
                {/* 更新日時 */}
                <Box sx={{ display: "flex", alignItems: "center" }}>
                    <DateRangeIcon sx={{ mr: 1 }} />
                    <Typography variant="body2" color="text.secondary">
                        更新日時: {updatedAt}
                    </Typography>
                </Box>
            </CardContent>
        </Card>
    );
};
