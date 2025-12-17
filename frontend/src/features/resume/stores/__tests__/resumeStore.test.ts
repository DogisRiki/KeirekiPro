import type { Resume } from "@/features/resume";
import { useResumeStore } from "@/features/resume";

describe("useResumeStore", () => {
    const mockResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [
            {
                id: "career-1",
                companyName: "株式会社テスト",
                startDate: "2020-04",
                endDate: "2023-12",
                active: false,
            },
            {
                id: "career-2",
                companyName: "株式会社サンプル",
                startDate: "2024-01",
                endDate: null,
                active: true,
            },
        ],
        projects: [
            {
                id: "project-1",
                companyName: "株式会社テスト",
                startDate: "2020-04-01",
                endDate: "2021-03-31",
                active: false,
                name: "テストプロジェクト",
                overview: "テストプロジェクトの概要",
                teamComp: "5名",
                role: "バックエンドエンジニア",
                achievement: "パフォーマンス改善",
                process: {
                    requirements: true,
                    basicDesign: true,
                    detailedDesign: true,
                    implementation: true,
                    integrationTest: true,
                    systemTest: false,
                    maintenance: false,
                },
                techStack: {
                    frontend: {
                        languages: ["TypeScript"],
                        frameworks: ["React"],
                        libraries: [],
                        buildTools: [],
                        packageManagers: ["npm"],
                        linters: ["ESLint"],
                        formatters: ["Prettier"],
                        testingTools: ["Jest"],
                    },
                    backend: {
                        languages: ["Go"],
                        frameworks: ["Echo"],
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
                        clouds: ["AWS"],
                        operatingSystems: ["Linux"],
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
                },
            },
        ],
        certifications: [
            {
                id: "cert-1",
                name: "基本情報技術者",
                date: "2020-06-01",
            },
        ],
        portfolios: [
            {
                id: "portfolio-1",
                name: "個人ブログ",
                overview: "技術ブログ",
                techStack: "Next.js, Vercel",
                link: "https://example.com/blog",
            },
        ],
        socialLinks: [
            {
                id: "social-1",
                name: "GitHub",
                link: "https://github.com/example",
            },
        ],
        selfPromotions: [
            {
                id: "pr-1",
                title: "技術への取り組み",
                content: "新しい技術を積極的に学んでいます。",
            },
        ],
    };

    beforeEach(() => {
        // テスト前にストアをリセット
        useResumeStore.getState().clearResume();
    });

    describe("初期状態", () => {
        it("初期状態でactiveSectionがbasicInfo、resumeがnull、isDirtyがfalseであること", () => {
            const { activeSection, resume, isDirty, activeEntryId, dirtyEntryIds } = useResumeStore.getState();
            expect(activeSection).toBe("basicInfo");
            expect(resume).toBeNull();
            expect(isDirty).toBe(false);
            expect(activeEntryId).toBeNull();
            expect(dirtyEntryIds.size).toBe(0);
        });

        it("初期状態でactiveEntryIdsBySectionがすべてnullであること", () => {
            const { activeEntryIdsBySection } = useResumeStore.getState();
            expect(activeEntryIdsBySection.career).toBeNull();
            expect(activeEntryIdsBySection.project).toBeNull();
            expect(activeEntryIdsBySection.certification).toBeNull();
            expect(activeEntryIdsBySection.portfolio).toBeNull();
            expect(activeEntryIdsBySection.socialLink).toBeNull();
            expect(activeEntryIdsBySection.selfPromotion).toBeNull();
        });
    });

    describe("setActiveSection", () => {
        it("setActiveSectionでセクションを切り替えられること", () => {
            useResumeStore.getState().setActiveSection("career");

            const { activeSection } = useResumeStore.getState();
            expect(activeSection).toBe("career");
        });

        it("セクション切り替え時にactiveEntryIdが更新されること", () => {
            // careerセクションにエントリーIDを設定
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");
            expect(useResumeStore.getState().activeEntryId).toBe("career-1");

            // projectセクションに切り替え
            useResumeStore.getState().setActiveSection("project");
            expect(useResumeStore.getState().activeEntryId).toBeNull();

            // careerセクションに戻ると以前のエントリーIDが復元される
            useResumeStore.getState().setActiveSection("career");
            expect(useResumeStore.getState().activeEntryId).toBe("career-1");
        });

        it("basicInfoセクションではactiveEntryIdがnullになること", () => {
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");

            useResumeStore.getState().setActiveSection("basicInfo");
            expect(useResumeStore.getState().activeEntryId).toBeNull();
        });
    });

    describe("setActiveEntryId", () => {
        it("setActiveEntryIdでエントリーIDを設定できること", () => {
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");

            const { activeEntryId, activeEntryIdsBySection } = useResumeStore.getState();
            expect(activeEntryId).toBe("career-1");
            expect(activeEntryIdsBySection.career).toBe("career-1");
        });

        it("basicInfoセクションではsetActiveEntryIdが無視されること", () => {
            useResumeStore.getState().setActiveSection("basicInfo");
            useResumeStore.getState().setActiveEntryId("some-id");

            const { activeEntryId } = useResumeStore.getState();
            expect(activeEntryId).toBeNull();
        });

        it("異なるセクションごとに異なるエントリーIDを保持できること", () => {
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");

            useResumeStore.getState().setActiveSection("project");
            useResumeStore.getState().setActiveEntryId("project-1");

            useResumeStore.getState().setActiveSection("certification");
            useResumeStore.getState().setActiveEntryId("cert-1");

            const { activeEntryIdsBySection } = useResumeStore.getState();
            expect(activeEntryIdsBySection.career).toBe("career-1");
            expect(activeEntryIdsBySection.project).toBe("project-1");
            expect(activeEntryIdsBySection.certification).toBe("cert-1");
        });
    });

    describe("setResume", () => {
        it("setResumeで職務経歴書を設定しisDirtyがfalseになること", () => {
            useResumeStore.getState().setResume(mockResume);

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume).toEqual(mockResume);
            expect(isDirty).toBe(false);
        });

        it("isDirtyがtrueの状態でsetResumeを呼ぶとisDirtyがfalseになること", () => {
            useResumeStore.getState().setResume(mockResume);
            useResumeStore.getState().updateResume({ resumeName: "更新された職務経歴書" });
            expect(useResumeStore.getState().isDirty).toBe(true);

            useResumeStore.getState().setResume(mockResume);
            expect(useResumeStore.getState().isDirty).toBe(false);
        });
    });

    describe("initializeResume", () => {
        it("initializeResumeで職務経歴書と状態を初期化できること", () => {
            // 先に状態を変更しておく
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");

            // 初期化
            useResumeStore.getState().initializeResume(mockResume);

            const { resume, isDirty, activeSection, activeEntryId, dirtyEntryIds } = useResumeStore.getState();
            expect(resume).toEqual(mockResume);
            expect(isDirty).toBe(false);
            expect(activeSection).toBe("basicInfo");
            expect(activeEntryId).toBeNull();
            expect(dirtyEntryIds.size).toBe(0);
        });

        it("initializeResumeでactiveEntryIdsBySectionがリセットされること", () => {
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");

            useResumeStore.getState().initializeResume(mockResume);

            const { activeEntryIdsBySection } = useResumeStore.getState();
            expect(activeEntryIdsBySection.career).toBeNull();
            expect(activeEntryIdsBySection.project).toBeNull();
        });
    });

    describe("updateResume", () => {
        it("updateResumeで職務経歴書を部分更新できること", () => {
            useResumeStore.getState().setResume(mockResume);

            useResumeStore.getState().updateResume({
                resumeName: "更新された職務経歴書",
                lastName: "鈴木",
            });

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume?.resumeName).toBe("更新された職務経歴書");
            expect(resume?.lastName).toBe("鈴木");
            expect(resume?.firstName).toBe("太郎"); // 変更されていない
            expect(isDirty).toBe(true);
        });

        it("resumeがnullの場合updateResumeを呼んでもresumeはnullで、isDirtyがtrueになること", () => {
            useResumeStore.getState().updateResume({ resumeName: "テスト" });

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume).toBeNull();
            expect(isDirty).toBe(true);
        });
    });

    describe("updateResumeFromServer", () => {
        it("updateResumeFromServerで職務経歴書を部分更新でき、isDirtyは変更されないこと", () => {
            useResumeStore.getState().setResume(mockResume);

            // ローカル編集でdirtyにしておく
            useResumeStore.getState().updateResume({ resumeName: "ローカル更新" });
            expect(useResumeStore.getState().isDirty).toBe(true);

            // サーバー更新（isDirtyは維持）
            useResumeStore.getState().updateResumeFromServer({ lastName: "佐藤" });

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume?.resumeName).toBe("ローカル更新");
            expect(resume?.lastName).toBe("佐藤");
            expect(isDirty).toBe(true);
        });

        it("resumeがnullの場合updateResumeFromServerを呼んでもresumeがnullのままで、isDirtyは変更されないこと", () => {
            expect(useResumeStore.getState().resume).toBeNull();
            expect(useResumeStore.getState().isDirty).toBe(false);

            useResumeStore.getState().updateResumeFromServer({ resumeName: "サーバー更新" });

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume).toBeNull();
            expect(isDirty).toBe(false);
        });
    });

    describe("updateSection", () => {
        it("updateSectionでセクションデータを更新できること", () => {
            useResumeStore.getState().setResume(mockResume);

            const newCareers = [
                {
                    id: "career-3",
                    companyName: "新しい会社",
                    startDate: "2024-06",
                    endDate: null,
                    active: true,
                },
            ];

            useResumeStore.getState().updateSection("careers", newCareers);

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume?.careers).toEqual(newCareers);
            expect(isDirty).toBe(true);
        });

        it("updateSectionで新規エントリーがdirtyEntryIdsに追加されること", () => {
            useResumeStore.getState().setResume(mockResume);

            const newCareers = [
                ...mockResume.careers,
                {
                    id: "career-new",
                    companyName: "新しい会社",
                    startDate: "2024-06",
                    endDate: null,
                    active: true,
                },
            ];

            useResumeStore.getState().updateSection("careers", newCareers);

            const { dirtyEntryIds } = useResumeStore.getState();
            expect(dirtyEntryIds.has("career-new")).toBe(true);
            expect(dirtyEntryIds.has("career-1")).toBe(false); // 既存のIDは追加されない
        });

        it("resumeがnullの場合updateSectionを呼んでもresumeがnullのままであること", () => {
            useResumeStore.getState().updateSection("careers", []);

            const { resume } = useResumeStore.getState();
            expect(resume).toBeNull();
        });
    });

    describe("updateEntry", () => {
        it("updateEntryで特定のエントリーを更新できること", () => {
            useResumeStore.getState().setResume(mockResume);

            useResumeStore.getState().updateEntry("careers", "career-1", {
                companyName: "更新された会社名",
            });

            const { resume, isDirty } = useResumeStore.getState();
            const updatedCareer = resume?.careers.find((c) => c.id === "career-1");
            expect(updatedCareer?.companyName).toBe("更新された会社名");
            expect(updatedCareer?.startDate).toBe("2020-04"); // 変更されていない
            expect(isDirty).toBe(true);
        });

        it("updateEntryでentryIdがdirtyEntryIdsに追加されること", () => {
            useResumeStore.getState().setResume(mockResume);

            useResumeStore.getState().updateEntry("careers", "career-1", {
                companyName: "更新された会社名",
            });

            const { dirtyEntryIds } = useResumeStore.getState();
            expect(dirtyEntryIds.has("career-1")).toBe(true);
        });

        it("存在しないエントリーIDを指定しても他のエントリーに影響しないこと", () => {
            useResumeStore.getState().setResume(mockResume);

            useResumeStore.getState().updateEntry("careers", "non-existent-id", {
                companyName: "存在しないID",
            });

            const { resume } = useResumeStore.getState();
            expect(resume?.careers).toEqual(mockResume.careers);
        });

        it("resumeがnullの場合updateEntryを呼んでもresumeがnullのままで、isDirtyは変更されないこと", () => {
            useResumeStore.getState().updateEntry("careers", "career-1", {
                companyName: "テスト",
            });

            const { resume, isDirty } = useResumeStore.getState();
            expect(resume).toBeNull();
            expect(isDirty).toBe(false);
        });
    });

    describe("removeEntry", () => {
        it("removeEntryで特定エントリーを削除でき、dirtyEntryIdsからも削除され、isDirtyは変更されないこと", () => {
            useResumeStore.getState().setResume(mockResume);

            // 一度dirtyにする
            useResumeStore.getState().updateEntry("careers", "career-1", { companyName: "更新" });
            expect(useResumeStore.getState().dirtyEntryIds.has("career-1")).toBe(true);
            expect(useResumeStore.getState().isDirty).toBe(true);

            // isDirtyをfalseに戻しておき、removeEntryが触らないことを確認
            useResumeStore.getState().setDirty(false);
            expect(useResumeStore.getState().isDirty).toBe(false);

            useResumeStore.getState().removeEntry("careers", "career-1");

            const { resume, dirtyEntryIds, isDirty } = useResumeStore.getState();
            expect(resume?.careers.find((c) => c.id === "career-1")).toBeUndefined();
            expect(resume?.careers.find((c) => c.id === "career-2")).toBeDefined();
            expect(dirtyEntryIds.has("career-1")).toBe(false);
            expect(isDirty).toBe(false);
        });

        it("resumeがnullの場合removeEntryを呼んでもresumeがnullのままであること", () => {
            useResumeStore.getState().removeEntry("careers", "career-1");
            expect(useResumeStore.getState().resume).toBeNull();
        });
    });

    describe("clearResume", () => {
        it("clearResumeですべての状態がリセットされること", () => {
            // 状態を変更
            useResumeStore.getState().setResume(mockResume);
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");
            useResumeStore.getState().updateResume({ resumeName: "更新" });

            // クリア
            useResumeStore.getState().clearResume();

            const { resume, activeSection, activeEntryId, isDirty, dirtyEntryIds, activeEntryIdsBySection } =
                useResumeStore.getState();
            expect(resume).toBeNull();
            expect(activeSection).toBe("basicInfo");
            expect(activeEntryId).toBeNull();
            expect(isDirty).toBe(false);
            expect(dirtyEntryIds.size).toBe(0);
            expect(activeEntryIdsBySection.career).toBeNull();
        });
    });

    describe("setDirty", () => {
        it("setDirtyでisDirty状態を設定できること", () => {
            useResumeStore.getState().setDirty(true);
            expect(useResumeStore.getState().isDirty).toBe(true);

            useResumeStore.getState().setDirty(false);
            expect(useResumeStore.getState().isDirty).toBe(false);
        });
    });

    describe("addDirtyEntryId / removeDirtyEntryId", () => {
        it("addDirtyEntryIdでdirtyEntryIdsに追加でき、isDirtyは変更されないこと", () => {
            expect(useResumeStore.getState().isDirty).toBe(false);
            expect(useResumeStore.getState().dirtyEntryIds.size).toBe(0);

            useResumeStore.getState().addDirtyEntryId("career-1");

            const { dirtyEntryIds, isDirty } = useResumeStore.getState();
            expect(dirtyEntryIds.has("career-1")).toBe(true);
            expect(isDirty).toBe(false);
        });

        it("removeDirtyEntryIdでdirtyEntryIdsから削除でき、isDirtyは変更されないこと", () => {
            useResumeStore.getState().addDirtyEntryId("career-1");
            useResumeStore.getState().addDirtyEntryId("career-2");

            useResumeStore.getState().removeDirtyEntryId("career-1");

            const { dirtyEntryIds, isDirty } = useResumeStore.getState();
            expect(dirtyEntryIds.has("career-1")).toBe(false);
            expect(dirtyEntryIds.has("career-2")).toBe(true);
            expect(isDirty).toBe(false);
        });
    });

    describe("clearDirtyEntryIds", () => {
        it("clearDirtyEntryIdsで指定したエントリーIDを削除できること", () => {
            useResumeStore.getState().setResume(mockResume);
            useResumeStore.getState().updateEntry("careers", "career-1", { companyName: "更新1" });
            useResumeStore.getState().updateEntry("careers", "career-2", { companyName: "更新2" });
            useResumeStore.getState().updateEntry("projects", "project-1", { name: "更新プロジェクト" });

            expect(useResumeStore.getState().dirtyEntryIds.has("career-1")).toBe(true);
            expect(useResumeStore.getState().dirtyEntryIds.has("career-2")).toBe(true);
            expect(useResumeStore.getState().dirtyEntryIds.has("project-1")).toBe(true);

            useResumeStore.getState().clearDirtyEntryIds(["career-1", "project-1"]);

            const { dirtyEntryIds } = useResumeStore.getState();
            expect(dirtyEntryIds.has("career-1")).toBe(false);
            expect(dirtyEntryIds.has("career-2")).toBe(true);
            expect(dirtyEntryIds.has("project-1")).toBe(false);
        });

        it("存在しないIDを指定してもエラーにならないこと", () => {
            useResumeStore.getState().setResume(mockResume);
            useResumeStore.getState().updateEntry("careers", "career-1", { companyName: "更新" });

            useResumeStore.getState().clearDirtyEntryIds(["non-existent-id"]);

            const { dirtyEntryIds } = useResumeStore.getState();
            expect(dirtyEntryIds.has("career-1")).toBe(true);
        });
    });

    describe("複合シナリオ", () => {
        it("セクション間を移動してもそれぞれのactiveEntryIdが保持されること", () => {
            useResumeStore.getState().setResume(mockResume);

            // careerセクションでエントリーを選択
            useResumeStore.getState().setActiveSection("career");
            useResumeStore.getState().setActiveEntryId("career-1");

            // projectセクションでエントリーを選択
            useResumeStore.getState().setActiveSection("project");
            useResumeStore.getState().setActiveEntryId("project-1");

            // certificationセクションでエントリーを選択
            useResumeStore.getState().setActiveSection("certification");
            useResumeStore.getState().setActiveEntryId("cert-1");

            // 各セクションに戻ってもエントリーIDが保持されている
            useResumeStore.getState().setActiveSection("career");
            expect(useResumeStore.getState().activeEntryId).toBe("career-1");

            useResumeStore.getState().setActiveSection("project");
            expect(useResumeStore.getState().activeEntryId).toBe("project-1");

            useResumeStore.getState().setActiveSection("certification");
            expect(useResumeStore.getState().activeEntryId).toBe("cert-1");
        });

        it("複数のセクションを更新した場合すべての変更が反映されること", () => {
            useResumeStore.getState().setResume(mockResume);

            // 複数のセクションを更新
            useResumeStore.getState().updateEntry("careers", "career-1", { companyName: "更新会社" });
            useResumeStore.getState().updateEntry("projects", "project-1", { name: "更新プロジェクト" });
            useResumeStore.getState().updateEntry("certifications", "cert-1", { name: "更新資格" });

            const { resume, dirtyEntryIds } = useResumeStore.getState();
            expect(resume?.careers.find((c) => c.id === "career-1")?.companyName).toBe("更新会社");
            expect(resume?.projects.find((p) => p.id === "project-1")?.name).toBe("更新プロジェクト");
            expect(resume?.certifications.find((c) => c.id === "cert-1")?.name).toBe("更新資格");
            expect(dirtyEntryIds.size).toBe(3);
        });

        it("全セクションタイプに対してupdateSectionが正しく動作すること", () => {
            useResumeStore.getState().setResume(mockResume);

            const sectionTests: Array<{
                section: "careers" | "projects" | "certifications" | "portfolios" | "socialLinks" | "selfPromotions";
                data: unknown[];
            }> = [
                { section: "careers", data: [] },
                { section: "projects", data: [] },
                { section: "certifications", data: [] },
                { section: "portfolios", data: [] },
                { section: "socialLinks", data: [] },
                { section: "selfPromotions", data: [] },
            ];

            for (const { section, data } of sectionTests) {
                useResumeStore.getState().updateSection(section, data as never);
                expect(useResumeStore.getState().resume?.[section]).toEqual(data);
            }
        });
    });
});
