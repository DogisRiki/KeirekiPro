import { Checkbox, DatePicker, Select, TextField } from "@/components/ui";
import { Process, processList, TechStackFieldList, useResumeStore } from "@/features/resume";
import {
    Box,
    FormControl,
    FormControlLabel,
    InputLabel,
    ListItemText,
    MenuItem,
    SelectChangeEvent,
} from "@mui/material";
import { Dayjs } from "dayjs";
import { useState } from "react";

const MenuProps = {
    PaperProps: {
        style: {
            maxHeight: 48 * 4.5 + 8,
            width: 250,
        },
    },
};

/**
 * 職務内容セクション
 */
export const ProjectSection = () => {
    // ストアから必要な状態を取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();

    // 職歴から会社情報を取得
    const companies = resume?.careers ?? [];

    // 現在アクティブなプロジェクトエントリー
    const currentProject = resume?.projects.find((project) => project.id === activeEntryId) ?? null;

    // 会社名（選択用）
    const [companyName, setCompanyName] = useState<string>("");

    // 開始年月
    const [startDate, setStartDate] = useState<Dayjs | null>(null);

    // 終了年月
    const [endDate, setEndDate] = useState<Dayjs | null>(null);

    // 担当中チェックボックス
    const [isAssigned, setIsAssigned] = useState(false);

    // 作業工程チェックボックス
    const [process, setProcess] = useState<Process>({
        requirements: false,
        basicDesign: false,
        detailedDesign: false,
        implementation: false,
        integrationTest: false,
        systemTest: false,
        maintenance: false,
    });

    // 作業工程チェックボックス: チェック状態
    const [selectedProcesses, setSelectedProcesses] = useState<string[]>([]);

    // 会社名ハンドラー
    const handleCompanyNameChange = (event: SelectChangeEvent<string>) => {
        setCompanyName(event.target.value);
    };

    // 入社年月ハンドラー
    const handleStartDateChange = (newValue: Dayjs | null) => {
        setStartDate(newValue);
    };

    // 退職年月ハンドラー
    const handleEndDateChange = (newValue: Dayjs | null) => {
        if (!isAssigned) {
            setEndDate(newValue);
        }
    };

    // 担当中チェックボックスハンドラー
    const handleIsAssignedChange = () => {
        setIsAssigned((prev) => !prev);
        if (!isAssigned) {
            setEndDate(null);
        }
    };

    // 作業工程チェックボックスハンドラー
    const handleProcessChange = (event: SelectChangeEvent<string[]>) => {
        const value = event.target.value;
        const selectedValues = typeof value === "string" ? value.split(",") : value;
        setSelectedProcesses(selectedValues);

        // Process オブジェクトも更新
        const newProcess = { ...process };
        Object.entries(processList).forEach(([key, label]) => {
            newProcess[key as keyof Process] = selectedValues.includes(label);
        });
        setProcess(newProcess);
    };

    return (
        <>
            {/* 会社名 */}
            <FormControl fullWidth required variant="outlined" sx={{ mb: 4 }}>
                <InputLabel shrink>会社名</InputLabel>
                <Select value={companyName} onChange={handleCompanyNameChange} label="会社名" notched>
                    {companies.length === 0 ? (
                        <MenuItem disabled>職歴が存在しません</MenuItem>
                    ) : (
                        companies.map((company) => (
                            <MenuItem key={company.id} value={company.id}>
                                {company.companyName}
                            </MenuItem>
                        ))
                    )}
                </Select>
            </FormControl>
            {/* 開始年月 */}
            <DatePicker
                label="プロジェクト開始年月"
                value={startDate}
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
                    control={<Checkbox />}
                    label="現在も担当中"
                    checked={isAssigned}
                    onChange={handleIsAssignedChange}
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
                value={endDate}
                onChange={handleEndDateChange}
                disabled={isAssigned}
                slotProps={{
                    textField: {
                        fullWidth: true,
                        required: !isAssigned,
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
                value={currentProject?.name ?? ""}
                onChange={(e) => {
                    if (!currentProject) return;
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
