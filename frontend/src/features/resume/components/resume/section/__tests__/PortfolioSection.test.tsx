import type { Portfolio } from "@/features/resume";
import { PortfolioSection, useResumeStore } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";

import { cloneResume } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

const otherPortfolio: Portfolio = {
    id: "portfolio-2",
    name: "Portfolio B",
    overview: "別の概要",
    techStack: "Go",
    link: "https://b.example",
};

/** ポートフォリオを2件持ち、そのうち1件を選んだ状態で描画する */
const renderSection = ({ portfolio = {}, errors }: { portfolio?: Partial<Portfolio>; errors?: FieldErrors } = {}) => {
    const store = useResumeStore.getState();
    store.setResume(
        cloneResume({
            portfolios: [
                otherPortfolio,
                {
                    id: "portfolio-1",
                    name: "Portfolio A",
                    overview: "概要",
                    techStack: "React",
                    link: "https://a.example",
                    ...portfolio,
                },
            ],
        }),
    );
    store.setActiveSection("portfolio");
    store.setActiveEntryId("portfolio-1");
    if (errors) {
        store.setEntryErrors("portfolio-1", errors);
    }
    return renderWithProviders(<PortfolioSection />);
};

const currentPortfolio = () =>
    useResumeStore.getState().resume?.portfolios.find((portfolio) => portfolio.id === "portfolio-1");

const textFields = [
    { label: /^ポートフォリオ名/, key: "name", value: "Portfolio A" },
    { label: /^ポートフォリオ概要/, key: "overview", value: "概要" },
    { label: /^リンク/, key: "link", value: "https://a.example" },
    { label: /^技術スタック/, key: "techStack", value: "React" },
] as const;

describe("PortfolioSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("ポートフォリオが選ばれていないときは、選択を促す文言だけを表示すること", () => {
        useResumeStore.getState().setResume(cloneResume());
        useResumeStore.getState().setActiveSection("portfolio");

        renderWithProviders(<PortfolioSection />);

        expect(screen.getByText("一覧からポートフォリオを選択してください。")).toBeInTheDocument();
        expect(screen.queryByRole("textbox", { name: /^ポートフォリオ名/ })).not.toBeInTheDocument();
    });

    it("選ばれているポートフォリオの内容を表示すること", () => {
        renderSection();

        textFields.forEach(({ label, value }) => {
            expect(screen.getByRole("textbox", { name: label })).toHaveValue(value);
        });
    });

    it("技術スタックが無いときは、空の欄で表示すること", () => {
        renderSection({ portfolio: { techStack: null } });

        expect(screen.getByRole("textbox", { name: /^技術スタック/ })).toHaveValue("");
    });

    it.each(textFields)("$key の入力欄を変更すると、選ばれているポートフォリオに反映すること", ({ label, key }) => {
        renderSection();

        fireEvent.change(screen.getByRole("textbox", { name: label }), { target: { value: `新しい${key}` } });

        expect(currentPortfolio()?.[key]).toBe(`新しい${key}`);
        expect(useResumeStore.getState().resume?.portfolios[0]).toEqual(otherPortfolio);
        expect(useResumeStore.getState().dirtyEntryIds.has("portfolio-1")).toBe(true);
    });

    it("ポートフォリオ名が既定の名前のときは、フォーカスで消すこと", () => {
        renderSection({ portfolio: { name: "新しいポートフォリオ" } });

        fireEvent.focus(screen.getByRole("textbox", { name: /^ポートフォリオ名/ }));

        expect(currentPortfolio()?.name).toBe("");
    });

    it("ポートフォリオ名が既定の名前でないときは、フォーカスしても消さないこと", () => {
        renderSection();

        fireEvent.focus(screen.getByRole("textbox", { name: /^ポートフォリオ名/ }));

        expect(currentPortfolio()?.name).toBe("Portfolio A");
        expect(useResumeStore.getState().dirtyEntryIds.has("portfolio-1")).toBe(false);
    });

    it.each(textFields)(
        "$key にエラーがあるときは、その欄だけをエラー表示にしてメッセージを出すこと",
        ({ label, key }) => {
            renderSection({ errors: { [key]: [`${key}のエラー`] } });

            expect(screen.getByRole("textbox", { name: label })).toHaveAttribute("aria-invalid", "true");
            expect(screen.getByText(`${key}のエラー`)).toBeInTheDocument();
            textFields
                .filter((field) => field.key !== key)
                .forEach((field) => {
                    expect(screen.getByRole("textbox", { name: field.label })).toHaveAttribute("aria-invalid", "false");
                });
        },
    );

    it("1つの欄に複数のエラーがあるときは、箇条書きでまとめて出すこと", () => {
        renderSection({ errors: { overview: ["1つ目のエラー", "2つ目のエラー"] } });

        expect(screen.getByText("・ 1つ目のエラー ・ 2つ目のエラー")).toBeInTheDocument();
    });
});
