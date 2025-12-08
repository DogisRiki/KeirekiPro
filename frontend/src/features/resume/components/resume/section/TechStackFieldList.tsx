import type { TechStack } from "@/features/resume";
import { TechStackField, techStackInfo, useTechStackList } from "@/features/resume";
import { getNestedValue, setNestedValue } from "@/utils";
import { ExpandMore as ExpandMoreIcon } from "@mui/icons-material";
import type { SxProps, Theme } from "@mui/material";
import { Accordion, AccordionDetails, AccordionSummary, Typography } from "@mui/material";
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

/**
 * 技術スタックフィールド一覧
 */
export const TechStackFieldList = () => {
    const [techStack, setTechStack] = useState<TechStack>({
        frontend: {
            languages: [],
            frameworks: [],
            libraries: [],
            buildTools: [],
            packageManagers: [],
            linters: [],
            formatters: [],
            testingTools: [],
        },
        backend: {
            languages: [],
            frameworks: [],
            libraries: [],
            buildTools: [],
            packageManagers: [],
            linters: [],
            formatters: [],
            testingTools: [],
            ormTools: [],
            auth: [],
        },
        infrastructure: {
            clouds: [],
            operatingSystems: [],
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
            editors: [],
            developmentEnvironments: [],
        },
    });

    const { data } = useTechStackList();

    /**
     * 値の更新ハンドラ
     */
    const handleTechStackChange = (path: readonly string[], newValue: string[]) => {
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
                            <TechStackField
                                key={field.label}
                                label={field.label}
                                value={getNestedValue<TechStack, string[]>(techStack, field.path)}
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
