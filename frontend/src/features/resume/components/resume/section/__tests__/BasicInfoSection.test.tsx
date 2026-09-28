import type { Resume } from "@/features/resume";
import { BASIC_INFO_ENTRY_ID, BasicInfoSection, useResumeStore } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";

import { cloneResume } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

/** 職務経歴書を読み込んだ状態で描画する */
const renderSection = ({ resume = {}, errors }: { resume?: Partial<Resume>; errors?: FieldErrors } = {}) => {
    const store = useResumeStore.getState();
    store.setResume(cloneResume(resume));
    store.setActiveSection("basicInfo");
    if (errors) {
        store.setEntryErrors(BASIC_INFO_ENTRY_ID, errors);
    }
    return renderWithProviders(<BasicInfoSection />);
};

const currentResume = () => useResumeStore.getState().resume;

const textFields = [
    { label: /^職務経歴書名/, key: "resumeName" },
    { label: /^姓/, key: "lastName" },
    { label: /^名/, key: "firstName" },
] as const;

const dateGroup = () => screen.getByRole("group", { name: /^日付/ });

describe("BasicInfoSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("職務経歴書が無いときは、何も表示しないこと", () => {
        const { container } = renderWithProviders(<BasicInfoSection />);

        expect(container).toBeEmptyDOMElement();
    });

    it("職務経歴書の基本情報を表示すること", () => {
        renderSection({
            resume: { resumeName: "Alpha Resume", date: "2024-01-15", lastName: "Yamada", firstName: "Taro" },
        });

        expect(screen.getByRole("textbox", { name: /^職務経歴書名/ })).toHaveValue("Alpha Resume");
        expect(dateGroup()).toHaveTextContent("2024/01/15");
        expect(screen.getByRole("textbox", { name: /^姓/ })).toHaveValue("Yamada");
        expect(screen.getByRole("textbox", { name: /^名/ })).toHaveValue("Taro");
    });

    it("姓と名が無いときは、空の欄で表示すること", () => {
        renderSection({
            resume: { lastName: null as unknown as string, firstName: null as unknown as string },
        });

        expect(screen.getByRole("textbox", { name: /^姓/ })).toHaveValue("");
        expect(screen.getByRole("textbox", { name: /^名/ })).toHaveValue("");
    });

    it.each(textFields)("$key の入力欄を変更すると、職務経歴書に反映すること", ({ label, key }) => {
        renderSection();

        fireEvent.change(screen.getByRole("textbox", { name: label }), { target: { value: `新しい${key}` } });

        expect(currentResume()?.[key]).toBe(`新しい${key}`);
        expect(useResumeStore.getState().isDirty).toBe(true);
    });

    it("日付を選ぶと、年月日の形式で職務経歴書に反映すること", async () => {
        const { user } = renderSection({ resume: { date: "2024-01-01" } });

        await user.click(dateGroup());
        fireEvent.click(await screen.findByRole("gridcell", { name: "15" }));

        expect(currentResume()?.date).toBe("2024-01-15");
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
            expect(dateGroup()).toHaveAttribute("aria-invalid", "false");
        },
    );

    it("日付にエラーがあるときは、日付の欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { date: ["日付のエラー"] } });

        expect(dateGroup()).toHaveAttribute("aria-invalid", "true");
        expect(screen.getByText("日付のエラー")).toBeInTheDocument();
        textFields.forEach(({ label }) => {
            expect(screen.getByRole("textbox", { name: label })).toHaveAttribute("aria-invalid", "false");
        });
    });

    it("1つの欄に複数のエラーがあるときは、箇条書きでまとめて出すこと", () => {
        renderSection({ errors: { resumeName: ["1つ目のエラー", "2つ目のエラー"] } });

        expect(screen.getByText("・ 1つ目のエラー ・ 2つ目のエラー")).toBeInTheDocument();
    });
});
