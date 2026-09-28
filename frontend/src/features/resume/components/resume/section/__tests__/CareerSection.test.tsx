import type { Career } from "@/features/resume";
import { CareerSection, useResumeStore } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen } from "@testing-library/react";

import { cloneResume } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

const otherCareer: Career = {
    id: "career-2",
    companyName: "Company B",
    startDate: "2015-04",
    endDate: "2019-12",
    active: false,
};

/** 職歴を2件持ち、そのうち1件を選んだ状態で描画する */
const renderSection = ({ career = {}, errors }: { career?: Partial<Career>; errors?: FieldErrors } = {}) => {
    const base = cloneResume();
    const store = useResumeStore.getState();
    store.setResume({ ...base, careers: [otherCareer, { ...base.careers[0], ...career }] });
    store.setActiveSection("career");
    store.setActiveEntryId("career-1");
    if (errors) {
        store.setEntryErrors("career-1", errors);
    }
    return renderWithProviders(<CareerSection />);
};

const currentCareer = () => useResumeStore.getState().resume?.careers.find((career) => career.id === "career-1");

const companyNameInput = () => screen.getByRole("textbox", { name: /^会社名/ });

/** 年月の入力欄(MUI X の DatePicker)を取り出す */
const datePickerGroup = (label: RegExp) => screen.getByRole("group", { name: label });

/** 欄のラベル。MUI は必須・無効・エラーの状態をラベルのクラスにも付ける */
const fieldLabel = (text: string) => screen.getByText(text, { selector: "label" });

const activeCheckbox = () => screen.getByRole("checkbox", { name: "在職中" });

/** 年月の入力欄を開き、年と月を選ぶ */
const pickYearMonth = async (
    user: ReturnType<typeof renderSection>["user"],
    label: RegExp,
    year: string,
    month: string,
) => {
    await user.click(datePickerGroup(label));
    fireEvent.click(await screen.findByRole("radio", { name: year }));
    fireEvent.click(await screen.findByRole("radio", { name: month }));
};

describe("CareerSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("職歴が選ばれていないときは、選択を促す文言だけを表示すること", () => {
        useResumeStore.getState().setResume(cloneResume());
        useResumeStore.getState().setActiveSection("career");

        renderWithProviders(<CareerSection />);

        expect(screen.getByText("一覧から職歴を選択してください。")).toBeInTheDocument();
        expect(screen.queryByRole("textbox", { name: /^会社名/ })).not.toBeInTheDocument();
    });

    it("選ばれている職歴の内容を表示すること", () => {
        renderSection({ career: { companyName: "Company A", startDate: "2020-01", active: true } });

        expect(companyNameInput()).toHaveValue("Company A");
        expect(datePickerGroup(/^入社年月/)).toHaveTextContent("2020/01");
        expect(activeCheckbox()).toBeChecked();
    });

    it("退職済みの職歴では、退職年月を表示すること", () => {
        renderSection({ career: { active: false, endDate: "2021-03" } });

        expect(datePickerGroup(/^退職年月/)).toHaveTextContent("2021/03");
        expect(activeCheckbox()).not.toBeChecked();
    });

    it("会社名を変更すると、選ばれている職歴に反映すること", () => {
        renderSection();

        fireEvent.change(companyNameInput(), { target: { value: "株式会社ABC" } });

        expect(currentCareer()?.companyName).toBe("株式会社ABC");
        expect(useResumeStore.getState().resume?.careers[0]).toEqual(otherCareer);
        expect(useResumeStore.getState().dirtyEntryIds.has("career-1")).toBe(true);
    });

    it("会社名が既定の名前のときは、フォーカスで消すこと", () => {
        renderSection({ career: { companyName: "新しい職歴" } });

        fireEvent.focus(companyNameInput());

        expect(currentCareer()?.companyName).toBe("");
    });

    it("会社名が既定の名前でないときは、フォーカスしても消さないこと", () => {
        renderSection({ career: { companyName: "Company A" } });

        fireEvent.focus(companyNameInput());

        expect(currentCareer()?.companyName).toBe("Company A");
        expect(useResumeStore.getState().dirtyEntryIds.has("career-1")).toBe(false);
    });

    it("入社年月を選ぶと、年月の形式でストアに反映すること", async () => {
        const { user } = renderSection({ career: { startDate: "2020-01" } });

        await pickYearMonth(user, /^入社年月/, "2018", "April");

        expect(currentCareer()?.startDate).toBe("2018-04");
    });

    it("在職中でないときは、退職年月を選ぶと年月の形式でストアに反映すること", async () => {
        const { user } = renderSection({ career: { active: false, endDate: "2021-03" } });

        await pickYearMonth(user, /^退職年月/, "2022", "September");

        expect(currentCareer()?.endDate).toBe("2022-09");
    });

    it("在職中のときは、退職年月を必須にせず、入力できないようにすること", () => {
        renderSection({ career: { active: true, endDate: null } });

        const endDateField = fieldLabel("退職年月");
        expect(endDateField).not.toHaveClass("Mui-required");
        expect(endDateField).toHaveClass("Mui-disabled");
    });

    it("在職中でないときは、退職年月を必須にし、入力できるようにすること", () => {
        renderSection({ career: { active: false, endDate: "2021-03" } });

        const endDateField = fieldLabel("退職年月");
        expect(endDateField).toHaveClass("Mui-required");
        expect(endDateField).not.toHaveClass("Mui-disabled");
    });

    it("在職中にすると、退職年月を消すこと", async () => {
        const { user } = renderSection({ career: { active: false, endDate: "2021-03" } });

        await user.click(activeCheckbox());

        expect(currentCareer()).toMatchObject({ active: true, endDate: null });
    });

    it("在職中を外すと、退職年月は持っている値のままにすること", async () => {
        const { user } = renderSection({ career: { active: true, endDate: "2021-03" } });

        await user.click(activeCheckbox());

        expect(currentCareer()).toMatchObject({ active: false, endDate: "2021-03" });
        expect(fieldLabel("退職年月")).toHaveClass("Mui-required");
    });

    it("会社名にエラーがあるときは、会社名の欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { companyName: ["会社名のエラー"] } });

        expect(companyNameInput()).toHaveAttribute("aria-invalid", "true");
        expect(datePickerGroup(/^入社年月/)).toHaveAttribute("aria-invalid", "false");
        expect(datePickerGroup(/^退職年月/)).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("会社名のエラー")).toBeInTheDocument();
    });

    it("入社年月にエラーがあるときは、入社年月の欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { startDate: ["入社年月のエラー"] } });

        expect(datePickerGroup(/^入社年月/)).toHaveAttribute("aria-invalid", "true");
        expect(companyNameInput()).toHaveAttribute("aria-invalid", "false");
        expect(datePickerGroup(/^退職年月/)).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("入社年月のエラー")).toBeInTheDocument();
    });

    it("退職年月にエラーがあるときは、退職年月の欄だけをエラー表示にしてメッセージを出すこと", () => {
        renderSection({ career: { active: false, endDate: "2021-03" }, errors: { endDate: ["退職年月のエラー"] } });

        expect(datePickerGroup(/^退職年月/)).toHaveAttribute("aria-invalid", "true");
        expect(companyNameInput()).toHaveAttribute("aria-invalid", "false");
        expect(datePickerGroup(/^入社年月/)).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("退職年月のエラー")).toBeInTheDocument();
    });

    it("1つの欄に複数のエラーがあるときは、箇条書きでまとめて出すこと", () => {
        renderSection({ errors: { companyName: ["1つ目のエラー", "2つ目のエラー"] } });

        expect(screen.getByText("・ 1つ目のエラー ・ 2つ目のエラー")).toBeInTheDocument();
    });
});
