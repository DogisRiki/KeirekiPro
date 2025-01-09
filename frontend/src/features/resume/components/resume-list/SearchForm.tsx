import { Button, TextField } from "@/components/ui";
import { Sort as SortIcon } from "@mui/icons-material";
import { Box, Menu, MenuItem } from "@mui/material";
import React, { useState } from "react";

interface SearchFormProps {
    searchWord: string;
    setSearchWord: React.Dispatch<React.SetStateAction<string>>;
    sortType: "name" | "date";
    setSortType: React.Dispatch<React.SetStateAction<"name" | "date">>;
}

/**
 * 職務経歴書検索フォーム
 */
export const SearchForm = ({ searchWord, setSearchWord, sortType, setSortType }: SearchFormProps) => {
    // ソートメニューの表示位置を制御するアンカー要素
    const [sortAnchorEl, setSortAnchorEl] = useState<HTMLElement | null>(null);

    /**
     * ソートボタンクリック時のハンドラー
     */
    const handleSortClick = (event: React.MouseEvent<HTMLElement>) => setSortAnchorEl(event.currentTarget);

    /**
     * ソートメニュー選択時のハンドラー
     */
    const handleSortClose = (type: "name" | "date") => {
        setSortAnchorEl(null);
        if (type) {
            setSortType(type);
        }
    };

    /**
     * 検索ボックス入力時のハンドラー
     */
    const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => setSearchWord(event.target.value);

    return (
        <Box
            sx={{
                display: "flex",
                justifyContent: "center",
                gap: 2,
                width: "100%",
                maxWidth: "800px",
                margin: "0 auto",
            }}
        >
            {/* 検索ボックス */}
            <TextField
                placeholder="職務経歴書名で検索..."
                size="small"
                sx={{ flex: 1 }}
                value={searchWord}
                onChange={handleChange}
            />
            {/* ソートボタン */}
            <Button
                startIcon={<SortIcon />}
                onClick={handleSortClick}
                size="small"
                sx={{
                    minWidth: "100px",
                    width: "auto",
                }}
            >
                {sortType === "name" ? "名前順" : "作成日順"}
            </Button>
            {/* ソートメニュー */}
            <Menu anchorEl={sortAnchorEl} open={Boolean(sortAnchorEl)} onClose={handleSortClose}>
                <MenuItem onClick={() => handleSortClose("name")}>名前順</MenuItem>
                <MenuItem onClick={() => handleSortClose("date")}>作成日順</MenuItem>
            </Menu>
        </Box>
    );
};
