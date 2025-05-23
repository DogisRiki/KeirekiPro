import { Link } from "@/components/ui";
import CancelIcon from "@mui/icons-material/Cancel";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import { Box, Typography } from "@mui/material";

export interface PasswordStatusBoxProps {
    // 設定状態ラベル
    statusLabel: string;
    // ナビゲーションメッセージ
    navigationMessage: string;
    // 警告フラグ
    isWarning: boolean;
    // 遷移先パス
    linkPath: string;
}

/**
 * パスワードとメールアドレスの設定状況を示すステータスボックス
 */
export const PasswordStatusBox = ({ statusLabel, navigationMessage, isWarning, linkPath }: PasswordStatusBoxProps) => {
    // 「こちら」で分割してリンク挿入
    const [prefix, suffix] = navigationMessage.split("こちら");

    return (
        <Box
            sx={{
                display: "flex",
                alignItems: "center",
                gap: 2,
                p: 2,
                mb: 4,
                bgcolor: "grey.50",
                border: 1,
                borderRadius: 1,
                borderColor: isWarning ? "error.light" : "success.light",
            }}
        >
            <Box sx={{ display: "flex", alignItems: "center", flex: 1 }}>
                {isWarning ? (
                    <CancelIcon sx={{ mr: 1.5, color: "error.light", fontSize: 20 }} />
                ) : (
                    <CheckCircleIcon sx={{ mr: 1.5, color: "success.light", fontSize: 20 }} />
                )}
                <Box>
                    <Typography variant="body1" sx={{ fontWeight: 500, mb: 0.5, color: "text.primary" }}>
                        {statusLabel}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                        {prefix}
                        <Link to={linkPath} variant="body2">
                            こちら
                        </Link>
                        {suffix}
                    </Typography>
                </Box>
            </Box>
        </Box>
    );
};
