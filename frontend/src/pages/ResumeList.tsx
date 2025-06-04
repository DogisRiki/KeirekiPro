import { NoData } from "@/components/errors";
import { Button } from "@/components/ui";
import { ResumeCard, SearchForm } from "@/features/resume";
import { ExpandLess as ExpandLessIcon, ExpandMore as ExpandMoreIcon } from "@mui/icons-material";
import { Box } from "@mui/material";
import Grid from "@mui/material/Grid2";
import { useState } from "react";
import { useDebounce } from "use-debounce";

/**
 * 職務経歴書一覧画面
 */
export const ResumeList = () => {
    // 検索ワード
    const [searchWord, setSearchWord] = useState<string>("");

    // 検索結果の反映を500ms遅延させる
    const [debouncedSearchWord] = useDebounce(searchWord, 500);

    // ソート指定
    const [sortType, setSortType] = useState<"name" | "date">("date");

    // 1度に表示するデータ量
    const itemPerPage = 9 as const;

    // 現在の表示件数
    const [currentDisplayCount, setCurrentDisplayCount] = useState<number>(itemPerPage);

    // ダミーデータ
    const [resumeData] = useState(
        Array.from({ length: 19 }, (_, i) => ({
            resumeId: String(i + 1),
            resumeName: `職務経歴書 ${i + 1}`,
            createdAt: `2024/0${Math.floor(i / 3) + 1}/0${(i % 3) + 1} ${String(
                Math.floor(Math.random() * 24),
            ).padStart(2, "0")}:${String(Math.floor(Math.random() * 60)).padStart(2, "0")}:${String(
                Math.floor(Math.random() * 60),
            ).padStart(2, "0")}`,
            updatedAt: `2024/0${Math.floor(i / 3) + 1}/0${(i % 3) + 1} ${String(
                Math.floor(Math.random() * 24),
            ).padStart(2, "0")}:${String(Math.floor(Math.random() * 60)).padStart(2, "0")}:${String(
                Math.floor(Math.random() * 60),
            ).padStart(2, "0")}`,
        })),
    );

    /**
     * 表示件数を増やす
     */
    const handleShowMore = () => {
        const nextCount = Math.min(currentDisplayCount + itemPerPage, filteredResumeData.length);
        setCurrentDisplayCount(nextCount);
    };

    /**
     * 表示件数を減らす
     */
    const handleShowLess = () => {
        setCurrentDisplayCount(itemPerPage);
    };

    /**
     * データのソートとフィルタリングをする
     * フィルタリング時、半角全角と大文字小文字を区別しない
     */
    const filteredResumeData = resumeData
        .filter((resume) => {
            // 検索対象の文字列を正規化（半角化）
            const normalizedName = resume.resumeName
                .normalize("NFKC") // 文字列を正規化（半角に統一）
                .toLowerCase(); // 小文字に変換

            // 検索語句も同様に正規化
            const normalizedSearchWord = debouncedSearchWord
                .normalize("NFKC") // 文字列を正規化（半角に統一）
                .toLowerCase(); // 小文字に変換

            return normalizedName.includes(normalizedSearchWord);
        })
        .sort((a, b) => {
            if (sortType === "name") {
                // ソートの際も文字列を正規化
                return a.resumeName.normalize("NFKC").localeCompare(b.resumeName.normalize("NFKC"));
            } else {
                return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime();
            }
        });

    return (
        <>
            {/* 検索フォーム */}
            <SearchForm
                searchWord={searchWord}
                setSearchWord={setSearchWord}
                sortType={sortType}
                setSortType={setSortType}
            />
            {/* 職務経歴書カード */}
            {filteredResumeData.length > 0 ? (
                <Grid container spacing={3} sx={{ my: 4 }}>
                    {filteredResumeData.slice(0, currentDisplayCount).map((resume) => (
                        <Grid size={{ xs: 12, sm: 6, md: 4 }} key={resume.resumeId}>
                            <ResumeCard
                                key={resume.resumeId}
                                resumeId={resume.resumeId}
                                resumeName={resume.resumeName}
                                createdAt={resume.createdAt}
                                updatedAt={resume.updatedAt}
                            />
                        </Grid>
                    ))}
                </Grid>
            ) : (
                <Box
                    sx={{
                        display: "flex",
                        justifyContent: "center",
                        alignItems: "center",
                        height: "calc(100vh - 300px)",
                        overflow: "hidden",
                    }}
                >
                    <NoData variant="h6" message={"表示するデータがありません。"} />
                </Box>
            )}
            {/* もっと見る or 表示を減らすボタン */}
            <Box sx={{ display: "flex", justifyContent: "center", gap: 2, my: 4 }}>
                {currentDisplayCount < filteredResumeData.length ? (
                    <Button variant="contained" endIcon={<ExpandMoreIcon />} onClick={handleShowMore}>
                        もっと見る
                    </Button>
                ) : filteredResumeData.length > itemPerPage ? (
                    <Button variant="contained" endIcon={<ExpandLessIcon />} onClick={handleShowLess}>
                        表示を減らす
                    </Button>
                ) : null}
            </Box>
        </>
    );
};
