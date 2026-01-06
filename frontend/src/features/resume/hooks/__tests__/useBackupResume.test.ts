import { vi } from "vitest";

// file-saverのモック
const mockSaveAs = vi.hoisted(() => vi.fn());
vi.mock("file-saver", () => ({
    saveAs: mockSaveAs,
}));

// extractFileNameのモック
const mockExtractFileName = vi.hoisted(() => vi.fn());
vi.mock("@/utils", () => ({
    extractFileName: mockExtractFileName,
}));

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import { useBackupResume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useBackupResume", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        mockSaveAs.mockReset();
        mockExtractFileName.mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("バックアップが成功した場合、saveAsが正しく呼ばれること（Content-Dispositionあり）", async () => {
        const mockResponse = {
            status: 200,
            data: new Blob(['{"test":"ok"}'], { type: "application/json" }),
            headers: { "content-disposition": 'attachment; filename="resume_backup.json"' },
        } as unknown as AxiosResponse<Blob>;

        mockExtractFileName.mockReturnValueOnce("resume_backup.json");
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useBackupResume(), { wrapper });

        act(() => {
            result.current.mutate("resume-1");
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1/backup", {
            headers: { Accept: "application/json" },
            responseType: "blob",
        });

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();
        expect(mockExtractFileName).toHaveBeenCalledWith('attachment; filename="resume_backup.json"');
        expect(mockSaveAs).toHaveBeenCalledWith(expect.any(Blob), "resume_backup.json");
    });

    it("Content-Dispositionヘッダーがない場合、デフォルトのファイル名が使用されること", async () => {
        const mockResponse = {
            status: 200,
            data: new Blob(['{"test":"ok"}'], { type: "application/json" }),
            headers: {},
        } as unknown as AxiosResponse<Blob>;

        mockExtractFileName.mockReturnValueOnce(undefined);
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useBackupResume(), { wrapper });

        act(() => {
            result.current.mutate("resume-1");
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1/backup", {
            headers: { Accept: "application/json" },
            responseType: "blob",
        });

        expect(mockExtractFileName).toHaveBeenCalledWith(undefined);
        expect(mockSaveAs).toHaveBeenCalledWith(expect.any(Blob), "resume_backup.json");
    });

    it("バックアップが失敗した場合、isErrorがtrueになること", async () => {
        vi.mocked(protectedApiClient.get).mockRejectedValueOnce(new Error("Network Error"));

        const { result } = renderHook(() => useBackupResume(), { wrapper });

        act(() => {
            result.current.mutate("resume-1");
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        expect(mockSaveAs).not.toHaveBeenCalled();
    });
});
