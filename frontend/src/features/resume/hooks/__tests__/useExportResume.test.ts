import { vi } from "vitest";

// file-saverのモック
const mockSaveAs = vi.hoisted(() => vi.fn());
vi.mock("file-saver", () => ({
    saveAs: mockSaveAs,
}));

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import { useExportResume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createQueryWrapper } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useExportResume", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        vi.mocked(protectedApiClient.get).mockReset();
        mockSaveAs.mockReset();
    });

    it("PDF形式でエクスポートが成功した場合、saveAsが正しく呼ばれること", async () => {
        const mockResponse = {
            status: 200,
            data: new Blob(["test"], { type: "application/pdf" }),
            headers: { "content-disposition": 'attachment; filename="職務経歴書.pdf"' },
        } as unknown as AxiosResponse<Blob>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useExportResume(), { wrapper });

        act(() => {
            result.current.mutate({ resumeId: "resume-1", format: "pdf" });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1/export", {
            headers: { Accept: "application/pdf, application/json" },
            responseType: "blob",
        });
        expect(mockSaveAs).toHaveBeenCalledWith(expect.any(Blob), "職務経歴書.pdf");
    });

    it("Markdown形式でエクスポートが成功した場合、saveAsが正しく呼ばれること", async () => {
        const mockResponse = {
            status: 200,
            data: new Blob(["# test"], { type: "text/markdown" }),
            headers: { "content-disposition": 'attachment; filename="resume.md"' },
        } as unknown as AxiosResponse<Blob>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useExportResume(), { wrapper });

        act(() => {
            result.current.mutate({ resumeId: "resume-1", format: "markdown" });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1/export", {
            headers: { Accept: "text/markdown, application/json" },
            responseType: "blob",
        });
        expect(mockSaveAs).toHaveBeenCalledWith(expect.any(Blob), "resume.md");
    });

    it("Content-Dispositionヘッダーがない場合、デフォルトのファイル名が使用されること（PDF）", async () => {
        const mockResponse = {
            status: 200,
            data: new Blob(["test"], { type: "application/pdf" }),
            headers: {},
        } as unknown as AxiosResponse<Blob>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useExportResume(), { wrapper });

        act(() => {
            result.current.mutate({ resumeId: "resume-1", format: "pdf" });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(mockSaveAs).toHaveBeenCalledWith(expect.any(Blob), "resume.pdf");
    });

    it("Content-Dispositionヘッダーがない場合、デフォルトのファイル名が使用されること（Markdown）", async () => {
        const mockResponse = {
            status: 200,
            data: new Blob(["# test"], { type: "text/markdown" }),
            headers: {},
        } as unknown as AxiosResponse<Blob>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useExportResume(), { wrapper });

        act(() => {
            result.current.mutate({ resumeId: "resume-1", format: "markdown" });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(mockSaveAs).toHaveBeenCalledWith(expect.any(Blob), "resume.md");
    });

    it("エクスポートが失敗した場合、isErrorがtrueになること", async () => {
        vi.mocked(protectedApiClient.get).mockRejectedValueOnce(new Error("Network Error"));

        const { result } = renderHook(() => useExportResume(), { wrapper });

        act(() => {
            result.current.mutate({ resumeId: "resume-1", format: "pdf" });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        expect(mockSaveAs).not.toHaveBeenCalled();
    });
});
