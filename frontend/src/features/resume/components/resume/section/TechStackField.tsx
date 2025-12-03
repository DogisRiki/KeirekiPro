// src/features/resume/components/resume/section/TechStackField.tsx
import { Autocomplete, TextField } from "@/components/ui";
import { dedupeIgnoreCase, normalizeForCaseInsensitiveCompare } from "@/utils";
import React, { useState } from "react";

interface TechStackFieldProps {
    label: string;
    value: string[] | null;
    options: string[];
    onChange: (newValue: string[]) => void;
    isLast?: boolean;
}

/**
 * 技術スタック単一フィールド
 */
export const TechStackField = ({ label, value, options, onChange, isLast = false }: TechStackFieldProps) => {
    const [inputValue, setInputValue] = useState("");
    const [errorMessage, setErrorMessage] = useState<string | null>(null);
    const [duplicateLabel, setDuplicateLabel] = useState<string | null>(null);

    const currentValues = value ?? [];

    /**
     * AutocompleteのonChange用ハンドラ
     */
    const handleChange = (_event: React.SyntheticEvent, newValue: string[] | string | null) => {
        if (!Array.isArray(newValue)) {
            return;
        }
        const unique = dedupeIgnoreCase(newValue);
        onChange(unique);
    };

    /**
     * 入力値の変更ハンドラ
     */
    const handleInputChange = (_event: React.SyntheticEvent, newInputValue: string) => {
        setInputValue(newInputValue);
        // 入力が変わったタイミングでエラーはクリア
        if (errorMessage || duplicateLabel) {
            setErrorMessage(null);
            setDuplicateLabel(null);
        }
    };

    /**
     * Enterキー押下時の重複チェック
     */
    const handleKeyDown = (event: React.KeyboardEvent<HTMLElement>) => {
        if (event.key !== "Enter") {
            return;
        }

        const raw = inputValue;
        const norm = normalizeForCaseInsensitiveCompare(raw);
        if (!norm) {
            return;
        }

        const existing = currentValues.find((v) => normalizeForCaseInsensitiveCompare(v) === norm);
        if (existing) {
            // 既に同一値が存在する場合はAutocompleteの追加処理を止めてエラー表示
            event.preventDefault();
            event.stopPropagation();
            setDuplicateLabel(existing);
            setErrorMessage("はすでに同一の値が入力されています。");
        }
    };

    return (
        <Autocomplete
            multiple
            freeSolo
            options={options}
            filterSelectedOptions
            autoHighlight
            isOptionEqualToValue={(option, v) =>
                normalizeForCaseInsensitiveCompare(option) === normalizeForCaseInsensitiveCompare(v)
            }
            value={currentValues}
            onChange={handleChange}
            inputValue={inputValue}
            onInputChange={handleInputChange}
            renderInput={(params) => (
                <TextField
                    {...params}
                    label={label}
                    error={!!errorMessage}
                    helperText={
                        errorMessage && duplicateLabel ? (
                            <>
                                <span
                                    style={{
                                        color: "#d32f2f",
                                        fontWeight: 500,
                                        marginRight: 4,
                                    }}
                                >
                                    「{duplicateLabel}」
                                </span>
                                {errorMessage}
                            </>
                        ) : (
                            errorMessage ?? undefined
                        )
                    }
                    onKeyDown={(event) => {
                        const inputProps = params.inputProps as React.InputHTMLAttributes<HTMLInputElement>;
                        if (inputProps.onKeyDown) {
                            inputProps.onKeyDown(event as React.KeyboardEvent<HTMLInputElement>);
                        }
                        handleKeyDown(event);
                    }}
                    slotProps={{
                        inputLabel: { shrink: true },
                    }}
                />
            )}
            sx={!isLast ? { mb: 4 } : undefined}
        />
    );
};
