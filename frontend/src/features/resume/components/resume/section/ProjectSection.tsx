import { Autocomplete, Checkbox, DatePicker, Select, TextField } from "@/components/ui";
import type { Process } from "@/features/resume";
import { processList, TechStackFieldList, useResumeStore } from "@/features/resume";
import { stringListToBulletList } from "@/utils";
import type { SelectChangeEvent } from "@mui/material";
import { Box, FormControl, FormControlLabel, FormHelperText, InputLabel, ListItemText, MenuItem } from "@mui/material";
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
 * 新規作成時のデフォルト名
 */
const DEFAULT_NAME = "新しいプロジェクト";

/**
 * プロジェクトセクション
 */
export const ProjectSection = () => {
    // ストアから必要な状態を取得
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateEntry = useResumeStore((state) => state.updateEntry);
    const getEntryErrors = useResumeStore((state) => state.getEntryErrors);

    // 職歴から会社名プルダウンデータを取得
    const companyNameOptions = resume?.careers?.map((c) => c.companyName) ?? [];

    // 現在アクティブなエントリー
    const currentProject = resume?.projects?.find((p) => p.id === activeEntryId) ?? null;

    // エントリーが選択されていない場合
    if (!currentProject) {
        return <Box sx={{ p: 2, color: "text.secondary" }}>左のリストからプロジェクトを選択してください。</Box>;
    }

    // 現在のエントリーのエラーを取得
    const errors = getEntryErrors(currentProject.id);

    // 作業工程チェックボックス: チェック状態を算出
    const selectedProcesses = Object.entries(processList)
        .filter(([key]) => currentProject.process[key as keyof Process])
        .map(([, label]) => label);

    // 会社名ハンドラー
    const handleCompanyNameChange = (_: React.SyntheticEvent, newValue: string | string[] | null) => {
        const value = Array.isArray(newValue) ? (newValue[0] ?? "") : (newValue ?? "");
        updateEntry("projects", currentProject.id, { companyName: value });
    };

    // 会社名入力ハンドラー（値が変更された場合のみ更新）
    const handleCompanyNameInputChange = (_: React.SyntheticEvent, newInputValue: string) => {
        if (newInputValue !== currentProject.companyName) {
            updateEntry("projects", currentProject.id, { companyName: newInputValue });
        }
    };

    // 開始年月ハンドラー
    const handleStartDateChange = (newValue: Dayjs | null) => {
        updateEntry("projects", currentProject.id, { startDate: newValue ? newValue.format("YYYY-MM") : "" });
    };

    // 終了年月ハンドラー
    const handleEndDateChange = (newValue: Dayjs | null) => {
        if (!currentProject.active) {
            updateEntry("projects", currentProject.id, { endDate: newValue ? newValue.format("YYYY-MM") : null });
        }
    };

    // 担当中チェックボックスハンドラー
    const handleIsActiveChange = () => {
        const newActive = !currentProject.active;
        updateEntry("projects", currentProject.id, {
            active: newActive,
            endDate: newActive ? null : currentProject.endDate,
        });
    };

    // 作業工程チェックボックスハンドラー
    const handleProcessChange = (event: SelectChangeEvent<string[]>) => {
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

    /**
     * フォーカス時にデフォルト名をクリア
     */
    const handleNameFocus = () => {
        // デフォルト名または「（コピー）」で終わる名前の場合はクリア
        if (currentProject.name === DEFAULT_NAME || currentProject.name.endsWith("（コピー）")) {
            updateEntry("projects", currentProject.id, { name: "" });
        }
    };

    // 作業工程関連のエラーキーを判定
    const hasProcessError =
        !!errors.requirements?.length ||
        !!errors.basicDesign?.length ||
        !!errors.detailedDesign?.length ||
        !!errors.implementation?.length ||
        !!errors.integrationTest?.length ||
        !!errors.systemTest?.length ||
        !!errors.maintenance?.length;

    const slotProps = { inputLabel: { shrink: true }, formHelperText: { sx: { whiteSpace: "pre-line" } } };

    return (
        <>
            {/* 会社名 */}
            <Autocomplete
                freeSolo
                options={companyNameOptions}
                value={currentProject.companyName}
                onChange={handleCompanyNameChange}
                onInputChange={handleCompanyNameInputChange}
                renderInput={(params) => (
                    <TextField
                        {...params}
                        label="会社名"
                        required
                        placeholder="（例）株式会社ABC"
                        error={!!errors.companyName?.length}
                        helperText={stringListToBulletList(errors.companyName)}
                        slotProps={slotProps}
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
                        error: !!errors.startDate?.length,
                        helperText: stringListToBulletList(errors.startDate),
                        FormHelperTextProps: { sx: { whiteSpace: "pre-line" } },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
            {/* 担当中チェックボックス */}
            <Box sx={{ display: "flex", justifyContent: "flex-end" }}>
                <FormControlLabel
                    control={<Checkbox checked={currentProject.active} onChange={handleIsActiveChange} />}
                    label="現在も担当中"
                    sx={{ color: "text.secondary", m: 0 }}
                />
            </Box>
            {/* 終了年月 */}
            <DatePicker
                label="プロジェクト終了年月"
                format="YYYY/MM"
                value={currentProject.endDate ? dayjs(currentProject.endDate, "YYYY-MM") : null}
                onChange={handleEndDateChange}
                disabled={currentProject.active}
                views={["year", "month"]}
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: !currentProject.active,
                        sx: { mb: 4 },
                        InputLabelProps: { shrink: true },
                        error: !!errors.endDate?.length,
                        helperText: stringListToBulletList(errors.endDate),
                        FormHelperTextProps: { sx: { whiteSpace: "pre-line" } },
                    },
                    calendarHeader: { format: "YYYY/MM" },
                }}
            />
            {/* プロジェクト名 */}
            <TextField
                label="プロジェクト名"
                fullWidth
                required
                placeholder="ECサイトのマイクロサービス化プロジェクト"
                value={currentProject.name}
                onChange={(e) => updateEntry("projects", currentProject.id, { name: e.target.value })}
                onFocus={handleNameFocus}
                error={!!errors.name?.length}
                helperText={stringListToBulletList(errors.name)}
                slotProps={slotProps}
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
                onChange={(e) => updateEntry("projects", currentProject.id, { overview: e.target.value })}
                error={!!errors.overview?.length}
                helperText={stringListToBulletList(errors.overview)}
                slotProps={slotProps}
                sx={{ mb: 4 }}
            />
            {/* チーム構成 */}
            <TextField
                label="チーム構成"
                fullWidth
                required
                placeholder="8名（エンジニア6名、デザイナー1名、プロダクトマネージャー1名）"
                value={currentProject.teamComp}
                onChange={(e) => updateEntry("projects", currentProject.id, { teamComp: e.target.value })}
                error={!!errors.teamComp?.length}
                helperText={stringListToBulletList(errors.teamComp)}
                slotProps={slotProps}
                sx={{ mb: 4 }}
            />
            {/* 役割 */}
            <TextField
                label="役割"
                fullWidth
                required
                placeholder="テックリード（設計、実装、レビュー、技術選定を担当）"
                value={currentProject.role}
                onChange={(e) => updateEntry("projects", currentProject.id, { role: e.target.value })}
                error={!!errors.role?.length}
                helperText={stringListToBulletList(errors.role)}
                slotProps={slotProps}
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
                onChange={(e) => updateEntry("projects", currentProject.id, { achievement: e.target.value })}
                error={!!errors.achievement?.length}
                helperText={stringListToBulletList(errors.achievement)}
                slotProps={slotProps}
                sx={{ mb: 4 }}
            />
            {/* 作業工程 */}
            <FormControl fullWidth required variant="outlined" sx={{ mb: 4 }} error={hasProcessError}>
                <InputLabel shrink>作業工程</InputLabel>
                <Select
                    multiple
                    value={selectedProcesses}
                    onChange={handleProcessChange}
                    renderValue={(selected) => selected.join("、")}
                    MenuProps={MenuProps}
                    label="作業工程"
                    notched
                    error={hasProcessError}
                >
                    {Object.entries(processList).map(([key, label]) => (
                        <MenuItem key={key} value={label}>
                            <Checkbox checked={selectedProcesses.includes(label)} />
                            <ListItemText primary={label} />
                        </MenuItem>
                    ))}
                </Select>
                {hasProcessError && (
                    <FormHelperText sx={{ whiteSpace: "pre-line" }}>
                        {stringListToBulletList(
                            [
                                ...(errors.requirements ?? []),
                                ...(errors.basicDesign ?? []),
                                ...(errors.detailedDesign ?? []),
                                ...(errors.implementation ?? []),
                                ...(errors.integrationTest ?? []),
                                ...(errors.systemTest ?? []),
                                ...(errors.maintenance ?? []),
                            ].filter((v, i, a) => a.indexOf(v) === i),
                        )}
                    </FormHelperText>
                )}
            </FormControl>
            {/* 技術スタック */}
            <TechStackFieldList />
        </>
    );
};
