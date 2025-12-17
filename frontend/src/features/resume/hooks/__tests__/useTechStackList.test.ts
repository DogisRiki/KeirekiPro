import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { TechStack } from "@/features/resume";
import { useTechStackList } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useTechStackList", () => {
    const wrapper = createQueryWrapper();

    const mockTechStack: TechStack = {
        frontend: {
            languages: ["TypeScript", "JavaScript"],
            frameworks: ["React", "Vue"],
            libraries: [],
            buildTools: [],
            packageManagers: ["npm", "yarn"],
            linters: ["ESLint"],
            formatters: ["Prettier"],
            testingTools: ["Jest", "Vitest"],
        },
        backend: {
            languages: ["Go", "Python"],
            frameworks: [],
            libraries: [],
            buildTools: [],
            packageManagers: [],
            linters: [],
            formatters: [],
            testingTools: [],
            ormTools: [],
            auth: [],
        },
        infrastructure: {
            clouds: ["AWS", "GCP"],
            operatingSystems: [],
            containers: ["Docker"],
            databases: ["PostgreSQL"],
            webServers: [],
            ciCdTools: [],
            iacTools: [],
            monitoringTools: [],
            loggingTools: [],
        },
        tools: {
            sourceControls: ["Git"],
            projectManagements: [],
            communicationTools: [],
            documentationTools: [],
            apiDevelopmentTools: [],
            designTools: [],
            editors: ["VSCode"],
            developmentEnvironments: [],
        },
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("成功時はエラーストアをクリアし、データが取得されること", async () => {
        const mockResponse = { status: 200, data: mockTechStack } as AxiosResponse<TechStack>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useTechStackList(), { wrapper });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();
        expect(result.current.data).toEqual(mockTechStack);
    });
});
