import BuildIcon from "@mui/icons-material/Build";
import CloudOffIcon from "@mui/icons-material/CloudOff";
import { Box, Typography } from "@mui/material";
import { useState } from "react";

import { isBusinessHours } from "@/utils";

/**
 * メンテナンス画面
 * 表示したときの時刻が営業時間なら障害の案内を、それ以外なら時間外の案内を出す。
 * 判定は表示したときに1回だけ行い、自分から別の画面へは移らない。
 */
export const Maintenance = () => {
    const [isOutage] = useState(() => isBusinessHours(new Date()));

    const Icon = isOutage ? CloudOffIcon : BuildIcon;
    const title = isOutage ? "ただいまご利用いただけません" : "メンテナンス中";
    const message = isOutage
        ? "サービスに接続できない状態です。復旧までしばらくお待ちいただき、時間をおいて再度アクセスしてください。"
        : "現在サービスは停止中です。平日 8:00〜20:00 に再度アクセスしてください。";

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                height: "100vh",
                textAlign: "center",
            }}
        >
            <Icon sx={{ fontSize: 64, color: "text.secondary", mb: 2 }} />
            <Typography variant="h4" gutterBottom>
                {title}
            </Typography>
            <Typography variant="body1" sx={{ mb: 4 }}>
                {message}
            </Typography>
        </Box>
    );
};
