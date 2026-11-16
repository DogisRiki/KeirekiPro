import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { buildPayloadForEntry, TEMP_ID_PREFIX, useResumeStore, useUpdateSnsPlatform } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useUpdateSnsPlatform", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}sns-platform-temp-99`;

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
        portfolios: [],
        snsPlatforms: [
            {
                id: "sns-platform-1",
                name: "ローカル（更新対象・dirty）",
                link: "https://example.com/local-target",
            },
            {
                id: "sns-platform-3",
                name: "ローカル（別dirty）",
                link: "https://example.com/local-other-dirty",
            },
            {
                id: localOnlyTempId,
                name: "ローカルのみ（temp）",
                link: "https://example.com/local-only-temp",
            },
        ],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.put).mockReset();
        vi.mocked(protectedApiClient.get).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、snsPlatformsをマージしてストア更新・dirty解除・通知が実行されること", async () => {
        const snsPlatformId = "sns-platform-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(snsPlatformId);
        useResumeStore.getState().addDirtyEntryId("sns-platform-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            snsPlatforms: [
                {
                    id: "sns-platform-1",
                    name: "サーバー（更新後）",
                    link: "https://example.com/server-updated",
                },
                {
                    id: "sns-platform-2",
                    name: "サーバー（別エントリー）",
                    link: "https://example.com/server-other",
                },
                {
                    id: "sns-platform-3",
                    name: "サーバー（dirtyで上書きされる想定）",
                    link: "https://example.com/server-overwritten",
                },
            ],
        };

        const mockResponse = { status: 200, data: serverResume };
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateSnsPlatform("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                snsPlatformId,
                payload: {
                    name: localResume.snsPlatforms.find((s) => s.id === snsPlatformId)!.name,
                    link: localResume.snsPlatforms.find((s) => s.id === snsPlatformId)!.link,
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server snsPlatformsをベースにdirtyな sns-platform-3はローカルデータで上書き
        // - 更新対象（snsPlatformId=sns-platform-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedSnsPlatforms = [
            localResume.snsPlatforms.find((s) => s.id === localOnlyTempId)!,
            serverResume.snsPlatforms.find((s) => s.id === "sns-platform-1")!, // server優先
            serverResume.snsPlatforms.find((s) => s.id === "sns-platform-2")!,
            localResume.snsPlatforms.find((s) => s.id === "sns-platform-3")!, // dirtyなのでローカル優先
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, snsPlatformId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, snsPlatformId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            snsPlatforms: expectedSnsPlatforms,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(snsPlatformId);
        expect(useResumeStore.getState().dirtyEntryIds.has(snsPlatformId)).toBe(false);
        expect(useResumeStore.getState().isDirty).toBe(true); // ほかのエントリーが未保存のまま残る
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("SNSを更新しました。", "success");
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        const snsPlatformId = "sns-platform-1";

        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(snsPlatformId);

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

        const { result } = renderHook(() => useUpdateSnsPlatform("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                snsPlatformId,
                payload: {
                    name: "",
                    link: localResume.snsPlatforms.find((s) => s.id === snsPlatformId)!.link,
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(snsPlatformId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(snsPlatformId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().removeDirtyEntryId).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });

    it("SNSプラットフォーム不存在404の場合、空セクションが省略された詳細レスポンスでストアを同期すること", async () => {
        const snsPlatformId = "sns-platform-1";
        useResumeStore.getState().setResume({ ...localResume, snsPlatforms: [localResume.snsPlatforms[0]] });
        useResumeStore.getState().setActiveSection("snsPlatform");
        useResumeStore.getState().setActiveEntryId(snsPlatformId);

        vi.mocked(protectedApiClient.put).mockRejectedValueOnce({
            isAxiosError: true,
            response: { status: 404, data: { message: "対象のSNSプラットフォームが存在しません。", errors: {} } },
        });
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce({
            data: {
                id: localResume.id,
                resumeName: localResume.resumeName,
                date: localResume.date,
                createdAt: localResume.createdAt,
                updatedAt: localResume.updatedAt,
            },
        });

        const { result } = renderHook(() => useUpdateSnsPlatform("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                snsPlatformId,
                payload: { name: "SNS", link: "https://example.com" },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));
        await waitFor(() => expect(useResumeStore.getState().resume?.snsPlatforms).toEqual([]));
        expect(protectedApiClient.get).toHaveBeenCalledWith("/resumes/resume-1");
        expect(useResumeStore.getState().activeEntryId).toBeNull();
    });

    it("保存中に打った文字は、保存が終わったあとも欄に残り、未保存の変更として扱われること", async () => {
        const entry = localResume.snsPlatforms[0];
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(entry.id);

        let resolveSave: (value: unknown) => void = () => undefined;
        vi.mocked(protectedApiClient.put).mockReturnValueOnce(
            new Promise((resolve) => {
                resolveSave = resolve;
            }),
        );

        const { result } = renderHook(() => useUpdateSnsPlatform("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({ snsPlatformId: entry.id, payload: buildPayloadForEntry("snsPlatform", entry) });
        });
        await waitFor(() => expect(protectedApiClient.put).toHaveBeenCalled());

        // 保存が終わる前に文字を打つ
        act(() => {
            useResumeStore.getState().updateEntry("snsPlatforms", entry.id, { name: "保存中に打った文字" });
        });
        await act(async () => {
            resolveSave({ status: 200, data: { ...localResume, updatedAt: "2024-02-10T00:00:00.000Z" } });
        });
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        const { resume, dirtyEntryIds, isDirty } = useResumeStore.getState();
        expect(resume?.snsPlatforms.find((e) => e.id === entry.id)?.name).toBe("保存中に打った文字");
        expect(resume?.updatedAt).toBe("2024-02-10T00:00:00.000Z");
        expect(dirtyEntryIds.has(entry.id)).toBe(true);
        expect(isDirty).toBe(true);
    });
});
