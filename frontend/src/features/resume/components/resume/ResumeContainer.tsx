import { Button, Dialog } from "@/components/ui";
import {
    BottomMenu,
    buildPayloadForEntry,
    createCurrentSection,
    EntryList,
    getResumeKey,
    isTempId,
    sections,
    SectionTabs,
    useAutoSave,
    useCreateCareer,
    useCreateCertification,
    useCreatePortfolio,
    useCreateProject,
    useCreateSelfPromotion,
    useCreateSnsPlatform,
    useDeleteCareer,
    useDeleteCertification,
    useDeletePortfolio,
    useDeleteProject,
    useDeleteSelfPromotion,
    useDeleteSnsPlatform,
    useGetResumeInfo,
    useNavigationBlocker,
    useResumeStore,
    useUpdateCareer,
    useUpdateCertification,
    useUpdatePortfolio,
    useUpdateProject,
    useUpdateResumeBasic,
    useUpdateSelfPromotion,
    useUpdateSnsPlatform,
} from "@/features/resume";
import DeleteIcon from "@mui/icons-material/Delete";
import SaveIcon from "@mui/icons-material/Save";
import { Box, Divider, Typography } from "@mui/material";
import Grid from "@mui/material/Grid2";
import dayjs from "dayjs";
import { useState } from "react";
import { useParams } from "react-router";

/**
 * 職務経歴書詳細コンテナ
 */
export const ResumeContainer = () => {
    const { id: resumeId } = useParams<{ id: string }>();

    // 離脱防止フック
    const { dialogProps } = useNavigationBlocker();

    // 現在のセクションを監視
    const activeSection = useResumeStore((state) => state.activeSection);
    const currentSection = sections.find((section) => section.key === activeSection)!;

    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const removeEntry = useResumeStore((state) => state.removeEntry);
    const setActiveEntryId = useResumeStore((state) => state.setActiveEntryId);
    const isDirty = useResumeStore((state) => state.isDirty);
    const dirtyEntryIds = useResumeStore((state) => state.dirtyEntryIds);

    // タイトル取得
    const title = currentSection.label + "情報";

    // BottomMenuの高さを動的に取得
    const [bottomMenuHeight, setBottomMenuHeight] = useState(0);

    // 自動保存の有効/無効状態
    const [autoSaveEnabled, setAutoSaveEnabled] = useState(false);

    // 削除確認ダイアログ
    const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

    // 職務経歴書詳細情報取得
    const { isLoading } = useGetResumeInfo(resumeId ?? "");

    // 基本情報更新ミューテーション
    const updateBasicMutation = useUpdateResumeBasic(resumeId ?? "");

    // 各セクションの作成・更新・削除ミューテーション
    const createCareerMutation = useCreateCareer(resumeId ?? "");
    const updateCareerMutation = useUpdateCareer(resumeId ?? "");
    const deleteCareerMutation = useDeleteCareer(resumeId ?? "");

    const createProjectMutation = useCreateProject(resumeId ?? "");
    const updateProjectMutation = useUpdateProject(resumeId ?? "");
    const deleteProjectMutation = useDeleteProject(resumeId ?? "");

    const createCertificationMutation = useCreateCertification(resumeId ?? "");
    const updateCertificationMutation = useUpdateCertification(resumeId ?? "");
    const deleteCertificationMutation = useDeleteCertification(resumeId ?? "");

    const createPortfolioMutation = useCreatePortfolio(resumeId ?? "");
    const updatePortfolioMutation = useUpdatePortfolio(resumeId ?? "");
    const deletePortfolioMutation = useDeletePortfolio(resumeId ?? "");

    const createSnsPlatformMutation = useCreateSnsPlatform(resumeId ?? "");
    const updateSnsPlatformMutation = useUpdateSnsPlatform(resumeId ?? "");
    const deleteSnsPlatformMutation = useDeleteSnsPlatform(resumeId ?? "");

    const createSelfPromotionMutation = useCreateSelfPromotion(resumeId ?? "");
    const updateSelfPromotionMutation = useUpdateSelfPromotion(resumeId ?? "");
    const deleteSelfPromotionMutation = useDeleteSelfPromotion(resumeId ?? "");

    // 自動保存フック
    useAutoSave({
        enabled: autoSaveEnabled,
        resumeId: resumeId ?? "",
        updateBasicMutation,
        createCareerMutation,
        updateCareerMutation,
        createProjectMutation,
        updateProjectMutation,
        createCertificationMutation,
        updateCertificationMutation,
        createPortfolioMutation,
        updatePortfolioMutation,
        createSnsPlatformMutation,
        updateSnsPlatformMutation,
        createSelfPromotionMutation,
        updateSelfPromotionMutation,
    });

    // BottomMenuの高さ計測
    const measuredRef = (node: HTMLDivElement | null) => {
        if (node !== null) {
            setBottomMenuHeight(node.offsetHeight);
        }
    };

    /**
     * 削除ボタン押下
     */
    const handleDeleteCurrentEntry = () => {
        if (!activeEntryId || !resume) return;

        // 一時IDの場合は警告なしでストアから削除
        if (isTempId(activeEntryId)) {
            deleteFromStore(activeEntryId);
            return;
        }

        // 既存エントリーの場合は確認ダイアログを表示
        setDeleteDialogOpen(true);
    };

    /**
     * ストアからエントリーを削除
     */
    const deleteFromStore = (entryId: string) => {
        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey || !resume) return;

        removeEntry(sectionKey, entryId);
        setActiveEntryId(null);
    };

    /**
     * 削除確認ダイアログのコールバック
     */
    const handleDeleteDialogClose = (confirmed: boolean) => {
        setDeleteDialogOpen(false);
        if (confirmed && activeEntryId && resume) {
            // APIを呼び出して削除
            executeDeleteMutation(activeEntryId);
        }
    };

    /**
     * セクションに応じた削除ミューテーションを実行
     */
    const executeDeleteMutation = (entryId: string) => {
        switch (activeSection) {
            case "career":
                deleteCareerMutation.mutate(entryId);
                break;
            case "project":
                deleteProjectMutation.mutate(entryId);
                break;
            case "certification":
                deleteCertificationMutation.mutate(entryId);
                break;
            case "portfolio":
                deletePortfolioMutation.mutate(entryId);
                break;
            case "snsPlatform":
                deleteSnsPlatformMutation.mutate(entryId);
                break;
            case "selfPromotion":
                deleteSelfPromotionMutation.mutate(entryId);
                break;
        }
    };

    /**
     * 日付を安全にフォーマットする
     * 無効な日付の場合は空文字列を返す
     */
    const formatDateSafe = (date: string | null | undefined): string => {
        if (!date) return "";
        const parsed = dayjs(date);
        return parsed.isValid() ? parsed.format("YYYY-MM-DD") : "";
    };

    /**
     * 現在のアクティブなエントリーのみを保存
     */
    const handleSaveCurrentEntry = () => {
        if (!resume || !resumeId) return;

        // 基本情報セクションの場合
        if (activeSection === "basicInfo") {
            updateBasicMutation.mutate({
                resumeName: resume.resumeName,
                date: formatDateSafe(resume.date),
                lastName: resume.lastName ?? "",
                firstName: resume.firstName ?? "",
            });
            return;
        }

        // リスト型セクションの場合
        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey || !activeEntryId) return;

        const list = resume[sectionKey];
        const activeEntry = list.find((item) => item.id === activeEntryId);
        if (!activeEntry) return;

        // 新規作成か更新かを判定
        const isNew = isTempId(activeEntryId);

        // セクションに応じてミューテーションを呼び出す
        executeSaveMutation(activeEntry, activeEntryId, isNew);
    };

    /**
     * セクションに応じた保存ミューテーションを実行
     */
    const executeSaveMutation = (activeEntry: any, entryId: string, isNew: boolean) => {
        switch (activeSection) {
            case "career":
                if (isNew) {
                    createCareerMutation.mutate({
                        tempId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                } else {
                    updateCareerMutation.mutate({
                        careerId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                }
                break;
            case "project":
                if (isNew) {
                    createProjectMutation.mutate({
                        tempId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                } else {
                    updateProjectMutation.mutate({
                        projectId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                }
                break;
            case "certification":
                if (isNew) {
                    createCertificationMutation.mutate({
                        tempId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                } else {
                    updateCertificationMutation.mutate({
                        certificationId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                }
                break;
            case "portfolio":
                if (isNew) {
                    createPortfolioMutation.mutate({
                        tempId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                } else {
                    updatePortfolioMutation.mutate({
                        portfolioId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                }
                break;
            case "snsPlatform":
                if (isNew) {
                    createSnsPlatformMutation.mutate({
                        tempId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                } else {
                    updateSnsPlatformMutation.mutate({
                        snsPlatformId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                }
                break;
            case "selfPromotion":
                if (isNew) {
                    createSelfPromotionMutation.mutate({
                        tempId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                } else {
                    updateSelfPromotionMutation.mutate({
                        selfPromotionId: entryId,
                        payload: buildPayloadForEntry(activeSection, activeEntry),
                    });
                }
                break;
        }
    };

    // ローディング状態
    const isSaving =
        updateBasicMutation.isPending ||
        createCareerMutation.isPending ||
        updateCareerMutation.isPending ||
        deleteCareerMutation.isPending ||
        createProjectMutation.isPending ||
        updateProjectMutation.isPending ||
        deleteProjectMutation.isPending ||
        createCertificationMutation.isPending ||
        updateCertificationMutation.isPending ||
        deleteCertificationMutation.isPending ||
        createPortfolioMutation.isPending ||
        updatePortfolioMutation.isPending ||
        deletePortfolioMutation.isPending ||
        createSnsPlatformMutation.isPending ||
        updateSnsPlatformMutation.isPending ||
        deleteSnsPlatformMutation.isPending ||
        createSelfPromotionMutation.isPending ||
        updateSelfPromotionMutation.isPending ||
        deleteSelfPromotionMutation.isPending;

    // データ取得中またはresumeがnullの場合は何も表示しない
    if (isLoading || !resume) {
        return null;
    }

    // 保存・削除ボタンの表示条件
    const showButtons = activeSection === "basicInfo" || activeEntryId !== null;

    // アクティブなエントリーが編集状態かどうかを判定
    const isActiveEntryDirty =
        activeSection === "basicInfo" ? isDirty : activeEntryId !== null && dirtyEntryIds.has(activeEntryId);

    return (
        <>
            {/* セクション切り替えタブ */}
            <SectionTabs />

            <Grid container spacing={3} sx={{ mt: 2, mb: `${bottomMenuHeight}px` }}>
                {currentSection.type === "list" && (
                    <Grid size={{ xs: 12, md: 4 }}>
                        {/* エントリーリスト */}
                        <EntryList />
                    </Grid>
                )}
                <Grid size={{ xs: 12, md: currentSection.type === "list" ? 8 : 12 }}>
                    {/* セクション */}
                    <Box
                        sx={{
                            bgcolor: "background.paper",
                            borderRadius: 2,
                            boxShadow: 1,
                        }}
                    >
                        <Box
                            sx={{
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "space-between",
                                p: 2,
                            }}
                        >
                            {/* コンテンツタイトル */}
                            <Typography variant="h6">{title}</Typography>
                            {showButtons && (
                                <Box sx={{ display: "flex", gap: 1 }}>
                                    {/* 保存ボタン */}
                                    <Button
                                        color="info"
                                        size="small"
                                        startIcon={<SaveIcon />}
                                        onClick={handleSaveCurrentEntry}
                                        disabled={isSaving || !isActiveEntryDirty}
                                    >
                                        保存
                                    </Button>
                                    {/* 削除ボタン（リスト型セクションのみ） */}
                                    {currentSection.type === "list" && (
                                        <Button
                                            color="error"
                                            size="small"
                                            startIcon={<DeleteIcon />}
                                            onClick={handleDeleteCurrentEntry}
                                        >
                                            削除
                                        </Button>
                                    )}
                                </Box>
                            )}
                        </Box>
                        <Divider />
                        <Box sx={{ display: "flex", flexDirection: "column", justifyContent: "center", p: 3 }}>
                            {createCurrentSection(activeSection)}
                        </Box>
                    </Box>
                </Grid>
            </Grid>
            {/* 下部メニュー */}
            <BottomMenu
                ref={measuredRef}
                autoSaveEnabled={autoSaveEnabled}
                onAutoSaveToggle={setAutoSaveEnabled}
                onSave={handleSaveCurrentEntry}
                isSaving={isSaving}
                canSave={isActiveEntryDirty}
            />
            {/* 離脱防止ダイアログ */}
            <Dialog
                open={dialogProps.open}
                variant="confirm"
                title="このページを離れますか？"
                description="保存されていない変更があります。このまま離れると、変更内容は失われます。"
                onClose={dialogProps.onClose}
            />
            {/* 削除確認ダイアログ */}
            <Dialog
                open={deleteDialogOpen}
                variant="confirm"
                title="削除確認"
                description="このエントリーを削除しますか？この操作は取り消せません。"
                onClose={handleDeleteDialogClose}
            />
        </>
    );
};
