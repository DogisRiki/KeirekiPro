import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useResumeStore, useUpdatePortfolio } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useUpdatePortfolio", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}portfolio-temp-99`;

    const localResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [],
        projects: [],
        certifications: [],
        portfolios: [
            {
                id: "portfolio-1",
                name: "ローカル（更新対象・dirty）",
                overview: "ローカル概要1",
                techStack: "React",
                link: "https://example.com/p1",
            },
            {
                id: "portfolio-3",
                name: "ローカル（別dirty）",
                overview: "ローカル概要3",
                techStack: "Vue",
                link: "https://example.com/p3",
            },
            {
                id: localOnlyTempId,
                name: "ローカルのみ（temp）",
                overview: "ローカルのみ概要",
                techStack: "Svelte",
                link: "https://example.com/temp",
            },
        ],
        socialLinks: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.put).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、portfoliosをマージしてストア更新・dirty解除・通知が実行されること", async () => {
        const portfolioId = "portfolio-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(portfolioId);
        useResumeStore.getState().addDirtyEntryId("portfolio-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            portfolios: [
                {
                    id: "portfolio-1",
                    name: "サーバー（更新後）",
                    overview: "サーバー概要1",
                    techStack: "React",
                    link: "https://example.com/server1",
                },
                {
                    id: "portfolio-2",
                    name: "サーバー（別エントリー）",
                    overview: "サーバー概要2",
                    techStack: "Next.js",
                    link: "https://example.com/server2",
                },
                {
                    id: "portfolio-3",
                    name: "サーバー（dirtyで上書きされる想定）",
                    overview: "サーバー概要3",
                    techStack: "Vue",
                    link: "https://example.com/server3",
                },
            ],
        };

        const mockResponse = { status: 200, data: serverResume };
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdatePortfolio("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                portfolioId,
                payload: {
                    name: "ローカル（更新対象・dirty）",
                    overview: "ローカル概要1",
                    techStack: "React",
                    link: "https://example.com/p1",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server portfoliosをベースにdirtyなportfolio-3はローカルデータで上書き
        // - 更新対象（portfolioId=portfolio-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedPortfolios = [
            localResume.portfolios.find((p) => p.id === localOnlyTempId)!,
            serverResume.portfolios.find((p) => p.id === "portfolio-1")!, // server優先
            serverResume.portfolios.find((p) => p.id === "portfolio-2")!,
            localResume.portfolios.find((p) => p.id === "portfolio-3")!, // dirtyなのでローカル優先
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, portfolioId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, portfolioId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            portfolios: expectedPortfolios,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(portfolioId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "ポートフォリオを更新しました。",
            "success",
        );
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        const portfolioId = "portfolio-1";

        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(portfolioId);

        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                name: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.put).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useUpdatePortfolio("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                portfolioId,
                payload: {
                    name: "",
                    overview: "ローカル概要1",
                    techStack: "React",
                    link: "https://example.com/p1",
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(portfolioId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(portfolioId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
