import type * as ReactRouter from "react-router";
import { vi } from "vitest";

// モックをセット
vi.mock("react-ga4", () => {
    const m = { send: vi.fn(), set: vi.fn() };
    return { default: m };
});

const mockLocation = vi.hoisted(() => ({ pathname: "/foo", search: "?bar=1", hash: "#baz" }));

vi.mock("react-router", async (importOriginal) => ({
    ...(await importOriginal<typeof ReactRouter>()),
    useLocation: () => mockLocation,
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
        mockLocation.pathname = "/foo";
    });

    it("GA_MEASUREMENT_IDが設定されている場合、クエリ文字列とハッシュを除いたパスとURLを送ること", () => {
        renderHook(() => useGoogleAnalytics());
        const location = `${window.location.origin}/foo`;
        expect(ReactGA.set).toHaveBeenCalledWith({ page_location: location });
        expect(ReactGA.send).toHaveBeenCalledWith({
            hitType: "pageview",
            page: "/foo",
            location,
        });
    });

    it("パスワード再設定ページでは、トークンを固定の文字列に置き換えて送ること", () => {
        mockLocation.pathname = "/password/reset/secret-token";
        renderHook(() => useGoogleAnalytics());
        const location = `${window.location.origin}/password/reset/:token`;
        expect(ReactGA.set).toHaveBeenCalledWith({ page_location: location });
        expect(ReactGA.send).toHaveBeenCalledWith({
            hitType: "pageview",
            page: "/password/reset/:token",
            location,
        });
    });

    it("GA_MEASUREMENT_IDが空文字の場合、ReactGA.sendが呼び出されないこと", () => {
        env.GA_MEASUREMENT_ID = "";
        renderHook(() => useGoogleAnalytics());
        expect(ReactGA.set).not.toHaveBeenCalled();
        expect(ReactGA.send).not.toHaveBeenCalled();
    });
});

describe("GoogleAnalytics", () => {
    beforeEach(() => {
        // モック関数をクリアし、デフォルトのenvを復元
        vi.clearAllMocks();
        // 毎回計測IDを設定しておく
        env.GA_MEASUREMENT_ID = "G-TESTID";
        mockLocation.pathname = "/foo";
    });

    it("マウント時にReactGA.sendが呼び出されること", () => {
        render(<GoogleAnalytics />);
        expect(ReactGA.send).toHaveBeenCalledWith({
            hitType: "pageview",
            page: "/foo",
            location: `${window.location.origin}/foo`,
        });
    });

    it("GA_MEASUREMENT_IDが空文字の場合、renderしてもReactGA.sendが呼び出されないこと", () => {
        env.GA_MEASUREMENT_ID = "";
        render(<GoogleAnalytics />);
        expect(ReactGA.send).not.toHaveBeenCalled();
    });
});
