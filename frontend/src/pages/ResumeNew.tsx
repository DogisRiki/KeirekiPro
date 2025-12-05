import { Headline } from "@/components/ui";
import { CreateResumeContainer } from "@/features/resume";
import { Box, Typography } from "@mui/material";

/**
 * 職務経歴書新規作成画面
 */
export const ResumeNew = () => {
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            <Headline text={"職務経歴書の新規作成"} />
            <Typography variant="body1" gutterBottom sx={{ my: 4 }}>
                職務経歴書名を入力して新規作成するか、既存の職務経歴書をコピーして作成できます。
            </Typography>
            <CreateResumeContainer />
        </Box>
    );
};
