import type { SectionName } from "@/features/resume";
import { AUTO_SAVE_INTERVAL_MS, buildPayloadForEntry, getResumeKey, isTempId, useResumeStore } from "@/features/resume";
import dayjs from "dayjs";
import { useEffect } from "react";
import { useDebouncedCallback } from "use-debounce";

/**
 * 自動保存フックのオプション
 */
interface UseAutoSaveOptions {
    /** 自動保存が有効かどうか */
    enabled: boolean;
    /** 職務経歴書ID */
    resumeId: string;
    /** 基本情報更新ミューテーション */
    updateBasicMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 職歴作成ミューテーション */
    createCareerMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 職歴更新ミューテーション */
    updateCareerMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** プロジェクト作成ミューテーション */
    createProjectMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** プロジェクト更新ミューテーション */
    updateProjectMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 資格作成ミューテーション */
    createCertificationMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 資格更新ミューテーション */
    updateCertificationMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** ポートフォリオ作成ミューテーション */
    createPortfolioMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** ポートフォリオ更新ミューテーション */
    updatePortfolioMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** SNS作成ミューテーション */
    createSocialLinkMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** SNS更新ミューテーション */
    updateSocialLinkMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 自己PR作成ミューテーション */
    createSelfPromotionMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 自己PR更新ミューテーション */
    updateSelfPromotionMutation: { mutate: (payload: any) => void; isPending: boolean };
}

/**
 * 自動保存フック（アクティブなエントリー単位・デバウンス方式）
 * 最後の編集から一定時間経過後に現在アクティブなエントリーのみを自動保存する
 */
export const useAutoSave = ({
    enabled,
    resumeId,
    updateBasicMutation,
    createCareerMutation,
    updateCareerMutation,
    createProjectMutation,
    updateProjectMutation,
    createCertificationMutation,
    updateCertificationMutation,
    createPortfolioMutation,
    updatePortfolioMutation,
    createSocialLinkMutation,
    updateSocialLinkMutation,
    createSelfPromotionMutation,
    updateSelfPromotionMutation,
}: UseAutoSaveOptions) => {
    const resume = useResumeStore((state) => state.resume);
    const isDirty = useResumeStore((state) => state.isDirty);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);

    // デバウンスされた保存処理
    const debouncedSave = useDebouncedCallback(() => {
        const { resume, activeSection, isDirty, activeEntryId, dirtyEntryIds } = useResumeStore.getState();

        if (!resume || !resumeId || !isDirty) {
            return;
        }

        // いずれかのミューテーションが実行中の場合はスキップ
        const isPending =
            updateBasicMutation.isPending ||
            createCareerMutation.isPending ||
            updateCareerMutation.isPending ||
            createProjectMutation.isPending ||
            updateProjectMutation.isPending ||
            createCertificationMutation.isPending ||
            updateCertificationMutation.isPending ||
            createPortfolioMutation.isPending ||
            updatePortfolioMutation.isPending ||
            createSocialLinkMutation.isPending ||
            updateSocialLinkMutation.isPending ||
            createSelfPromotionMutation.isPending ||
            updateSelfPromotionMutation.isPending;

        if (isPending) {
            return;
        }

        // 基本情報セクションの場合
        if (activeSection === "basicInfo") {
            updateBasicMutation.mutate({
                resumeName: resume.resumeName,
                date: dayjs(resume.date).format("YYYY-MM-DD"),
                lastName: resume.lastName ?? "",
                firstName: resume.firstName ?? "",
            });
            return;
        }

        // アクティブなエントリーがない場合、またはアクティブなエントリーがdirtyでない場合はスキップ
        if (!activeEntryId || !dirtyEntryIds.has(activeEntryId)) {
            return;
        }

        // アクティブなエントリーを取得
        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey) return;

        const list = resume[sectionKey];
        const activeEntry = list.find((item) => item.id === activeEntryId);
        if (!activeEntry) return;

        // 新規作成か更新かを判定
        const isNew = isTempId(activeEntryId);

        // セクションに応じてミューテーションを呼び出す
        executeMutation(activeSection, activeEntry, activeEntryId, isNew, {
            createCareerMutation,
            updateCareerMutation,
            createProjectMutation,
            updateProjectMutation,
            createCertificationMutation,
            updateCertificationMutation,
            createPortfolioMutation,
            updatePortfolioMutation,
            createSocialLinkMutation,
            updateSocialLinkMutation,
            createSelfPromotionMutation,
            updateSelfPromotionMutation,
        });
    }, AUTO_SAVE_INTERVAL_MS);

    // resumeまたはactiveEntryIdが変更されたらデバウンス保存をトリガー
    useEffect(() => {
        if (enabled && isDirty) {
            debouncedSave();
        }
    }, [enabled, resume, isDirty, activeEntryId, debouncedSave]);

    // enabledがfalseになったらキャンセル
    useEffect(() => {
        if (!enabled) {
            debouncedSave.cancel();
        }
    }, [enabled, debouncedSave]);
};

/**
 * セクションに応じてミューテーションを実行する
 */
const executeMutation = (
    activeSection: SectionName,
    activeEntry: any,
    activeEntryId: string,
    isNew: boolean,
    mutations: {
        createCareerMutation: { mutate: (payload: any) => void };
        updateCareerMutation: { mutate: (payload: any) => void };
        createProjectMutation: { mutate: (payload: any) => void };
        updateProjectMutation: { mutate: (payload: any) => void };
        createCertificationMutation: { mutate: (payload: any) => void };
        updateCertificationMutation: { mutate: (payload: any) => void };
        createPortfolioMutation: { mutate: (payload: any) => void };
        updatePortfolioMutation: { mutate: (payload: any) => void };
        createSocialLinkMutation: { mutate: (payload: any) => void };
        updateSocialLinkMutation: { mutate: (payload: any) => void };
        createSelfPromotionMutation: { mutate: (payload: any) => void };
        updateSelfPromotionMutation: { mutate: (payload: any) => void };
    },
) => {
    switch (activeSection) {
        case "career":
            if (isNew) {
                mutations.createCareerMutation.mutate({
                    tempId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            } else {
                mutations.updateCareerMutation.mutate({
                    careerId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            }
            break;
        case "project":
            if (isNew) {
                mutations.createProjectMutation.mutate({
                    tempId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            } else {
                mutations.updateProjectMutation.mutate({
                    projectId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            }
            break;
        case "certification":
            if (isNew) {
                mutations.createCertificationMutation.mutate({
                    tempId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            } else {
                mutations.updateCertificationMutation.mutate({
                    certificationId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            }
            break;
        case "portfolio":
            if (isNew) {
                mutations.createPortfolioMutation.mutate({
                    tempId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            } else {
                mutations.updatePortfolioMutation.mutate({
                    portfolioId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            }
            break;
        case "socialLink":
            if (isNew) {
                mutations.createSocialLinkMutation.mutate({
                    tempId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            } else {
                mutations.updateSocialLinkMutation.mutate({
                    socialLinkId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            }
            break;
        case "selfPromotion":
            if (isNew) {
                mutations.createSelfPromotionMutation.mutate({
                    tempId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            } else {
                mutations.updateSelfPromotionMutation.mutate({
                    selfPromotionId: activeEntryId,
                    payload: buildPayloadForEntry(activeSection, activeEntry),
                });
            }
            break;
    }
};
