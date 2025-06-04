import { Switch } from "@/components/ui";
import { Box, FormControlLabel, Typography } from "@mui/material";

export interface TwoFactorSwitchProps {
    enabled: boolean;
    disabled?: boolean;
    onToggle: (next: boolean) => void;
}

/**
 * 二段階認証ON/OFFスイッチ
 */
export const TwoFactorSwitch = ({ enabled, disabled = false, onToggle }: TwoFactorSwitchProps) => (
    <FormControlLabel
        control={
            <Switch
                color="primary"
                checked={enabled}
                disabled={disabled}
                onChange={(_, checked) => onToggle(checked)}
            />
        }
        label={
            <Box>
                <Typography variant="subtitle1">二段階認証</Typography>
                <Typography variant="body2" color="text.secondary">
                    アカウントのセキュリティを強化します
                </Typography>
            </Box>
        }
    />
);
