import { vi } from "vitest";

type NotFoundOptions = { onResumeNotFound?: (errorResponse?: unknown) => void } | undefined;

/** 差し替えたフックの状態と呼び出しを、テストから操作・確認する */
const hookState = vi.hoisted(() => ({
    deleteMutate: vi.fn(),
    deletePending: false,
    exportMutate: vi.fn(),
    exportPending: false,
    exportOptions: undefined as NotFoundOptions,
    openPreview: vi.fn(),
    previewPending: false,
    previewOpen: false,
    previewOptions: undefined as NotFoundOptions,
}));

vi.mock("@/features/resume/hooks/useDeleteResume", () => ({
    useDeleteResume: () => ({ mutate: hookState.deleteMutate, isPending: hookState.deletePending }),
}));

vi.mock("@/features/resume/hooks/useExportResume", () => ({
    useExportResume: (options: NotFoundOptions) => {
        hookState.exportOptions = options;
        return { mutate: hookState.exportMutate, isPending: hookState.exportPending };
    },
}));

vi.mock("@/features/resume/hooks/useResumePdfPreview", async () => {
    const { DEFAULT_RESUME_PDF_SETTINGS } = await import("@/features/resume/utils/pdfPreview");
    return {
        useResumePdfPreview: (options: NotFoundOptions) => {
            hookState.previewOptions = options;
            return {
                open: hookState.previewOpen,
                previewUrl: null,
                settings: DEFAULT_RESUME_PDF_SETTINGS,
                updateSettings: vi.fn(),
                refresh: vi.fn(),
                resetSettings: vi.fn(),
                exportPdf: vi.fn(),
                close: vi.fn(),
                openPreview: hookState.openPreview,
                isPending: hookState.previewPending,
            };
        },
    };
});

import { BottomMenu, useResumeStore } from "@/features/resume";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import { act, screen, within } from "@testing-library/react";
import { Route, Routes, useLocation } from "react-router";

import { cloneResume } from "../../__tests__/resumeTestData";

/** 一覧画面の代わりに、受け取った画面遷移の状態を表示する */
const ResumeListProbe = () => {
    const location = useLocation();
    return <div>一覧画面:{JSON.stringify(location.state ?? null)}</div>;
};

/** 画面幅の判定(useMediaQuery)を、スマホ幅かどうかで固定する */
const mockMobile = (isMobile: boolean) => {
    vi.spyOn(window, "matchMedia").mockImplementation((query: string) => ({
        matches: isMobile,
        media: query,
        onchange: null,
        addListener: vi.fn(),
        removeListener: vi.fn(),
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        dispatchEvent: vi.fn(() => false),
    }));
};

const renderMenu = ({
    autoSaveEnabled = false,
    isSaving = false,
    canSave = true,
}: { autoSaveEnabled?: boolean; isSaving?: boolean; canSave?: boolean } = {}) => {
    useResumeStore.getState().setResume(cloneResume({ id: "resume-1", resumeName: "Alpha Resume" }));
    const onAutoSaveToggle = vi.fn();
    const onSave = vi.fn();
    const utils = renderWithProviders(
        <Routes>
            <Route
                path="/resume/:id"
                element={
                    <BottomMenu
                        autoSaveEnabled={autoSaveEnabled}
                        onAutoSaveToggle={onAutoSaveToggle}
                        onSave={onSave}
                        isSaving={isSaving}
                        canSave={canSave}
                    />
                }
            />
            <Route path="/resume/list" element={<ResumeListProbe />} />
        </Routes>,
        { route: "/resume/resume-1" },
    );
    return { onAutoSaveToggle, onSave, ...utils };
};

describe("BottomMenu", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        hookState.deleteMutate.mockReset();
        hookState.exportMutate.mockReset();
        hookState.openPreview.mockReset();
        hookState.deletePending = false;
        hookState.exportPending = false;
        hookState.previewPending = false;
        hookState.previewOpen = false;
        hookState.exportOptions = undefined;
        hookState.previewOptions = undefined;
    });

    describe("PC幅", () => {
        beforeEach(() => {
            mockMobile(false);
        });

        it("保存ボタンを押すと、保存を呼ぶこと", async () => {
            const { user, onSave } = renderMenu();

            await user.click(screen.getByRole("button", { name: "保存" }));

            expect(onSave).toHaveBeenCalledTimes(1);
        });

        it.each([
            { isSaving: true, canSave: true },
            { isSaving: false, canSave: false },
        ])("保存中($isSaving)や保存できない($canSave)ときは、保存ボタンを押せないこと", ({ isSaving, canSave }) => {
            renderMenu({ isSaving, canSave });

            expect(screen.getByRole("button", { name: "保存" })).toBeDisabled();
        });

        it("保存できて保存中でないときは、保存ボタンを押せること", () => {
            renderMenu({ isSaving: false, canSave: true });

            expect(screen.getByRole("button", { name: "保存" })).toBeEnabled();
        });

        it.each([true, false])(
            "自動保存のスイッチは今の設定(%s)を示し、切り替えると反対の値を渡すこと",
            async (enabled) => {
                const { user, onAutoSaveToggle } = renderMenu({ autoSaveEnabled: enabled });
                const toggle = screen.getByRole("switch", { name: "自動保存" });

                if (enabled) {
                    expect(toggle).toBeChecked();
                } else {
                    expect(toggle).not.toBeChecked();
                }
                await user.click(toggle);

                expect(onAutoSaveToggle).toHaveBeenCalledWith(!enabled);
            },
        );

        it("エクスポートからPDFを選ぶと、表示中の職務経歴書のプレビューを開き、メニューを閉じること", async () => {
            const { user } = renderMenu();

            await user.click(screen.getByRole("button", { name: "エクスポート" }));
            await user.click(screen.getByRole("menuitem", { name: "PDFでエクスポート" }));

            expect(hookState.openPreview).toHaveBeenCalledWith("resume-1");
            expect(hookState.exportMutate).not.toHaveBeenCalled();
            expect(screen.queryByRole("menu")).not.toBeInTheDocument();
        });

        it("エクスポートからMarkdownを選ぶと、表示中の職務経歴書をMarkdownで出力し、メニューを閉じること", async () => {
            const { user } = renderMenu();

            await user.click(screen.getByRole("button", { name: "エクスポート" }));
            await user.click(screen.getByRole("menuitem", { name: "Markdownでエクスポート" }));

            expect(hookState.exportMutate).toHaveBeenCalledWith({ resumeId: "resume-1", format: "markdown" });
            expect(hookState.openPreview).not.toHaveBeenCalled();
            expect(screen.queryByRole("menu")).not.toBeInTheDocument();
        });

        it("職務経歴書が読み込まれていないときは、エクスポートを選んでも何もしないこと", async () => {
            const { user } = renderMenu();
            act(() => useResumeStore.getState().clearResume());

            await user.click(screen.getByRole("button", { name: "エクスポート" }));
            await user.click(screen.getByRole("menuitem", { name: "PDFでエクスポート" }));
            await user.click(screen.getByRole("button", { name: "エクスポート" }));
            await user.click(screen.getByRole("menuitem", { name: "Markdownでエクスポート" }));

            expect(hookState.openPreview).not.toHaveBeenCalled();
            expect(hookState.exportMutate).not.toHaveBeenCalled();
        });

        it.each([
            { exportPending: true, previewPending: false },
            { exportPending: false, previewPending: true },
        ])(
            "エクスポートの処理中(Markdown: $exportPending, PDF: $previewPending)は、エクスポートボタンを押せないこと",
            ({ exportPending, previewPending }) => {
                hookState.exportPending = exportPending;
                hookState.previewPending = previewPending;

                renderMenu();

                expect(screen.getByRole("button", { name: "エクスポート" })).toBeDisabled();
            },
        );

        it("エクスポートで職務経歴書が見つからなかったときは、エラー内容を持って一覧へ移ること", () => {
            renderMenu();

            act(() => hookState.exportOptions?.onResumeNotFound?.({ message: "見つかりません", errors: {} }));

            expect(
                screen.getByText('一覧画面:{"errorResponse":{"message":"見つかりません","errors":{}}}'),
            ).toBeInTheDocument();
        });

        it("PDFのプレビューで職務経歴書が見つからなかったときも、エラー内容を持って一覧へ移ること", () => {
            renderMenu();

            act(() => hookState.previewOptions?.onResumeNotFound?.({ message: "見つかりません", errors: {} }));

            expect(
                screen.getByText('一覧画面:{"errorResponse":{"message":"見つかりません","errors":{}}}'),
            ).toBeInTheDocument();
        });

        it("削除を押すと職務経歴書名を添えて確認し、「はい」で削除して、成功したら一覧へ移ること", async () => {
            const { user } = renderMenu();

            await user.click(screen.getByRole("button", { name: "職務経歴書を削除" }));
            const dialog = screen.getByRole("dialog");
            expect(dialog).toHaveTextContent("「Alpha Resume」を削除しますか？この操作は取り消せません。");
            await user.click(within(dialog).getByRole("button", { name: "はい" }));

            expect(hookState.deleteMutate).toHaveBeenCalledWith("resume-1", expect.anything());
            // 削除が成功するまでは一覧へ移らない
            expect(screen.queryByText(/一覧画面/)).not.toBeInTheDocument();
            act(() => hookState.deleteMutate.mock.calls[0][1].onSuccess());
            expect(screen.getByText("一覧画面:null")).toBeInTheDocument();
        });

        it("削除の確認で「いいえ」を選ぶと、削除しないこと", async () => {
            const { user } = renderMenu();

            await user.click(screen.getByRole("button", { name: "職務経歴書を削除" }));
            await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "いいえ" }));

            expect(hookState.deleteMutate).not.toHaveBeenCalled();
            expect(screen.queryByText(/一覧画面/)).not.toBeInTheDocument();
        });

        it("削除の処理中は、削除ボタンを押せないこと", () => {
            hookState.deletePending = true;

            renderMenu();

            expect(screen.getByRole("button", { name: "職務経歴書を削除" })).toBeDisabled();
        });

        it("折りたたむと展開ボタンだけを出し、展開すると元のメニューに戻すこと", async () => {
            const { user } = renderMenu();

            await user.click(screen.getByRole("button", { name: "メニューを折りたたむ" }));

            expect(screen.getByRole("button", { name: "メニューを展開" })).toBeInTheDocument();
            expect(screen.queryByRole("button", { name: "保存" })).not.toBeInTheDocument();

            await user.click(screen.getByRole("button", { name: "メニューを展開" }));

            expect(screen.getByRole("button", { name: "保存" })).toBeInTheDocument();
        });

        it("PDFのプレビューが開いているときは、折りたたんでいてもプレビューを出すこと", async () => {
            hookState.previewOpen = true;
            const { user } = renderMenu();
            expect(screen.getByRole("dialog", { name: /PDFプレビュー/ })).toBeInTheDocument();

            await user.click(screen.getByRole("button", { name: "メニューを折りたたむ", hidden: true }));

            expect(screen.getByRole("dialog", { name: /PDFプレビュー/ })).toBeInTheDocument();
        });
    });

    describe("スマホ幅", () => {
        beforeEach(() => {
            mockMobile(true);
        });

        it("アイコンのボタンで、保存・エクスポート・削除・自動保存を操作できること", async () => {
            const { user, onSave, onAutoSaveToggle } = renderMenu();

            await user.click(within(screen.getByLabelText("保存")).getByRole("button"));
            expect(onSave).toHaveBeenCalledTimes(1);

            await user.click(screen.getByRole("switch", { name: "自動" }));
            expect(onAutoSaveToggle).toHaveBeenCalledWith(true);

            await user.click(screen.getByRole("button", { name: "エクスポート" }));
            await user.click(screen.getByRole("menuitem", { name: "Markdownでエクスポート" }));
            expect(hookState.exportMutate).toHaveBeenCalledWith({ resumeId: "resume-1", format: "markdown" });

            await user.click(screen.getByRole("button", { name: "エクスポート" }));
            await user.click(screen.getByRole("menuitem", { name: "PDFでエクスポート" }));
            expect(hookState.openPreview).toHaveBeenCalledWith("resume-1");

            await user.click(screen.getByRole("button", { name: "職務経歴書を削除" }));
            const dialog = screen.getByRole("dialog");
            expect(dialog).toHaveTextContent("「Alpha Resume」を削除しますか？この操作は取り消せません。");
            await user.click(within(dialog).getByRole("button", { name: "はい" }));
            expect(hookState.deleteMutate).toHaveBeenCalledWith("resume-1", expect.anything());
        });

        it("自動保存が有効なときは、スイッチを入れた状態で示し、切り替えると無効にすること", async () => {
            const { user, onAutoSaveToggle } = renderMenu({ autoSaveEnabled: true });
            const toggle = screen.getByRole("switch", { name: "自動" });

            expect(toggle).toBeChecked();
            await user.click(toggle);

            expect(onAutoSaveToggle).toHaveBeenCalledWith(false);
        });

        it("保存できないときや処理中は、対応するボタンを押せないこと", () => {
            hookState.deletePending = true;
            hookState.previewPending = true;

            renderMenu({ canSave: false });

            expect(within(screen.getByLabelText("保存")).getByRole("button")).toBeDisabled();
            expect(screen.getByRole("button", { name: "エクスポート" })).toBeDisabled();
            expect(screen.getByRole("button", { name: "職務経歴書を削除" })).toBeDisabled();
        });

        it("PDFのプレビューが開いているときは、プレビューを出すこと", () => {
            hookState.previewOpen = true;

            renderMenu();

            expect(screen.getByRole("dialog", { name: /PDFプレビュー/ })).toBeInTheDocument();
        });
    });
});
