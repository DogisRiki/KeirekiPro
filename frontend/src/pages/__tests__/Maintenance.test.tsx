import { act, screen } from "@testing-library/react";
import { Route, Routes, useLocation } from "react-router";
import { vi } from "vitest";

import { paths } from "@/config/paths";
import { Maintenance } from "@/pages/Maintenance";
import { renderWithProviders, resetStoresAndMocks } from "@/test";

const OUTAGE_TITLE = "ただいまご利用いただけません";
const OUTAGE_MESSAGE =
    "サービスに接続できない状態です。復旧までしばらくお待ちいただき、時間をおいて再度アクセスしてください。";
const CLOSED_TITLE = "メンテナンス中";
const CLOSED_MESSAGE = "現在サービスは停止中です。平日 8:00〜20:00 に再度アクセスしてください。";

/** 今の画面のパスを表示する */
const LocationDisplay = () => {
    const { pathname } = useLocation();
    return <div data-testid="location">{pathname}</div>;
};

/** メンテ画面を /maintenance で表示する */
const renderMaintenance = () =>
    renderWithProviders(
        <>
            <Routes>
                <Route path={paths.maintenance} element={<Maintenance />} />
                <Route path="*" element={<div>別の画面</div>} />
            </Routes>
            <LocationDisplay />
        </>,
        { route: paths.maintenance },
    );

const expectOutageNotice = () => {
    expect(screen.getByRole("heading", { name: OUTAGE_TITLE })).toBeInTheDocument();
    expect(screen.getByText(OUTAGE_MESSAGE)).toBeInTheDocument();
    expect(screen.getByTestId("CloudOffIcon")).toBeInTheDocument();
    expect(screen.queryByText(CLOSED_TITLE)).not.toBeInTheDocument();
    expect(screen.queryByTestId("BuildIcon")).not.toBeInTheDocument();
};

const expectClosedNotice = () => {
    expect(screen.getByRole("heading", { name: CLOSED_TITLE })).toBeInTheDocument();
    expect(screen.getByText(CLOSED_MESSAGE)).toBeInTheDocument();
    expect(screen.getByTestId("BuildIcon")).toBeInTheDocument();
    expect(screen.queryByText(OUTAGE_TITLE)).not.toBeInTheDocument();
    expect(screen.queryByTestId("CloudOffIcon")).not.toBeInTheDocument();
};

describe("Maintenance", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.useFakeTimers();
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it("日本時間の平日 10:00 は障害の案内を出す", () => {
        // 2026-10-14 は水曜
        vi.setSystemTime(new Date("2026-10-14T10:00:00+09:00"));

        renderMaintenance();

        expectOutageNotice();
    });

    it("日本時間の平日 21:00 は時間外の案内を出す", () => {
        vi.setSystemTime(new Date("2026-10-14T21:00:00+09:00"));

        renderMaintenance();

        expectClosedNotice();
    });

    it("日本時間の土曜 10:00 は時間外の案内を出す", () => {
        // 2026-10-17 は土曜
        vi.setSystemTime(new Date("2026-10-17T10:00:00+09:00"));

        renderMaintenance();

        expectClosedNotice();
    });

    it("日本時間の平日 8:00 は障害の案内を出す", () => {
        vi.setSystemTime(new Date("2026-10-14T08:00:00+09:00"));

        renderMaintenance();

        expectOutageNotice();
    });

    it("表示のあと、自分から別の画面へ移らない", () => {
        vi.setSystemTime(new Date("2026-10-14T10:00:00+09:00"));

        renderMaintenance();

        // 10分たっても、メンテ画面のままである
        act(() => {
            vi.advanceTimersByTime(10 * 60 * 1000);
        });

        expect(screen.getByTestId("location")).toHaveTextContent(paths.maintenance);
        expect(screen.queryByText("別の画面")).not.toBeInTheDocument();
        expectOutageNotice();
    });
});
