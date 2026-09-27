import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { Process, Project } from "@/features/resume";
import { ProjectSection, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { createAxiosResponse, renderWithProviders, resetStoresAndMocks } from "@/test";
import { fireEvent, screen, within } from "@testing-library/react";

import { cloneResume, emptyTechStack } from "../../../__tests__/resumeTestData";

type FieldErrors = Record<string, string[]>;

/** 選択中のプロジェクトを1件持つ状態で描画する */
const renderSection = ({
    project = {},
    errors,
}: {
    project?: Partial<Project>;
    errors?: FieldErrors;
} = {}) => {
    const base = cloneResume();
    const store = useResumeStore.getState();
    store.setResume({ ...base, projects: [{ ...base.projects[0], ...project }] });
    store.setActiveSection("project");
    store.setActiveEntryId("project-1");
    if (errors) {
        store.setEntryErrors("project-1", errors);
    }
    return renderWithProviders(<ProjectSection />);
};

const currentProject = () => useResumeStore.getState().resume?.projects[0];

/** 年月の入力欄(MUI X の DatePicker)を取り出す */
const datePickerGroup = (label: RegExp) => screen.getByRole("group", { name: label });

/** 欄のラベル。MUI は必須・無効・エラーの状態をラベルのクラスにも付ける */
const fieldLabel = (text: string) => screen.getByText(text, { selector: "label" });

/** 作業工程の選択欄(ラベルと関連付いていないため名前が空になる。会社名の欄とは名前で区別する) */
const processSelect = () => screen.getByRole("combobox", { name: "" });

const expectProcessError = (hasError: boolean) => {
    if (hasError) {
        expect(fieldLabel("作業工程")).toHaveClass("Mui-error");
    } else {
        expect(fieldLabel("作業工程")).not.toHaveClass("Mui-error");
    }
};

const textFields = [
    { label: /^プロジェクト名/, key: "name" },
    { label: /^プロジェクト概要/, key: "overview" },
    { label: /^チーム構成/, key: "teamComp" },
    { label: /^役割/, key: "role" },
    { label: /^主な成果/, key: "achievement" },
] as const;

const processKeys: (keyof Process)[] = [
    "requirements",
    "basicDesign",
    "detailedDesign",
    "implementation",
    "integrationTest",
    "systemTest",
    "maintenance",
];

describe("ProjectSection", () => {
    beforeEach(() => {
        resetStoresAndMocks([() => vi.mocked(protectedApiClient.get).mockReset()]);
        vi.mocked(protectedApiClient.get).mockResolvedValue(createAxiosResponse(emptyTechStack));
    });

    it("プロジェクトが選ばれていないときは、選択を促す文言だけを表示すること", () => {
        useResumeStore.getState().setResume(cloneResume());
        useResumeStore.getState().setActiveSection("project");

        renderWithProviders(<ProjectSection />);

        expect(screen.getByText("一覧からプロジェクトを選択してください。")).toBeInTheDocument();
        expect(screen.queryByRole("textbox", { name: /^プロジェクト名/ })).not.toBeInTheDocument();
    });

    it.each(textFields)("$key の入力欄を変更すると、ストアのプロジェクトに反映すること", ({ label, key }) => {
        renderSection();

        fireEvent.change(screen.getByRole("textbox", { name: label }), { target: { value: `新しい${key}` } });

        expect(currentProject()?.[key]).toBe(`新しい${key}`);
        expect(useResumeStore.getState().dirtyEntryIds.has("project-1")).toBe(true);
    });

    it.each(textFields)("$key にエラーがあるときは、その欄をエラー表示にしてメッセージを出すこと", ({ label, key }) => {
        renderSection({ errors: { [key]: [`${key}のエラー`] } });

        expect(screen.getByRole("textbox", { name: label })).toHaveAttribute("aria-invalid", "true");
        expect(screen.getByText(`${key}のエラー`)).toBeInTheDocument();
        // ほかの欄はエラー表示にしない
        textFields
            .filter((field) => field.key !== key)
            .forEach((field) => {
                expect(screen.getByRole("textbox", { name: field.label })).toHaveAttribute("aria-invalid", "false");
            });
    });

    it("会社名にエラーがあるときは、会社名の欄をエラー表示にしてメッセージを出すこと", () => {
        renderSection({ errors: { companyName: ["会社名のエラー"] } });

        expect(screen.getByRole("combobox", { name: /^会社名/ })).toHaveAttribute("aria-invalid", "true");
        expect(screen.getByText("会社名のエラー")).toBeInTheDocument();
    });

    it("エラーが無いときは、どの欄もエラー表示にしないこと", () => {
        renderSection();

        expect(screen.getByRole("combobox", { name: /^会社名/ })).toHaveAttribute("aria-invalid", "false");
        textFields.forEach(({ label }) => {
            expect(screen.getByRole("textbox", { name: label })).toHaveAttribute("aria-invalid", "false");
        });
        expect(datePickerGroup(/^プロジェクト開始年月/)).toHaveAttribute("aria-invalid", "false");
        expect(datePickerGroup(/^プロジェクト終了年月/)).toHaveAttribute("aria-invalid", "false");
    });

    it("開始年月にエラーがあるときは、開始年月の欄だけをエラー表示にすること", () => {
        renderSection({ errors: { startDate: ["開始年月のエラー"] } });

        expect(datePickerGroup(/^プロジェクト開始年月/)).toHaveAttribute("aria-invalid", "true");
        expect(datePickerGroup(/^プロジェクト終了年月/)).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("開始年月のエラー")).toBeInTheDocument();
    });

    it("終了年月にエラーがあるときは、終了年月の欄だけをエラー表示にすること", () => {
        renderSection({ project: { active: false, endDate: "2021-03" }, errors: { endDate: ["終了年月のエラー"] } });

        expect(datePickerGroup(/^プロジェクト終了年月/)).toHaveAttribute("aria-invalid", "true");
        expect(datePickerGroup(/^プロジェクト開始年月/)).toHaveAttribute("aria-invalid", "false");
        expect(screen.getByText("終了年月のエラー")).toBeInTheDocument();
    });

    it("担当中のときは、終了年月を必須にせず、入力できないようにすること", () => {
        renderSection({ project: { active: true, endDate: null } });

        const endDateField = fieldLabel("プロジェクト終了年月");
        expect(endDateField).not.toHaveClass("Mui-required");
        expect(endDateField).toHaveClass("Mui-disabled");
    });

    it("担当中でないときは、終了年月を必須にすること", () => {
        renderSection({ project: { active: false, endDate: "2021-03" } });

        const endDateField = fieldLabel("プロジェクト終了年月");
        expect(endDateField).toHaveClass("Mui-required");
        expect(endDateField).not.toHaveClass("Mui-disabled");
    });

    it("選ばれている作業工程を、定義の順に読点で区切って表示すること", () => {
        renderSection();

        expect(processSelect()).toHaveTextContent("要件定義、実装・単体テスト");
    });

    it("作業工程の選択肢では、選ばれている工程だけにチェックを付けること", () => {
        renderSection();

        fireEvent.mouseDown(processSelect());
        const listbox = screen.getByRole("listbox");
        const checkedLabels = within(listbox)
            .getAllByRole("option")
            .filter((option) => within(option).getByRole("checkbox").matches(":checked"))
            .map((option) => option.textContent);

        expect(checkedLabels).toEqual(["要件定義", "実装・単体テスト"]);
    });

    it("作業工程を選ぶと、選んだ工程を加えた内容でストアを更新すること", () => {
        renderSection();

        fireEvent.mouseDown(processSelect());
        fireEvent.click(within(screen.getByRole("listbox")).getByRole("option", { name: "基本設計" }));

        expect(currentProject()?.process).toEqual({
            requirements: true,
            basicDesign: true,
            detailedDesign: false,
            implementation: true,
            integrationTest: false,
            systemTest: false,
            maintenance: false,
        });
    });

    it("選ばれている作業工程を選び直すと、その工程を外すこと", () => {
        renderSection();

        fireEvent.mouseDown(processSelect());
        fireEvent.click(within(screen.getByRole("listbox")).getByRole("option", { name: "要件定義" }));

        expect(currentProject()?.process.requirements).toBe(false);
        expect(currentProject()?.process.implementation).toBe(true);
    });

    it.each(processKeys)("工程 %s にエラーがあるときは、作業工程の欄をエラー表示にしてメッセージを出すこと", (key) => {
        renderSection({ errors: { [key]: [`${key}のエラー`] } });

        expect(screen.getByText(`${key}のエラー`)).toBeInTheDocument();
        expectProcessError(true);
    });

    it("作業工程のエラーが無いときは、作業工程の欄をエラー表示にしないこと", () => {
        renderSection({ errors: { name: ["プロジェクト名のエラー"] } });

        expectProcessError(false);
    });

    it("複数の工程に同じエラーがあるときは、メッセージを1回だけ出すこと", () => {
        renderSection({
            errors: {
                requirements: ["工程を1つ以上選択してください。"],
                maintenance: ["工程を1つ以上選択してください。", "運用・保守のエラー"],
            },
        });

        expect(screen.getAllByText(/工程を1つ以上選択してください。/)).toHaveLength(1);
        expect(screen.getByText("・ 工程を1つ以上選択してください。 ・ 運用・保守のエラー")).toBeInTheDocument();
    });
});
