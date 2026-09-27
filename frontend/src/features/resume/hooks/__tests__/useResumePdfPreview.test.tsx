import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
}));

import type { ResumePdfSettings } from "@/features/resume";
import { DEFAULT_RESUME_PDF_SETTINGS, RESUME_NOT_FOUND_MESSAGE, useResumePdfPreview } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, createTestQueryClient, resetStoresAndMocks } from "@/test";
import { QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { AxiosError, CanceledError } from "axios";
import type { ReactNode } from "react";

type Deferred = {
    promise: Promise<AxiosResponse<Blob>>;
    resolve: (value: AxiosResponse<Blob>) => void;
    reject: (reason: unknown) => void;
};

const createDeferred = (): Deferred => {
    let resolve!: Deferred["resolve"];
    let reject!: Deferred["reject"];
    const promise = new Promise<AxiosResponse<Blob>>((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
};

const pdfResponse = (content: string) => createAxiosResponse(new Blob([content], { type: "application/pdf" }));

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const changedSettings: ResumePdfSettings = {
    ...DEFAULT_RESUME_PDF_SETTINGS,
    fontSizes: { ...DEFAULT_RESUME_PDF_SETTINGS.fontSizes, title: 20 },
};

const resumeNotFoundError = () =>
    new AxiosError("Not Found", "ERR_BAD_REQUEST", undefined, undefined, {
        ...createAxiosResponse({ message: RESUME_NOT_FOUND_MESSAGE, errors: {} }),
        status: 404,
    });

/** 送信したPDF設定(本文のpdfSettings)を呼び出し順に取り出す */
const sentSettings = () =>
    vi
        .mocked(protectedApiClient.post)
        .mock.calls.map(([, body]) => (body as { pdfSettings: ResumePdfSettings }).pdfSettings);

describe("useResumePdfPreview", () => {
    const post = vi.mocked(protectedApiClient.post);
    let urlCount = 0;
    const createObjectURL = vi.fn(() => {
        urlCount += 1;
        return `blob:preview-${urlCount}`;
    });
    const revokeObjectURL = vi.fn();

    const renderPreviewHook = (onResumeNotFound?: () => void) => {
        const queryClient = createTestQueryClient();
        const refetchQueries = vi.spyOn(queryClient, "refetchQueries").mockResolvedValue();
        const wrapper = ({ children }: { children: ReactNode }) => (
            <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
        );
        const view = renderHook(() => useResumePdfPreview({ onResumeNotFound }), { wrapper });
        return { ...view, refetchQueries };
    };

    /** プレビューを開き、最初の生成が終わるまで待つ */
    const openAndWait = async (result: { current: ReturnType<typeof useResumePdfPreview> }) => {
        act(() => {
            result.current.openPreview("resume-1");
        });
        await waitFor(() => expect(result.current.open).toBe(true));
    };

    beforeEach(() => {
        resetStoresAndMocks([() => post.mockReset()]);
        urlCount = 0;
        createObjectURL.mockClear();
        revokeObjectURL.mockClear();
        URL.createObjectURL = createObjectURL;
        URL.revokeObjectURL = revokeObjectURL;
    });

    it("プレビューを開くと、初期設定でインライン表示のPDFを生成して開くこと", async () => {
        post.mockResolvedValue(pdfResponse("pdf-1"));
        const { result } = renderPreviewHook();

        await openAndWait(result);

        expect(post).toHaveBeenCalledOnce();
        expect(post).toHaveBeenCalledWith(
            "/resumes/resume-1/export",
            { format: "pdf", disposition: "inline", pdfSettings: DEFAULT_RESUME_PDF_SETTINGS },
            expect.objectContaining({ responseType: "blob" }),
        );
        expect(result.current.previewUrl).toBe("blob:preview-1");
    });

    it("開いた直後に、同じ設定で生成し直さないこと", async () => {
        post.mockResolvedValue(pdfResponse("pdf-1"));
        const { result } = renderPreviewHook();

        await openAndWait(result);
        await act(() => sleep(700));

        expect(post).toHaveBeenCalledOnce();
    });

    it("連続で生成したとき、後から出したリクエストの結果だけを反映すること", async () => {
        post.mockResolvedValueOnce(pdfResponse("pdf-1"));
        const { result } = renderPreviewHook();
        await openAndWait(result);

        const older = createDeferred();
        const newer = createDeferred();
        post.mockReturnValueOnce(older.promise).mockReturnValueOnce(newer.promise);

        act(() => {
            result.current.refresh();
        });
        act(() => {
            result.current.refresh();
        });
        await waitFor(() => expect(post).toHaveBeenCalledTimes(3));

        await act(async () => {
            newer.resolve(pdfResponse("newer"));
            await newer.promise;
        });
        await waitFor(() => expect(result.current.previewUrl).toBe("blob:preview-2"));

        await act(async () => {
            older.resolve(pdfResponse("older"));
            await older.promise;
        });

        expect(createObjectURL).toHaveBeenCalledTimes(2);
        expect(result.current.previewUrl).toBe("blob:preview-2");
        expect(result.current.open).toBe(true);
    });

    it("キャンセルされたリクエストはエラーとして扱わず、プレビューを閉じないこと", async () => {
        post.mockResolvedValueOnce(pdfResponse("pdf-1"));
        const onResumeNotFound = vi.fn();
        const { result } = renderPreviewHook(onResumeNotFound);
        await openAndWait(result);

        post.mockRejectedValueOnce(new CanceledError());
        await act(async () => {
            result.current.refresh();
            await sleep(0);
        });

        expect(result.current.open).toBe(true);
        expect(result.current.previewUrl).toBe("blob:preview-1");
        expect(onResumeNotFound).not.toHaveBeenCalled();
    });

    it("職務経歴書が見つからないときは、一覧を再取得して呼び出し元に知らせ、プレビューを閉じること", async () => {
        post.mockRejectedValueOnce(resumeNotFoundError());
        const onResumeNotFound = vi.fn();
        const { result, refetchQueries } = renderPreviewHook(onResumeNotFound);

        act(() => {
            result.current.openPreview("resume-1");
        });

        await waitFor(() => expect(onResumeNotFound).toHaveBeenCalledOnce());
        expect(onResumeNotFound).toHaveBeenCalledWith({ message: RESUME_NOT_FOUND_MESSAGE, errors: {} });
        expect(refetchQueries).toHaveBeenCalledWith({ queryKey: ["getResumeList"], type: "active" });
        expect(result.current.open).toBe(false);
        expect(result.current.previewUrl).toBeNull();
    });

    it("それ以外のエラーでは、呼び出し元に知らせずにプレビューを閉じること", async () => {
        post.mockResolvedValueOnce(pdfResponse("pdf-1"));
        const onResumeNotFound = vi.fn();
        const { result, refetchQueries } = renderPreviewHook(onResumeNotFound);
        await openAndWait(result);

        post.mockRejectedValueOnce(
            new AxiosError("Server Error", "ERR_BAD_RESPONSE", undefined, undefined, {
                ...createAxiosResponse({ message: "サーバーエラー", errors: {} }),
                status: 500,
            }),
        );
        act(() => {
            result.current.refresh();
        });

        await waitFor(() => expect(result.current.open).toBe(false));
        expect(onResumeNotFound).not.toHaveBeenCalled();
        expect(refetchQueries).not.toHaveBeenCalled();
        expect(result.current.previewUrl).toBeNull();
    });

    it("設定を変えると、500ms待ってから新しい設定で生成し直すこと", async () => {
        post.mockResolvedValue(pdfResponse("pdf"));
        const { result } = renderPreviewHook();
        await openAndWait(result);

        act(() => {
            result.current.updateSettings(changedSettings);
        });
        await act(() => sleep(300));
        expect(post).toHaveBeenCalledOnce();

        await waitFor(() => expect(post).toHaveBeenCalledTimes(2));
        expect(sentSettings()[1]).toEqual(changedSettings);
    });

    it("同じ内容の設定を渡しても、生成し直さないこと", async () => {
        post.mockResolvedValue(pdfResponse("pdf"));
        const { result } = renderPreviewHook();
        await openAndWait(result);

        act(() => {
            result.current.updateSettings({ ...DEFAULT_RESUME_PDF_SETTINGS });
        });
        await act(() => sleep(700));

        expect(post).toHaveBeenCalledOnce();
    });

    it("設定を初期値に戻すと、待たずに初期設定で生成し直すこと", async () => {
        post.mockResolvedValue(pdfResponse("pdf"));
        const { result } = renderPreviewHook();
        await openAndWait(result);

        act(() => {
            result.current.updateSettings(changedSettings);
        });
        await act(() => sleep(100));
        act(() => {
            result.current.resetSettings();
        });

        await waitFor(() => expect(post).toHaveBeenCalledTimes(2), { timeout: 200 });
        expect(sentSettings()[1]).toEqual(DEFAULT_RESUME_PDF_SETTINGS);

        // 取り消した変更の分を、後から生成しないこと
        await act(() => sleep(700));
        expect(post).toHaveBeenCalledTimes(2);
    });

    it("待っている間に閉じたときは、生成し直さないこと", async () => {
        post.mockResolvedValue(pdfResponse("pdf"));
        const { result } = renderPreviewHook();
        await openAndWait(result);

        act(() => {
            result.current.updateSettings(changedSettings);
        });
        act(() => {
            result.current.close();
        });
        await act(() => sleep(700));

        expect(post).toHaveBeenCalledOnce();
    });

    it("新しいプレビューを出したときと閉じたときに、前のプレビューのURLを片付けること", async () => {
        post.mockResolvedValue(pdfResponse("pdf"));
        const { result } = renderPreviewHook();
        await openAndWait(result);
        expect(revokeObjectURL).not.toHaveBeenCalled();

        act(() => {
            result.current.refresh();
        });
        await waitFor(() => expect(result.current.previewUrl).toBe("blob:preview-2"));
        expect(revokeObjectURL).toHaveBeenCalledWith("blob:preview-1");

        act(() => {
            result.current.close();
        });
        expect(revokeObjectURL).toHaveBeenCalledWith("blob:preview-2");
        expect(result.current.previewUrl).toBeNull();
        expect(result.current.open).toBe(false);
    });

    it("アンマウントしたときに、表示中のプレビューのURLを片付けること", async () => {
        post.mockResolvedValue(pdfResponse("pdf"));
        const { result, unmount } = renderPreviewHook();
        await openAndWait(result);

        unmount();

        expect(revokeObjectURL).toHaveBeenCalledWith("blob:preview-1");
    });

    it("生成している間だけ、生成中の状態になること", async () => {
        const pending = createDeferred();
        post.mockReturnValueOnce(pending.promise);
        const { result } = renderPreviewHook();

        expect(result.current.isPending).toBe(false);
        act(() => {
            result.current.openPreview("resume-1");
        });
        await waitFor(() => expect(result.current.isPending).toBe(true));

        await act(async () => {
            pending.resolve(pdfResponse("pdf"));
            await pending.promise;
        });
        await waitFor(() => expect(result.current.isPending).toBe(false));
    });
});
