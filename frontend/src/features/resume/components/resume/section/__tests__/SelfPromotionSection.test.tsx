import type { SelfPromotion } from "@/features/resume";
import { SelfPromotionSection, useResumeStore } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";

import { cloneResume } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

const otherSelfPromotion: SelfPromotion = { id: "self-2", title: "別の強み", content: "別の内容" };

/** 自己PRを2件持ち、そのうち1件を選んだ状態で描画する */
const renderSection = ({
    selfPromotion = {},
    errors,
}: { selfPromotion?: Partial<SelfPromotion>; errors?: FieldErrors } = {}) => {
    const store = useResumeStore.getState();
    store.setResume(
        cloneResume({
            selfPromotions: [otherSelfPromotion, { id: "self-1", title: "強み", content: "内容", ...selfPromotion }],
        }),
    );
    store.setActiveSection("selfPromotion");
    store.setActiveEntryId("self-1");
    if (errors) {
        store.setEntryErrors("self-1", errors);
    }
    return renderWithProviders(<SelfPromotionSection />);
};

const currentSelfPromotion = () =>
    useResumeStore.getState().resume?.selfPromotions.find((selfPromotion) => selfPromotion.id === "self-1");

const textFields = [
    { label: /^タイトル/, key: "title", value: "強み" },
    { label: /^内容/, key: "content", value: "内容" },
] as const;

describe("SelfPromotionSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("自己PRが選ばれていないときは、選択を促す文言だけを表示すること", () => {
        useResumeStore.getState().setResume(cloneResume());
        useResumeStore.getState().setActiveSection("selfPromotion");

        renderWithProviders(<SelfPromotionSection />);

        expect(screen.getByText("一覧から自己PRを選択してください。")).toBeInTheDocument();
        expect(screen.queryByRole("textbox", { name: /^タイトル/ })).not.toBeInTheDocument();
    });

    it("選ばれている自己PRの内容を表示すること", () => {
        renderSection();

        textFields.forEach(({ label, value }) => {
            expect(screen.getByRole("textbox", { name: label })).toHaveValue(value);
        });
    });

    it.each(textFields)("$key の入力欄を変更すると、選ばれている自己PRに反映すること", ({ label, key }) => {
        renderSection();

        fireEvent.change(screen.getByRole("textbox", { name: label }), { target: { value: `新しい${key}` } });

        expect(currentSelfPromotion()?.[key]).toBe(`新しい${key}`);
        expect(useResumeStore.getState().resume?.selfPromotions[0]).toEqual(otherSelfPromotion);
        expect(useResumeStore.getState().dirtyEntryIds.has("self-1")).toBe(true);
    });

    it("タイトルが既定の名前のときは、フォーカスで消すこと", () => {
        renderSection({ selfPromotion: { title: "新しい自己PR" } });

        fireEvent.focus(screen.getByRole("textbox", { name: /^タイトル/ }));

        expect(currentSelfPromotion()?.title).toBe("");
    });

    it("タイトルが既定の名前でないときは、フォーカスしても消さないこと", () => {
        renderSection();

        fireEvent.focus(screen.getByRole("textbox", { name: /^タイトル/ }));

        expect(currentSelfPromotion()?.title).toBe("強み");
        expect(useResumeStore.getState().dirtyEntryIds.has("self-1")).toBe(false);
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
        renderSection({ errors: { content: ["1つ目のエラー", "2つ目のエラー"] } });

        expect(screen.getByText("・ 1つ目のエラー ・ 2つ目のエラー")).toBeInTheDocument();
    });
});
