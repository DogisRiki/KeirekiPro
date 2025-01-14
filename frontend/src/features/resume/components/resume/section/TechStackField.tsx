import { Autocomplete, TextField } from "@/components/ui";
import { techStackInfo, teckStackList } from "@/features/resume";
import { TechStack } from "@/types";
import { getNestedValue, setNestedValue } from "@/utils/objectUtils";
import { ExpandMore as ExpandMoreIcon } from "@mui/icons-material";
import { Accordion, AccordionDetails, AccordionSummary, SxProps, Theme, Typography } from "@mui/material";
import { useState } from "react";

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

interface TechFieldProps {
    label: string;
    value: string[] | null;
    options: string[];
    onChange: (newValue: string[]) => void;
    isLast?: boolean;
}

const TechField = ({ label, value, options, onChange, isLast = false }: TechFieldProps) => (
    <Autocomplete
        multiple
        options={options}
        freeSolo
        value={value ?? []}
        onChange={(_, value) => {
            // 型が配列であることを保証
            if (Array.isArray(value)) {
                onChange(value);
            }
        }}
        renderInput={(params) => (
            <TextField
                {...params}
                label={label}
                slotProps={{
                    inputLabel: { shrink: true },
                }}
            />
        )}
        sx={!isLast ? { mb: 4 } : undefined}
    />
);

/**
 * 技術スタックフィールド
 */
export const TechStackField = () => {
    // 技術スタック
    const [techStack, setTechStack] = useState<TechStack>({
        languages: [],
        dependencies: {
            frameworks: [],
            libraries: [],
            testingTools: [],
            ormTools: [],
            packageManagers: [],
        },
        infrastructure: {
            clouds: [],
            containers: [],
            databases: [],
            webServers: [],
            ciCdTools: [],
            iacTools: [],
            monitoringTools: [],
            loggingTools: [],
        },
        tools: {
            sourceControls: [],
            projectManagements: [],
            communicationTools: [],
            documentationTools: [],
            apiDevelopmentTools: [],
            designTools: [],
        },
        others: [],
    });

    // 値の更新ハンドラー
    const handleTeckStackChange = (path: string[], newValue: string[]) => {
        setTechStack((prev) => {
            const newTechStack = { ...prev };
            return setNestedValue(newTechStack, path, newValue);
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
                            <TechField
                                key={field.label}
                                label={field.label}
                                value={getNestedValue<TechStack, string[]>(techStack, field.path)}
                                options={getNestedValue<TechStack, string[]>(teckStackList, field.path)}
                                onChange={(newValue) => handleTeckStackChange(field.path, newValue)}
                                isLast={index === section.fields.length - 1}
                            />
                        ))}
                    </AccordionDetails>
                </Accordion>
            ))}
        </>
    );
};
