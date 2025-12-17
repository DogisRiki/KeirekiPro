import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useCreateSocialLink, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useCreateSocialLink", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}social-link-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}social-link-temp-2`;

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
                id: tempId,
                name: "一時SNS",
                link: "https://example.com/temp",
            },
            {
                id: "social-link-1",
                name: "ローカル（dirty）SNS名",
                link: "https://example.com/local-dirty",
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
        vi.mocked(protectedApiClient.post).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
    });

    it("成功時はsocialLinksをマージしてupdateResumeFromServerが呼ばれ、activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("socialLink");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("social-link-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            socialLinks: [
                {
                    id: "social-link-1",
                    name: "サーバーSNS名（上書きされる想定）",
                    link: "https://example.com/server-overwritten",
                },
                {
                    id: "social-link-2",
                    name: "新規作成されたSNS",
                    link: "https://example.com/new",
                },
            ],
        };

        const mockResponse = { status: 201, data: serverResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateSocialLink("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    name: "一時SNS",
                    link: "https://example.com/temp",
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // socialLinksのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server socialLinksをベースに、dirtyなsocial-link-1はローカルデータで上書き
        const expectedSocialLinks = [
            localResume.socialLinks.find((s) => s.id === localOnlyTempId)!,
            localResume.socialLinks.find((s) => s.id === "social-link-1")!, // dirtyなのでローカルが優先
            serverResume.socialLinks.find((s) => s.id === "social-link-2")!,
        ];

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            socialLinks: expectedSocialLinks,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("social-link-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("SNSを作成しました。", "success");
    });
});
