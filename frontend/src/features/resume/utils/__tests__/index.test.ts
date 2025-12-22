import type { SectionName } from "@/features/resume";
import {
    TEMP_ID_PREFIX,
    buildPayloadForEntry,
    createCurrentSection,
    getApiId,
    getEntryText,
    getResumeKey,
    isTempId,
} from "@/features/resume";

describe("getEntryText", () => {
    describe("career", () => {
        it("会社名と期間を返すこと", () => {
            const entry = {
                companyName: "株式会社テスト",
                startDate: "2020-04",
                endDate: "2023-12",
                active: false,
            };

            const result = getEntryText("career", entry);

            expect(result).toEqual({
                primary: "株式会社テスト",
                secondary: "2020/04 - 2023/12",
            });
        });

        it("activeがtrueの場合、終了日が「現在」になること", () => {
            const entry = {
                companyName: "株式会社テスト",
                startDate: "2020-04",
                endDate: null,
                active: true,
            };

            const result = getEntryText("career", entry);

            expect(result).toEqual({
                primary: "株式会社テスト",
                secondary: "2020/04 - 現在",
            });
        });
    });

    describe("project", () => {
        it("プロジェクト名と期間を返すこと", () => {
            const entry = {
                name: "テストプロジェクト",
                startDate: "2020-04-01",
                endDate: "2021-03-31",
                active: false,
            };

            const result = getEntryText("project", entry);

            expect(result).toEqual({
                primary: "テストプロジェクト",
                secondary: "2020/04 - 2021/03",
            });
        });

        it("activeがtrueの場合、終了日が「現在」になること", () => {
            const entry = {
                name: "テストプロジェクト",
                startDate: "2020-04-01",
                endDate: null,
                active: true,
            };

            const result = getEntryText("project", entry);

            expect(result).toEqual({
                primary: "テストプロジェクト",
                secondary: "2020/04 - 現在",
            });
        });
    });

    describe("certification", () => {
        it("資格名と取得日を返すこと", () => {
            const entry = {
                name: "基本情報技術者",
                date: "2020-06-01",
            };

            const result = getEntryText("certification", entry);

            expect(result).toEqual({
                primary: "基本情報技術者",
                secondary: "2020/06",
            });
        });
    });

    describe("portfolio", () => {
        it("ポートフォリオ名とリンクを返すこと", () => {
            const entry = {
                name: "個人ブログ",
                link: "https://example.com/blog",
            };

            const result = getEntryText("portfolio", entry);

            expect(result).toEqual({
                primary: "個人ブログ",
                secondary: "https://example.com/blog",
            });
        });
    });

    describe("snsPlatform", () => {
        it("SNS名とリンクを返すこと", () => {
            const entry = {
                name: "GitHub",
                link: "https://github.com/example",
            };

            const result = getEntryText("snsPlatform", entry);

            expect(result).toEqual({
                primary: "GitHub",
                secondary: "https://github.com/example",
            });
        });
    });

    describe("selfPromotion", () => {
        it("タイトルと内容を返すこと", () => {
            const entry = {
                title: "技術への取り組み",
                content: "新しい技術を積極的に学んでいます。",
            };

            const result = getEntryText("selfPromotion", entry);

            expect(result).toEqual({
                primary: "技術への取り組み",
                secondary: "新しい技術を積極的に学んでいます。",
            });
        });
    });

    describe("basicInfo", () => {
        it("nullを返すこと", () => {
            const entry = {};

            const result = getEntryText("basicInfo", entry);

            expect(result).toBeNull();
        });
    });
});

describe("getResumeKey", () => {
    it.each([
        ["career", "careers"],
        ["project", "projects"],
        ["certification", "certifications"],
        ["portfolio", "portfolios"],
        ["snsPlatform", "snsPlatforms"],
        ["selfPromotion", "selfPromotions"],
    ] as const)("セクション名「%s」に対して「%s」を返すこと", (sectionName, expectedKey) => {
        const result = getResumeKey(sectionName);
        expect(result).toBe(expectedKey);
    });

    it("basicInfoの場合はundefinedを返すこと", () => {
        const result = getResumeKey("basicInfo");
        expect(result).toBeUndefined();
    });
});

describe("isTempId", () => {
    it("一時IDプレフィックスで始まるIDの場合trueを返すこと", () => {
        const tempId = `${TEMP_ID_PREFIX}12345`;

        const result = isTempId(tempId);

        expect(result).toBe(true);
    });

    it("通常のIDの場合falseを返すこと", () => {
        const normalId = "uuid-12345-abcde";

        const result = isTempId(normalId);

        expect(result).toBe(false);
    });

    it("nullの場合trueを返すこと", () => {
        const result = isTempId(null);

        expect(result).toBe(true);
    });

    it("undefinedの場合trueを返すこと", () => {
        const result = isTempId(undefined);

        expect(result).toBe(true);
    });

    it("空文字の場合trueを返すこと", () => {
        const result = isTempId("");

        expect(result).toBe(true);
    });
});

describe("getApiId", () => {
    it("通常のIDの場合そのまま返すこと", () => {
        const normalId = "uuid-12345-abcde";

        const result = getApiId(normalId);

        expect(result).toBe(normalId);
    });

    it("一時IDの場合nullを返すこと", () => {
        const tempId = `${TEMP_ID_PREFIX}12345`;

        const result = getApiId(tempId);

        expect(result).toBeNull();
    });

    it("nullの場合nullを返すこと", () => {
        const result = getApiId(null);

        expect(result).toBeNull();
    });

    it("undefinedの場合nullを返すこと", () => {
        const result = getApiId(undefined);

        expect(result).toBeNull();
    });

    it("空文字の場合nullを返すこと", () => {
        const result = getApiId("");

        expect(result).toBeNull();
    });
});

describe("buildPayloadForEntry", () => {
    it("careerの場合、API送信用のペイロードを返すこと", () => {
        const entry = {
            id: "career-1",
            companyName: "株式会社テスト",
            startDate: "2020-04",
            endDate: "2023-12",
            active: false,
            // 余計なフィールドがあっても無視されることを確認
            extra: "ignored",
        };

        const result = buildPayloadForEntry("career", entry);

        expect(result).toEqual({
            companyName: "株式会社テスト",
            startDate: "2020-04",
            endDate: "2023-12",
            isActive: false,
        });
        expect(result).not.toHaveProperty("id");
        expect(result).not.toHaveProperty("active");
        expect(result).not.toHaveProperty("extra");
    });

    it("projectの場合、process/techStackをフラット化したペイロードを返すこと", () => {
        const entry = {
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
                    libraries: ["Redux"],
                    buildTools: ["Vite"],
                    packageManagers: ["npm"],
                    linters: ["ESLint"],
                    formatters: ["Prettier"],
                    testingTools: ["Jest"],
                },
                backend: {
                    languages: ["Go"],
                    frameworks: ["Echo"],
                    libraries: ["sqlx"],
                    buildTools: ["Go build"],
                    packageManagers: ["go mod"],
                    linters: ["golangci-lint"],
                    formatters: ["gofmt"],
                    testingTools: ["testing"],
                    ormTools: ["GORM"],
                    auth: ["JWT"],
                },
                infrastructure: {
                    clouds: ["AWS"],
                    operatingSystems: ["Linux"],
                    containers: ["Docker"],
                    databases: ["PostgreSQL"],
                    webServers: ["Nginx"],
                    ciCdTools: ["GitHub Actions"],
                    iacTools: ["Terraform"],
                    monitoringTools: ["CloudWatch"],
                    loggingTools: ["CloudWatch Logs"],
                },
                tools: {
                    sourceControls: ["Git"],
                    projectManagements: ["Jira"],
                    communicationTools: ["Slack"],
                    documentationTools: ["Confluence"],
                    apiDevelopmentTools: ["Postman"],
                    designTools: ["Figma"],
                    editors: ["VSCode"],
                    developmentEnvironments: ["Docker Desktop"],
                },
            },
        };

        const result = buildPayloadForEntry("project", entry);

        expect(result).toEqual({
            companyName: "株式会社テスト",
            startDate: "2020-04-01",
            endDate: "2021-03-31",
            isActive: false,
            name: "テストプロジェクト",
            overview: "テストプロジェクトの概要",
            teamComp: "5名",
            role: "バックエンドエンジニア",
            achievement: "パフォーマンス改善",
            requirements: true,
            basicDesign: true,
            detailedDesign: true,
            implementation: true,
            integrationTest: true,
            systemTest: false,
            maintenance: false,
            frontendLanguages: ["TypeScript"],
            frontendFrameworks: ["React"],
            frontendLibraries: ["Redux"],
            frontendBuildTools: ["Vite"],
            frontendPackageManagers: ["npm"],
            frontendLinters: ["ESLint"],
            frontendFormatters: ["Prettier"],
            frontendTestingTools: ["Jest"],
            backendLanguages: ["Go"],
            backendFrameworks: ["Echo"],
            backendLibraries: ["sqlx"],
            backendBuildTools: ["Go build"],
            backendPackageManagers: ["go mod"],
            backendLinters: ["golangci-lint"],
            backendFormatters: ["gofmt"],
            backendTestingTools: ["testing"],
            ormTools: ["GORM"],
            auth: ["JWT"],
            clouds: ["AWS"],
            operatingSystems: ["Linux"],
            containers: ["Docker"],
            databases: ["PostgreSQL"],
            webServers: ["Nginx"],
            ciCdTools: ["GitHub Actions"],
            iacTools: ["Terraform"],
            monitoringTools: ["CloudWatch"],
            loggingTools: ["CloudWatch Logs"],
            sourceControls: ["Git"],
            projectManagements: ["Jira"],
            communicationTools: ["Slack"],
            documentationTools: ["Confluence"],
            apiDevelopmentTools: ["Postman"],
            designTools: ["Figma"],
            editors: ["VSCode"],
            developmentEnvironments: ["Docker Desktop"],
        });
        expect(result).not.toHaveProperty("id");
        expect(result).not.toHaveProperty("active");
        expect(result).not.toHaveProperty("process");
        expect(result).not.toHaveProperty("techStack");
    });

    it("certificationの場合、API送信用のペイロードを返すこと", () => {
        const entry = {
            id: "cert-1",
            name: "基本情報技術者",
            date: "2020-06-01",
        };

        const result = buildPayloadForEntry("certification", entry);

        expect(result).toEqual({
            name: "基本情報技術者",
            date: "2020-06-01",
        });
        expect(result).not.toHaveProperty("id");
    });

    it("portfolioの場合、API送信用のペイロードを返すこと", () => {
        const entry = {
            id: "portfolio-1",
            name: "個人ブログ",
            overview: "技術ブログ",
            techStack: "Next.js, Vercel",
            link: "https://example.com/blog",
        };

        const result = buildPayloadForEntry("portfolio", entry);

        expect(result).toEqual({
            name: "個人ブログ",
            overview: "技術ブログ",
            techStack: "Next.js, Vercel",
            link: "https://example.com/blog",
        });
        expect(result).not.toHaveProperty("id");
    });

    it("snsPlatformの場合、API送信用のペイロードを返すこと", () => {
        const entry = {
            id: "snsPlatform-1",
            name: "GitHub",
            link: "https://github.com/example",
        };

        const result = buildPayloadForEntry("snsPlatform", entry);

        expect(result).toEqual({
            name: "GitHub",
            link: "https://github.com/example",
        });
        expect(result).not.toHaveProperty("id");
    });

    it("selfPromotionの場合、API送信用のペイロードを返すこと", () => {
        const entry = {
            id: "pr-1",
            title: "技術への取り組み",
            content: "新しい技術を積極的に学んでいます。",
        };

        const result = buildPayloadForEntry("selfPromotion", entry);

        expect(result).toEqual({
            title: "技術への取り組み",
            content: "新しい技術を積極的に学んでいます。",
        });
        expect(result).not.toHaveProperty("id");
    });

    it("SectionName以外（未知の文字列）の場合、entryをそのまま返すこと", () => {
        const entry = { foo: "bar", nested: { a: 1 } };

        const result = buildPayloadForEntry("unknown-type", entry);

        expect(result).toBe(entry); // 同一参照で返す（default: return entry）
    });
});

describe("createCurrentSection", () => {
    it("指定されたセクション名に対応するコンポーネントを生成すること", () => {
        const sectionNames: SectionName[] = [
            "basicInfo",
            "career",
            "project",
            "certification",
            "portfolio",
            "snsPlatform",
            "selfPromotion",
        ];

        for (const sectionName of sectionNames) {
            const result = createCurrentSection(sectionName);
            expect(result).toBeDefined();
            expect(result.type).toBeDefined();
        }
    });
});
