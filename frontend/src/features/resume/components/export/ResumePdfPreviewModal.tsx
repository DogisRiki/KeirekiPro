import {
    hexToRgb,
    PDF_FONT_SIZE_OPTIONS,
    rgbToHex,
    type PdfFontFamily,
    type ResumePdfSettings,
} from "@/features/resume";
import CloseIcon from "@mui/icons-material/Close";
import FileDownloadIcon from "@mui/icons-material/FileDownload";
import RefreshIcon from "@mui/icons-material/Refresh";
import {
    Autocomplete,
    Box,
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    FormControl,
    IconButton,
    InputAdornment,
    InputLabel,
    MenuItem,
    Select,
    TextField,
    Typography,
    useTheme,
} from "@mui/material";
import { useMemo, useState } from "react";
import { HexColorPicker } from "react-colorful";

interface ResumePdfPreviewModalProps {
    open: boolean;
    previewUrl: string | null;
    settings: ResumePdfSettings;
    onSettingsChange: (settings: ResumePdfSettings) => void;
    onRefresh: () => void;
    onReset: () => void;
    onExport: () => void;
    onClose: () => void;
}

/**
 * PDFフォント種別の表示名
 */
const fontFamilyLabels: Record<PdfFontFamily, string> = {
    NotoSansJP: "ゴシック系（Noto Sans JP）",
    NotoSerifJP: "明朝系（Noto Serif JP）",
};

/**
 * PDF設定入力欄の共通スタイル
 */
const fieldSx = {
    "& .MuiInputBase-root": {
        minHeight: 38,
    },
    "& .MuiInputBase-input": {
        py: 0.875,
    },
};

/**
 * PDFビューア用URLを生成する
 */
const buildPdfViewerUrl = (url: string): string => `${url}#toolbar=1&navpanes=0&zoom=100`;

/**
 * PDFプレビューモーダル
 */
export const ResumePdfPreviewModal = ({
    open,
    previewUrl,
    settings,
    onSettingsChange,
    onRefresh,
    onReset,
    onExport,
    onClose,
}: ResumePdfPreviewModalProps) => {
    const theme = useTheme();
    const hex = useMemo(
        () =>
            settings.tableHeaderColor.hex ??
            rgbToHex(
                settings.tableHeaderColor.rgb?.r ?? 217,
                settings.tableHeaderColor.rgb?.g ?? 217,
                settings.tableHeaderColor.rgb?.b ?? 217,
            ),
        [settings.tableHeaderColor.hex, settings.tableHeaderColor.rgb],
    );
    const rgb = useMemo(() => hexToRgb(hex), [hex]);
    const [hexInputState, setHexInputState] = useState({ committedHex: hex, value: hex });
    const hexInput = hexInputState.committedHex === hex ? hexInputState.value : hex;

    /**
     * PDF設定を部分更新する
     */
    const updateSettings = (next: Partial<ResumePdfSettings>) => {
        onSettingsChange({
            ...settings,
            ...next,
        });
    };

    /**
     * フォントサイズ設定を更新する
     */
    const updateFontSize = (key: keyof ResumePdfSettings["fontSizes"], value: string | number | null) => {
        if (value === null || value === "") return;
        const numeric = typeof value === "number" ? value : Number(value);
        if (!Number.isFinite(numeric)) return;
        updateSettings({
            fontSizes: {
                ...settings.fontSizes,
                [key]: numeric,
            },
        });
    };

    /**
     * カラーコード入力から表ヘッダー色を更新する
     */
    const updateHex = (value: string) => {
        const nextHex = value
            .replace("#", "")
            .replace(/[^0-9a-fA-F]/g, "")
            .slice(0, 6)
            .toLowerCase();
        setHexInputState({ committedHex: nextHex.length === 6 ? nextHex : hex, value: nextHex });
        if (nextHex.length === 6) {
            updateSettings({ tableHeaderColor: { hex: nextHex } });
        }
    };

    /**
     * RGB入力から表ヘッダー色を更新する
     */
    const updateRgb = (key: "r" | "g" | "b", value: string) => {
        const numeric = Number(value);
        if (!Number.isInteger(numeric) || numeric < 0 || numeric > 255) {
            return;
        }
        const nextRgb = { ...rgb, [key]: numeric };
        updateSettings({ tableHeaderColor: { hex: rgbToHex(nextRgb.r, nextRgb.g, nextRgb.b) } });
    };

    /**
     * フォントサイズ入力欄を描画する
     */
    const renderFontSizeField = (label: string, key: keyof ResumePdfSettings["fontSizes"]) => (
        <Autocomplete
            disableClearable
            freeSolo
            options={PDF_FONT_SIZE_OPTIONS}
            value={settings.fontSizes[key]}
            getOptionLabel={(option) => String(option)}
            onChange={(_, value) => updateFontSize(key, value)}
            size="small"
            renderInput={(params) => (
                <TextField
                    {...params}
                    label={label}
                    size="small"
                    onBlur={(event) => updateFontSize(key, event.target.value)}
                    onKeyDown={(event) => {
                        if (event.key === "Enter") {
                            updateFontSize(key, (event.target as HTMLInputElement).value);
                        }
                    }}
                    sx={fieldSx}
                />
            )}
        />
    );
    const previewViewerUrl = previewUrl ? buildPdfViewerUrl(previewUrl) : null;

    return (
        <Dialog
            open={open}
            onClose={onClose}
            fullWidth
            maxWidth={false}
            slotProps={{
                paper: {
                    sx: {
                        width: { xs: "calc(100vw - 24px)", md: "min(1480px, calc(100vw - 96px))" },
                        height: { xs: "calc(100vh - 24px)", md: "min(820px, calc(100vh - 96px))" },
                        m: { xs: 1.5, md: 6 },
                        bgcolor: theme.palette.mode === "light" ? "#EEEEEE" : "background.default",
                    },
                },
            }}
        >
            <DialogTitle
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    borderBottom: 1,
                    borderColor: "divider",
                    py: 1.25,
                }}
            >
                PDFプレビュー
                <IconButton aria-label="PDFプレビューを閉じる" onClick={onClose}>
                    <CloseIcon />
                </IconButton>
            </DialogTitle>
            <DialogContent
                sx={{
                    display: "flex",
                    flexDirection: { xs: "column", md: "row" },
                    gap: 1.5,
                    overflow: "hidden",
                    p: 1.5,
                    minHeight: 0,
                }}
            >
                <Box
                    sx={{
                        width: { xs: "100%", md: 320 },
                        minWidth: { md: 320 },
                        display: "flex",
                        flexDirection: "column",
                        gap: 1.25,
                        maxHeight: { xs: "50%", md: "none" },
                        overflowY: "auto",
                        px: 0.25,
                        pt: 1.5,
                        pb: 1.5,
                        pr: { md: 0.75 },
                    }}
                >
                    <FormControl size="small" sx={fieldSx}>
                        <InputLabel id="pdf-font-family-label">フォント</InputLabel>
                        <Select
                            labelId="pdf-font-family-label"
                            label="フォント"
                            value={settings.fontFamily}
                            onChange={(event) =>
                                updateSettings({ fontFamily: event.target.value as ResumePdfSettings["fontFamily"] })
                            }
                        >
                            {(Object.keys(fontFamilyLabels) as PdfFontFamily[]).map((fontFamily) => (
                                <MenuItem key={fontFamily} value={fontFamily}>
                                    {fontFamilyLabels[fontFamily]}
                                </MenuItem>
                            ))}
                        </Select>
                    </FormControl>

                    {renderFontSizeField("タイトルフォントサイズ", "title")}
                    {renderFontSizeField("日付フォントサイズ", "date")}
                    {renderFontSizeField("氏名フォントサイズ", "fullName")}
                    {renderFontSizeField("セクション見出しフォントサイズ", "sectionHeading")}

                    <Typography variant="subtitle2" sx={{ mt: 0.25 }}>
                        表ヘッダー色
                    </Typography>
                    <Box
                        sx={{
                            px: 1.5,
                            py: 0.25,
                            "& .react-colorful": {
                                width: "100%",
                                height: 155,
                            },
                        }}
                    >
                        <HexColorPicker color={`#${hex}`} onChange={(value) => updateHex(value)} />
                    </Box>
                    <TextField
                        label="カラーコード"
                        size="small"
                        value={hexInput}
                        onChange={(event) => updateHex(event.target.value)}
                        sx={fieldSx}
                        slotProps={{
                            input: {
                                startAdornment: (
                                    <InputAdornment position="start" sx={{ opacity: 0.5 }}>
                                        #
                                    </InputAdornment>
                                ),
                            },
                        }}
                    />
                    <Box sx={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 1 }}>
                        {(["r", "g", "b"] as const).map((key) => (
                            <TextField
                                key={key}
                                label={key.toUpperCase()}
                                size="small"
                                type="number"
                                value={rgb[key]}
                                onChange={(event) => updateRgb(key, event.target.value)}
                                sx={fieldSx}
                                slotProps={{
                                    htmlInput: {
                                        min: 0,
                                        max: 255,
                                    },
                                }}
                            />
                        ))}
                    </Box>
                    <Button variant="outlined" startIcon={<RefreshIcon />} onClick={onRefresh}>
                        プレビュー更新
                    </Button>
                    <Button variant="outlined" onClick={onReset}>
                        設定値リセット
                    </Button>
                </Box>

                <Box
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        minHeight: { xs: 320, md: 0 },
                        display: "block",
                        bgcolor: "#2b2b2b",
                    }}
                >
                    {previewViewerUrl && (
                        <Box
                            component="iframe"
                            title="PDFプレビュー"
                            src={previewViewerUrl}
                            sx={{ width: "100%", height: "100%", border: 0, display: "block" }}
                        />
                    )}
                </Box>
            </DialogContent>
            <DialogActions sx={{ borderTop: 1, borderColor: "divider", gap: 1, px: 1.5, py: 1 }}>
                <Button variant="contained" color="primary" onClick={onClose}>
                    とじる
                </Button>
                <Button variant="contained" color="primary" startIcon={<FileDownloadIcon />} onClick={onExport}>
                    エクスポート
                </Button>
            </DialogActions>
        </Dialog>
    );
};
