import { Switch } from "@/components/ui";
import { useThemeStore } from "@/stores";
import DarkModeIcon from "@mui/icons-material/DarkMode";
import LightModeIcon from "@mui/icons-material/LightMode";
import { Box } from "@mui/material";

/**
 * テーマ変更スイッチ
 */
export const ThemeSwitch = () => {
    const mode = useThemeStore((state) => state.mode);
    const toggleMode = useThemeStore((state) => state.toggleMode);

    return (
        <Box sx={{ display: "flex", alignItems: "center" }}>
            <LightModeIcon sx={{ color: "primary.contrastText", fontSize: 20 }} />
            <Switch
                checked={mode === "dark"}
                onChange={toggleMode}
                size="small"
                sx={{
                    mx: 0.5,
                    "& .MuiSwitch-switchBase.Mui-checked": {
                        color: "primary.contrastText",
                    },
                    "& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track": {
                        backgroundColor: "primary.contrastText",
                    },
                }}
            />
            <DarkModeIcon sx={{ color: "primary.contrastText", fontSize: 20 }} />
        </Box>
    );
};
