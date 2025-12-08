import type { TechStack } from "@/features/resume";
import { TechStackField, techStackInfo, useResumeStore, useTechStackList } from "@/features/resume";
import { getNestedValue, setNestedValue } from "@/utils";
import { ExpandMore as ExpandMoreIcon } from "@mui/icons-material";
import type { SxProps, Theme } from "@mui/material";
import { Accordion, AccordionDetails, AccordionSummary, Typography } from "@mui/material";

/**
 * 共通のアコーディオンスタイル
 */
const accordionStyles: SxProps<Theme> = {
    mb: 2,
    boxShadow: "none",
    "&:before": {
        display: "none",
    },
    "& .MuiAccordionSummary-root": {
        borderBottom: "1px solid",
        borderColor: "divider",
        minHeight: 48,
        "&.Mui-expanded": {
            minHeight: 48,
        },
    },
    "& .MuiAccordionSummary-content": {
        m: 0,
        "&.Mui-expanded": {
            m: 0,
        },
    },
    "& .MuiAccordionDetails-root": {
        p: 3,
    },
};

/**
 * 技術スタックフィールド一覧
 */
export const TechStackFieldList = () => {
    // ストアから現在のプロジェクトを取得
    const { resume, activeEntryId, updateEntry } = useResumeStore();
    const currentProject = resume?.projects.find((project) => project.id === activeEntryId) ?? null;
    const currentTechStack: TechStack | null = currentProject?.techStack ?? null;

    // マスタデータを取得
    const { data } = useTechStackList();

    /**
     * 値の更新ハンドラ
     * - currentProject が存在しない場合は何もしない
     * - currentTechStack をベースに、指定パスの配列を更新してストアに反映
     */
    const handleTechStackChange = (path: readonly string[], newValue: string[]) => {
        if (!currentProject || !currentTechStack) {
            return;
        }

        const nextTechStack: TechStack = {
            frontend: { ...currentTechStack.frontend },
            backend: { ...currentTechStack.backend },
            infrastructure: { ...currentTechStack.infrastructure },
            tools: { ...currentTechStack.tools },
        };

        const updated = setNestedValue(nextTechStack, path, newValue) as TechStack;

        updateEntry("projects", currentProject.id, {
            techStack: updated,
        });
    };

    return (
        <>
            {techStackInfo.map((section) => (
                <Accordion key={section.title} sx={accordionStyles}>
                    <AccordionSummary expandIcon={<ExpandMoreIcon />} sx={{ px: 2 }}>
                        <Typography
                            component="span"
                            sx={{
                                fontSize: "0.875rem",
                                fontWeight: 500,
                            }}
                        >
                            {section.title}
                        </Typography>
                    </AccordionSummary>
                    <AccordionDetails>
                        {section.fields.map((field, index) => (
                            <TechStackField
                                key={field.label}
                                label={field.label}
                                // プロジェクト側の値（未選択 or プロジェクト未選択時は空配列）
                                value={
                                    currentTechStack
                                        ? getNestedValue<TechStack, string[]>(currentTechStack, field.path)
                                        : []
                                }
                                // マスタ未取得（初期ロード中など）の場合は空配列
                                options={data ? getNestedValue<TechStack, string[]>(data, field.path) : []}
                                onChange={(newValue) => handleTechStackChange(field.path, newValue)}
                                isLast={index === section.fields.length - 1}
                            />
                        ))}
                    </AccordionDetails>
                </Accordion>
            ))}
        </>
    );
};
