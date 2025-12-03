import { techStackInfo, teckStackList } from "@/features/resume";
import { TechStackField } from "@/features/resume/components/resume/section/TechStackField";
import { TechStack } from "@/types";
import { getNestedValue, setNestedValue } from "@/utils";
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

    /**
     * 値の更新ハンドラ
     */
    const handleTeckStackChange = (path: readonly string[], newValue: string[]) => {
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
