import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { buildPayloadForEntry, TEMP_ID_PREFIX, useCreateSelfPromotion, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useCreateSelfPromotion", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}self-promotion-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}self-promotion-temp-2`;

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
        snsPlatforms: [],
        selfPromotions: [
            {
                id: tempId,
                title: "一時自己PR",
                content: "一時自己PR本文",
            },
            {
                id: "self-promotion-1",
                title: "ローカル（dirty）タイトル",
                content: "ローカル（dirty）本文",
            },
            {
                id: localOnlyTempId,
                title: "ローカルのみ（temp）タイトル",
                content: "ローカルのみ（temp）本文",
            },
        ],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、selfPromotionsをマージしてストア更新・activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("selfPromotion");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("self-promotion-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            selfPromotions: [
                {
                    id: "self-promotion-1",
                    title: "サーバータイトル（上書きされる想定）",
                    content: "サーバー本文（上書きされる想定）",
                },
                {
                    id: "self-promotion-2",
                    title: "新規作成された自己PR",
                    content: "新規作成本文",
                },
            ],
        };

        const mockResponse = { status: 201, data: serverResume };
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    title: "一時自己PR",
                    content: "一時自己PR本文",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // selfPromotionsのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server selfPromotionsをベースに、dirtyなself-promotion-1はローカルデータで上書き
        const expectedSelfPromotions = [
            localResume.selfPromotions.find((s) => s.id === localOnlyTempId)!,
            localResume.selfPromotions.find((s) => s.id === "self-promotion-1")!, // dirtyなのでローカルが優先
            serverResume.selfPromotions.find((s) => s.id === "self-promotion-2")!,
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, tempId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, tempId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            selfPromotions: expectedSelfPromotions,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("self-promotion-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().dirtyEntryIds.has(tempId)).toBe(false);
        expect(useResumeStore.getState().isDirty).toBe(true); // ほかのエントリーが未保存のまま残る
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "自己PRを作成しました。",
            "success",
        );
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("selfPromotion");
        useResumeStore.getState().setActiveEntryId(tempId);

        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                title: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.post).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useCreateSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    title: "",
                    content: "一時自己PR本文",
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(tempId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(tempId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().removeDirtyEntryId).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
    it("保存中に打った文字は、保存が終わったあとも作成されたエントリーの欄に残り、未保存の変更として扱われること", async () => {
        const entry = localResume.selfPromotions.find((e) => e.id === tempId)!;
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("selfPromotion");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);

        let resolveSave: (value: unknown) => void = () => undefined;
        vi.mocked(protectedApiClient.post).mockReturnValueOnce(
            new Promise((resolve) => {
                resolveSave = resolve;
            }),
        );

        const { result } = renderHook(() => useCreateSelfPromotion("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({ tempId, payload: buildPayloadForEntry("selfPromotion", entry) });
        });
        await waitFor(() => expect(protectedApiClient.post).toHaveBeenCalled());

        // 保存が終わる前に文字を打つ
        act(() => {
            useResumeStore.getState().updateEntry("selfPromotions", tempId, { title: "保存中に打った文字" });
        });
        await act(async () => {
            resolveSave({
                status: 201,
                data: {
                    ...localResume,
                    updatedAt: "2024-02-10T00:00:00.000Z",
                    selfPromotions: [{ ...entry, id: "self-promotion-new" }],
                },
            });
        });
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        const { resume, dirtyEntryIds, activeEntryId, isDirty } = useResumeStore.getState();
        expect(resume?.selfPromotions.find((e) => e.id === "self-promotion-new")?.title).toBe("保存中に打った文字");
        expect(resume?.selfPromotions.some((e) => e.id === tempId)).toBe(false);
        expect(resume?.updatedAt).toBe("2024-02-10T00:00:00.000Z");
        expect(activeEntryId).toBe("self-promotion-new");
        expect(dirtyEntryIds.has("self-promotion-new")).toBe(true);
        expect(dirtyEntryIds.has(tempId)).toBe(false);
        expect(isDirty).toBe(true);
    });
});
