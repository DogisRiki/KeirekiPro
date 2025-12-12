import { Autocomplete, Checkbox, DatePicker, Select, TextField } from "@/components/ui";
import type { Process } from "@/features/resume";
import { processList, TechStackFieldList, useResumeStore } from "@/features/resume";
import type { SelectChangeEvent } from "@mui/material";
import { Box, FormControl, FormControlLabel, InputLabel, ListItemText, MenuItem } from "@mui/material";
import type { Dayjs } from "dayjs";
import dayjs from "dayjs";

const MenuProps = {
    PaperProps: {
        style: {
            maxHeight: 48 * 4.5 + 8,
            width: 250,
        },
    },
};

/**
 * プロジェクトセクション
 */
export const ProjectSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);

    // 職歴から会社名リストを取得
    const companyNameOptions = resume?.careers?.map((c) => c.companyName) ?? [];

    // 現在アクティブなプロジェクトエントリー
    const currentProject = resume?.projects?.find((project) => project.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentProject) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストからプロジェクトを選択してください。</Box>;
    }

    // 作業工程チェックボックス: チェック状態を算出
    const selectedProcesses = Object.entries(processList)
        .filter(([key]) => currentProject.process[key as keyof Process])
        .map(([, label]) => label);

    // 会社名ハンドラー
    const handleCompanyNameChange = (_event: React.SyntheticEvent, newValue: string | string[] | null) => {
        if (!currentProject) return;
        const value = Array.isArray(newValue) ? newValue[0] ?? "" : newValue ?? "";
        updateEntry("projects", currentProject.id, {
            companyName: value,
        });
    };

    // 開始年月ハンドラー
    const handleStartDateChange = (newValue: Dayjs | null) => {
        if (!currentProject) return;
        updateEntry("projects", currentProject.id, {
            startDate: newValue ? newValue.format("YYYY-MM") : "",
        });
    };

    // 終了年月ハンドラー
    const handleEndDateChange = (newValue: Dayjs | null) => {
        if (!currentProject || currentProject.active) return;
        updateEntry("projects", currentProject.id, {
            endDate: newValue ? newValue.format("YYYY-MM") : null,
        });
    };

    // 担当中チェックボックスハンドラー
    const handleIsActiveChange = () => {
        if (!currentProject) return;
        const newActive = !currentProject.active;
        updateEntry("projects", currentProject.id, {
            active: newActive,
            endDate: newActive ? null : currentProject.endDate,
        });
    };

    // 作業工程チェックボックスハンドラー
    const handleProcessChange = (event: SelectChangeEvent<string[]>) => {
        if (!currentProject) return;
        const value = event.target.value;
        const selectedValues = typeof value === "string" ? value.split(",") : value;

        const newProcess: Process = {
            requirements: false,
            basicDesign: false,
            detailedDesign: false,
            implementation: false,
            integrationTest: false,
            systemTest: false,
            maintenance: false,
        };
        Object.entries(processList).forEach(([key, label]) => {
            newProcess[key as keyof Process] = selectedValues.includes(label);
        });

        updateEntry("projects", currentProject.id, { process: newProcess });
    };

    return (
        <>
            {/* 会社名 */}
            <Autocomplete
                freeSolo
                options={companyNameOptions}
                value={currentProject.companyName}
                onChange={handleCompanyNameChange}
                onInputChange={(_event, newInputValue) => {
                    if (!currentProject) return;
                    updateEntry("projects", currentProject.id, {
                        companyName: newInputValue,
                    });
                }}
                renderInput={(params) => (
                    <TextField
                        {...params}
                        label="会社名"
                        required
                        placeholder="（例）株式会社ABC"
                        slotProps={{
                            inputLabel: { shrink: true },
                        }}
                    />
                )}
                sx={{ mb: 4 }}
            />
            {/* 開始年月 */}
            <DatePicker
                label="プロジェクト開始年月"
                value={currentProject.startDate ? dayjs(currentProject.startDate, "YYYY-MM") : null}
                onChange={handleStartDateChange}
                views={["year", "month"]}
                format="YYYY/MM"
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: true,
                        sx: { mb: 2 },
                        InputLabelProps: { shrink: true },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
            {/* 担当中チェックボックス */}
            <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                <FormControlLabel
                    control={<Checkbox checked={currentProject.active} onChange={handleIsActiveChange} />}
                    label="現在も担当中"
                    sx={{
                        color: "text.secondary",
                        m: 0,
                    }}
                />
            </Box>
            {/* 終了年月 */}
            <DatePicker
                label="プロジェクト終了年月"
                format="YYYY/MM"
                value={currentProject.endDate ? dayjs(currentProject.endDate, "YYYY-MM") : null}
                onChange={handleEndDateChange}
                disabled={currentProject.active}
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: !currentProject.active,
                        sx: { mb: 4 },
                        InputLabelProps: { shrink: true },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
                views={["year", "month"]}
            />
            {/* プロジェクト名 */}
            <TextField
                label="プロジェクト名"
                fullWidth
                required
                placeholder="ECサイトのマイクロサービス化プロジェクト"
                value={currentProject.name}
                onChange={(e) => {
                    updateEntry("projects", currentProject.id, { name: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* プロジェクト概要 */}
            <TextField
                label="プロジェクト概要"
                fullWidth
                required
                multiline
                minRows={4}
                placeholder="導入実績25万店舗の大規模ECプラットフォームのマイクロサービス化プロジェクト"
                value={currentProject.overview}
                onChange={(e) => {
                    updateEntry("projects", currentProject.id, { overview: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* チーム構成 */}
            <TextField
                label="チーム構成"
                fullWidth
                required
                placeholder="8名（エンジニア6名、デザイナー1名、プロダクトマネージャー1名）"
                value={currentProject.teamComp}
                onChange={(e) => {
                    updateEntry("projects", currentProject.id, { teamComp: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 役割 */}
            <TextField
                label="役割"
                fullWidth
                required
                placeholder="テックリード（設計、実装、レビュー、技術選定を担当）"
                value={currentProject.role}
                onChange={(e) => {
                    updateEntry("projects", currentProject.id, { role: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 成果 */}
            <TextField
                label="主な成果"
                fullWidth
                required
                multiline
                minRows={10}
                placeholder={[
                    "・デプロイ頻度を週1回から1日3回に改善",
                    "・本番環境での重大インシデントを月平均5件から1件未満に削減",
                    "・新機能のリリースサイクルを2週間から3日に短縮",
                    "・マイクロサービスのリファレンスアーキテクチャを確立し、新規サービス作成時間を70%短縮",
                ].join("\n")}
                value={currentProject.achievement}
                onChange={(e) => {
                    updateEntry("projects", currentProject.id, { achievement: e.target.value });
                }}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
                sx={{ mb: 4 }}
            />
            {/* 作業工程 */}
            <FormControl fullWidth required variant="outlined" sx={{ mb: 4 }}>
                <InputLabel shrink>作業工程</InputLabel>
                <Select
                    multiple
                    value={selectedProcesses}
                    onChange={handleProcessChange}
                    renderValue={(selected) => selected.join("、")}
                    MenuProps={MenuProps}
                    label="作業工程"
                    notched
                >
                    {Object.entries(processList).map(([key, label]) => (
                        <MenuItem key={key} value={label}>
                            <Checkbox checked={selectedProcesses.includes(label)} />
                            <ListItemText primary={label} />
                        </MenuItem>
                    ))}
                </Select>
            </FormControl>
            {/* 技術スタック */}
            <TechStackFieldList />
        </>
    );
};
