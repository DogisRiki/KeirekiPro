import { Headline } from "@/components/ui";
import { BackupContainer } from "@/features/resume";
import { Box } from "@mui/material";

/**
 * バックアップ画面
 */
export const Backup = () => {
    return (
        <Box sx={{ maxWidth: 600, mx: "auto", py: 4 }}>
            <Headline text={"バックアップ"} />
            <Box sx={{ mt: 4 }}>
                <BackupContainer />
            </Box>
        </Box>
    );
};
