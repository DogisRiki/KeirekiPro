import { UserState, isProviderRemovable, isTwoFactorDisabled } from "@/features/user";
import type { AuthProvider } from "@/types";
import { describe, expect, it } from "vitest";

describe("isTwoFactorDisabled", () => {
    it("UserStateがEMAIL_PASSWORDのとき、二段階認証設定は切り替え可能(false)であることを検証", () => {
        expect(isTwoFactorDisabled(UserState.EMAIL_PASSWORD)).toBe(false);
    });
    it("UserStateがEMAIL_PASSWORD_WITH_PROVIDERのとき、二段階認証設定は切り替え可能(false)であることを検証", () => {
        expect(isTwoFactorDisabled(UserState.EMAIL_PASSWORD_WITH_PROVIDER)).toBe(false);
    });
    it("UserStateがEMAIL_PASSWORDとEMAIL_PASSWORD_WITH_PROVIDE以外のとき、二段階認証設定は切り替え不可(true)であることを検証", () => {
        expect(isTwoFactorDisabled(UserState.EMAIL_WITH_PROVIDER)).toBe(true);
        expect(isTwoFactorDisabled(UserState.PROVIDER_ONLY)).toBe(true);
        expect(isTwoFactorDisabled(UserState.UNKNOWN)).toBe(true);
    });
});

describe("isProviderRemovable", () => {
    it("UserStateがEMAIL_PASSWORD_WITH_PROVIDERのとき、プロバイダー数にかかわらず外部連携は解除可能(true)であることを検証", () => {
        // 空配列でもtrue
        expect(isProviderRemovable(UserState.EMAIL_PASSWORD_WITH_PROVIDER, [] as AuthProvider[])).toBe(true);
        // ダミーの文字列をキャストしてもtrue
        expect(
            isProviderRemovable(UserState.EMAIL_PASSWORD_WITH_PROVIDER, [
                "dummy1",
                "dummy2",
            ] as unknown as AuthProvider[]),
        ).toBe(true);
    });

    it("UserStateが EMAIL_WITH_PROVIDER かつ providerCount < 2 のとき、外部連携は解除不可(false)であることを検証", () => {
        expect(isProviderRemovable(UserState.EMAIL_WITH_PROVIDER, ["github"] as AuthProvider[])).toBe(false);
    });
    it("UserStateが PROVIDER_ONLY かつ providerCount < 2 のとき、外部連携は解除不可(false)であることを検証", () => {
        expect(isProviderRemovable(UserState.PROVIDER_ONLY, ["google"] as AuthProvider[])).toBe(false);
    });

    it("UserStateが EMAIL_WITH_PROVIDER かつ providerCount >= 2のとき、外部連携は解除可能(true)であることを検証", () => {
        expect(isProviderRemovable(UserState.EMAIL_WITH_PROVIDER, ["g1", "g2"] as unknown as AuthProvider[])).toBe(
            true,
        );
    });
    it("UserStateが PROVIDER_ONLY かつ providerCount >= 2 のとき、外部連携は解除可能(true)であることを検証", () => {
        expect(isProviderRemovable(UserState.PROVIDER_ONLY, ["p1", "p2", "p3"] as unknown as AuthProvider[])).toBe(
            true,
        );
    });
});
