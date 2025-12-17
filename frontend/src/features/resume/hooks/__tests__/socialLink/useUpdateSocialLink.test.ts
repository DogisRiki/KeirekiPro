import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useResumeStore, useUpdateSocialLink } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useUpdateSocialLink", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}social-link-temp-99`;

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
        socialLinks: [
            {
                id: "social-link-1",
                name: "ローカル（更新対象・dirty）",
                link: "https://example.com/local-target",
            },
            {
                id: "social-link-3",
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
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、socialLinksをマージしてストア更新・dirty解除・通知が実行されること", async () => {
        const socialLinkId = "social-link-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(socialLinkId);
        useResumeStore.getState().addDirtyEntryId("social-link-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            socialLinks: [
                {
                    id: "social-link-1",
                    name: "サーバー（更新後）",
                    link: "https://example.com/server-updated",
                },
                {
                    id: "social-link-2",
                    name: "サーバー（別エントリー）",
                    link: "https://example.com/server-other",
                },
                {
                    id: "social-link-3",
                    name: "サーバー（dirtyで上書きされる想定）",
                    link: "https://example.com/server-overwritten",
                },
            ],
        };

        const mockResponse = { status: 200, data: serverResume };
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateSocialLink("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                socialLinkId,
                payload: {
                    name: localResume.socialLinks.find((s) => s.id === socialLinkId)!.name,
                    link: localResume.socialLinks.find((s) => s.id === socialLinkId)!.link,
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server socialLinksをベースにdirtyな social-link-3はローカルデータで上書き
        // - 更新対象（socialLinkId=social-link-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedSocialLinks = [
            localResume.socialLinks.find((s) => s.id === localOnlyTempId)!,
            serverResume.socialLinks.find((s) => s.id === "social-link-1")!, // server優先
            serverResume.socialLinks.find((s) => s.id === "social-link-2")!,
            localResume.socialLinks.find((s) => s.id === "social-link-3")!, // dirtyなのでローカル優先
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, socialLinkId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, socialLinkId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            socialLinks: expectedSocialLinks,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(socialLinkId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("SNSを更新しました。", "success");
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        const socialLinkId = "social-link-1";

        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(socialLinkId);

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

        const { result } = renderHook(() => useUpdateSocialLink("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                socialLinkId,
                payload: {
                    name: "",
                    link: localResume.socialLinks.find((s) => s.id === socialLinkId)!.link,
                },
            });
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(socialLinkId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(socialLinkId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
