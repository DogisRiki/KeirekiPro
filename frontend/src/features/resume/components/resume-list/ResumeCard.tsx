import { ResumeCardMenu } from "@/features/resume";
import { formatDateTimeJa } from "@/utils";
import DateRangeIcon from "@mui/icons-material/DateRange";
import { Box, Card, CardContent, Typography } from "@mui/material";

interface resumeCardProps {
    resumeId: string;
    resumeName: string;
    createdAt: string;
    updatedAt: string;
    onClick?: () => void;
}

/**
 * 職務経歴書カード
 */
export const ResumeCard = ({ resumeId, resumeName, createdAt, updatedAt, onClick }: resumeCardProps) => {
    return (
        <Card
            key={resumeId}
            onClick={onClick}
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
                <ResumeCardMenu resumeId={resumeId} resumeName={resumeName} />
                {/* 職務経歴書名 */}
                <Typography
                    variant="h6"
                    gutterBottom
                    sx={{
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                        pr: 5,
                    }}
                >
                    {resumeName}
                </Typography>
                {/* 作成日時 */}
                <Box sx={{ display: "flex", alignItems: "center", mb: 1 }}>
                    <DateRangeIcon sx={{ mr: 1 }} />
                    <Typography variant="body2" color="text.secondary">
                        作成日時: {formatDateTimeJa(createdAt)}
                    </Typography>
                </Box>
                {/* 更新日時 */}
                <Box sx={{ display: "flex", alignItems: "center" }}>
                    <DateRangeIcon sx={{ mr: 1 }} />
                    <Typography variant="body2" color="text.secondary">
                        更新日時: {formatDateTimeJa(updatedAt)}
                    </Typography>
                </Box>
            </CardContent>
        </Card>
    );
};
