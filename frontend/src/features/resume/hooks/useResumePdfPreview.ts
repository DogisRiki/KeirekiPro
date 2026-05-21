import {
    buildResumePdfSettingsPayload,
    DEFAULT_RESUME_PDF_SETTINGS,
    exportResumePdf,
    isSameResumePdfSettings,
    type ResumePdfSettings,
} from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import { extractFileName } from "@/utils";
import { useMutation } from "@tanstack/react-query";
import type { AxiosResponse } from "axios";
import axios from "axios";
import { saveAs } from "file-saver";
import { useCallback, useEffect, useRef, useState } from "react";
import { useDebouncedCallback } from "use-debounce";

/**
 * 職務経歴書PDFプレビューを管理するフック
 */
export const useResumePdfPreview = () => {
    const { clearErrors } = useErrorMessageStore();
    const [open, setOpen] = useState(false);
    const [resumeId, setResumeId] = useState<string | null>(null);
    const [settings, setSettings] = useState<ResumePdfSettings>(DEFAULT_RESUME_PDF_SETTINGS);
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);

    const previewUrlRef = useRef<string | null>(null);
    const previewAbortRef = useRef<AbortController | null>(null);
    const requestIdRef = useRef(0);
    const skipNextDebounceRef = useRef(false);

    /**
     * 現在保持しているプレビューURLを破棄する
     */
    const revokePreviewUrl = useCallback(() => {
        if (previewUrlRef.current) {
            URL.revokeObjectURL(previewUrlRef.current);
            previewUrlRef.current = null;
        }
        setPreviewUrl(null);
    }, []);

    const {
        mutateAsync: generatePreviewAsync,
        reset: resetPreviewMutation,
        isPending: isPreviewPending,
    } = useMutation<
        AxiosResponse<Blob>,
        unknown,
        { resumeId: string; settings: ResumePdfSettings; signal: AbortSignal }
    >({
        mutationFn: ({ resumeId, settings, signal }) =>
            exportResumePdf(
                resumeId,
                {
                    format: "pdf",
                    disposition: "inline",
                    pdfSettings: buildResumePdfSettingsPayload(settings),
                },
                signal,
            ),
    });

    const {
        mutateAsync: exportPdfAsync,
        reset: resetExportMutation,
        isPending: isExportPending,
    } = useMutation<AxiosResponse<Blob>, unknown, { resumeId: string; settings: ResumePdfSettings }>({
        mutationFn: ({ resumeId, settings }) =>
            exportResumePdf(resumeId, {
                format: "pdf",
                disposition: "attachment",
                pdfSettings: buildResumePdfSettingsPayload(settings),
            }),
        onSuccess: (response) => {
            clearErrors();
            const fileName = extractFileName(response.headers["content-disposition"]) ?? "resume.pdf";
            const blob = new Blob([response.data], { type: "application/pdf" });
            saveAs(blob, fileName);
        },
    });

    /**
     * プレビュー状態を閉じて一時データを初期化する
     */
    const close = useCallback(() => {
        previewAbortRef.current?.abort();
        previewAbortRef.current = null;
        requestIdRef.current += 1;
        revokePreviewUrl();
        setOpen(false);
        setResumeId(null);
        setSettings(DEFAULT_RESUME_PDF_SETTINGS);
        resetPreviewMutation();
        resetExportMutation();
    }, [resetExportMutation, resetPreviewMutation, revokePreviewUrl]);

    /**
     * 現在の設定でPDFプレビューを生成する
     */
    const generatePreview = useCallback(
        async (targetSettings: ResumePdfSettings) => {
            if (!resumeId) return;

            previewAbortRef.current?.abort();
            const controller = new AbortController();
            previewAbortRef.current = controller;
            const requestId = requestIdRef.current + 1;
            requestIdRef.current = requestId;

            try {
                const response = await generatePreviewAsync({
                    resumeId,
                    settings: targetSettings,
                    signal: controller.signal,
                });

                if (requestId !== requestIdRef.current) {
                    return;
                }

                const blob = new Blob([response.data], { type: "application/pdf" });
                const url = URL.createObjectURL(blob);
                revokePreviewUrl();
                previewUrlRef.current = url;
                setPreviewUrl(url);
                clearErrors();
            } catch (error) {
                if (axios.isCancel(error) || (axios.isAxiosError(error) && error.code === "ERR_CANCELED")) {
                    return;
                }
                close();
            }
        },
        [clearErrors, close, generatePreviewAsync, resumeId, revokePreviewUrl],
    );

    /**
     * PDFプレビュー生成を500ms遅延させる
     */
    const debouncedGeneratePreview = useDebouncedCallback((targetSettings?: ResumePdfSettings) => {
        if (!targetSettings) return;
        void generatePreview(targetSettings);
    }, 500);
    const debouncedGeneratePreviewRef = useRef(debouncedGeneratePreview);

    useEffect(() => {
        debouncedGeneratePreviewRef.current = debouncedGeneratePreview;
    }, [debouncedGeneratePreview]);

    /**
     * PDFプレビューを初期設定で開く
     */
    const openPreview = useCallback(
        (targetResumeId: string) => {
            clearErrors();
            skipNextDebounceRef.current = true;
            setResumeId(targetResumeId);
            setSettings(DEFAULT_RESUME_PDF_SETTINGS);
            setOpen(true);
        },
        [clearErrors],
    );

    /**
     * PDF設定を変更する
     */
    const updateSettings = useCallback((nextSettings: ResumePdfSettings) => {
        setSettings((currentSettings) =>
            isSameResumePdfSettings(currentSettings, nextSettings) ? currentSettings : nextSettings,
        );
    }, []);

    /**
     * debounceを待たずPDFプレビューを再生成する
     */
    const refresh = useCallback(() => {
        debouncedGeneratePreview.cancel();
        void generatePreview(settings);
    }, [debouncedGeneratePreview, generatePreview, settings]);

    /**
     * PDF設定を初期値へ戻す
     */
    const resetSettings = useCallback(() => {
        skipNextDebounceRef.current = true;
        setSettings(DEFAULT_RESUME_PDF_SETTINGS);
        debouncedGeneratePreview.cancel();
    }, [debouncedGeneratePreview]);

    /**
     * 現在の設定でPDFをダウンロードする
     */
    const exportPdf = useCallback(async () => {
        if (!resumeId) return;
        try {
            await exportPdfAsync({ resumeId, settings });
        } catch (error) {
            if (axios.isCancel(error) || (axios.isAxiosError(error) && error.code === "ERR_CANCELED")) {
                return;
            }
            close();
        }
    }, [close, exportPdfAsync, resumeId, settings]);

    useEffect(() => {
        if (!open || !resumeId) {
            return;
        }
        if (skipNextDebounceRef.current) {
            skipNextDebounceRef.current = false;
            void generatePreview(settings);
            return;
        }
        debouncedGeneratePreviewRef.current(settings);
    }, [generatePreview, open, resumeId, settings]);

    useEffect(() => {
        return () => {
            debouncedGeneratePreviewRef.current.cancel();
            previewAbortRef.current?.abort();
            if (previewUrlRef.current) {
                URL.revokeObjectURL(previewUrlRef.current);
            }
        };
    }, []);

    return {
        open,
        previewUrl,
        settings,
        isPending: isPreviewPending || isExportPending,
        openPreview,
        close,
        updateSettings,
        refresh,
        resetSettings,
        exportPdf,
    };
};
