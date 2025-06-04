import { vi } from "vitest";

// モックをセット
vi.mock("react-ga4", () => {
    const m = { send: vi.fn() };
    return { default: m };
});

vi.mock("react-router", () => ({
    useLocation: () => ({ pathname: "/foo", search: "?bar=1" }),
}));

import { env } from "@/config/env";
import { GoogleAnalytics, useGoogleAnalytics } from "@/hooks/useGoogleAnalytics";
import { render, renderHook } from "@testing-library/react";
import ReactGA from "react-ga4";

describe("useGoogleAnalytics", () => {
    beforeEach(() => {
        // モック関数をクリアし、デフォルトのenvを復元
        vi.clearAllMocks();
        // 毎回計測IDを設定しておく
        env.GA_MEASUREMENT_ID = "G-TESTID";
    });

    it("GA_MEASUREMENT_IDが設定されている場合、ReactGA.sendが呼び出されること", () => {
        renderHook(() => useGoogleAnalytics());
        expect(ReactGA.send).toHaveBeenCalledWith({
            hitType: "pageview",
            page: "/foo?bar=1",
        });
    });

    it("GA_MEASUREMENT_IDが空文字の場合、ReactGA.sendが呼び出されないこと", () => {
        env.GA_MEASUREMENT_ID = "";
        renderHook(() => useGoogleAnalytics());
        expect(ReactGA.send).not.toHaveBeenCalled();
    });
});

describe("GoogleAnalytics", () => {
    beforeEach(() => {
        // モック関数をクリアし、デフォルトのenvを復元
        vi.clearAllMocks();
        // 毎回計測IDを設定しておく
        env.GA_MEASUREMENT_ID = "G-TESTID";
    });

    it("マウント時にReactGA.sendが呼び出されること", () => {
        render(<GoogleAnalytics />);
        expect(ReactGA.send).toHaveBeenCalledWith({
            hitType: "pageview",
            page: "/foo?bar=1",
        });
    });

    it("GA_MEASUREMENT_IDが空文字の場合、renderしてもReactGA.sendが呼び出されないこと", () => {
        env.GA_MEASUREMENT_ID = "";
        render(<GoogleAnalytics />);
        expect(ReactGA.send).not.toHaveBeenCalled();
    });
});
