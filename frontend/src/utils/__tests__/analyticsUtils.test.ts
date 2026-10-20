import { toAnalyticsLocation, toAnalyticsPath } from "@/utils";
import { describe, expect, it } from "vitest";

describe("analyticsUtils", () => {
    it("パスワード再設定ページのパスは、トークンを固定の文字列に置き換える", () => {
        expect(toAnalyticsPath("/password/reset/abc123")).toBe("/password/reset/:token");
    });

    it("パスワード再設定の依頼ページのパスは、そのまま返す", () => {
        expect(toAnalyticsPath("/password/reset")).toBe("/password/reset");
    });

    it("ほかのページのパスは、そのまま返す", () => {
        expect(toAnalyticsPath("/resume/list")).toBe("/resume/list");
    });

    it("URLはオリジンと置き換えたあとのパスをつなげる", () => {
        expect(toAnalyticsLocation("https://example.com", "/password/reset/abc123")).toBe(
            "https://example.com/password/reset/:token",
        );
    });
});
