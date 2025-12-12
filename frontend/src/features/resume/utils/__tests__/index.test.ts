import type { SectionName } from "@/features/resume";
import {
    TEMP_ID_PREFIX,
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

    describe("socialLink", () => {
        it("SNS名とリンクを返すこと", () => {
            const entry = {
                name: "GitHub",
                link: "https://github.com/example",
            };

            const result = getEntryText("socialLink", entry);

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
        ["socialLink", "socialLinks"],
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

describe("createCurrentSection", () => {
    it("指定されたセクション名に対応するコンポーネントを生成すること", () => {
        const sectionNames: SectionName[] = [
            "basicInfo",
            "career",
            "project",
            "certification",
            "portfolio",
            "socialLink",
            "selfPromotion",
        ];

        for (const sectionName of sectionNames) {
            const result = createCurrentSection(sectionName);
            expect(result).toBeDefined();
            expect(result.type).toBeDefined();
        }
    });
});
