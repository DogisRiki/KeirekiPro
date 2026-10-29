import { isProviderRemovable, isTwoFactorDisabled } from "@/features/user";
import type { AuthProvider, User } from "@/types";
import { describe, expect, it } from "vitest";

/**
 * テスト用のユーザーを作る
 */
const createUser = (overrides: Partial<User>): User => ({
    id: "user-1",
    email: "test-user@example.com",
    username: "test-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: [],
    roles: ["USER"],
    emailVerified: true,
    pendingEmail: null,
    ...overrides,
});

describe("isTwoFactorDisabled", () => {
    it("確認済みのメールアドレスとパスワードがあり、外部連携が無いとき、二段階認証設定は切り替え可能(false)であることを検証", () => {
        expect(isTwoFactorDisabled(createUser({}))).toBe(false);
    });
    it("確認済みのメールアドレスとパスワードと外部連携があるとき、二段階認証設定は切り替え可能(false)であることを検証", () => {
        expect(isTwoFactorDisabled(createUser({ authProviders: ["github", "google"] }))).toBe(false);
    });
    it("パスワードが無いとき、またはユーザーが無いとき、二段階認証設定は切り替え不可(true)であることを検証", () => {
        expect(isTwoFactorDisabled(createUser({ hasPassword: false, authProviders: ["github"] }))).toBe(true);
        expect(isTwoFactorDisabled(createUser({ email: null, hasPassword: false, authProviders: ["google"] }))).toBe(
            true,
        );
        expect(isTwoFactorDisabled(null)).toBe(true);
    });
    it("emailVerified が false なら isTwoFactorDisabled が true を返す", () => {
        // 確認前のメールアドレスのアカウント
        expect(isTwoFactorDisabled(createUser({ emailVerified: false }))).toBe(true);
        // 設定待ちのメールアドレスだけを持つアカウント
        expect(
            isTwoFactorDisabled(
                createUser({
                    email: null,
                    emailVerified: false,
                    pendingEmail: "pending@example.com",
                    authProviders: ["google"],
                }),
            ),
        ).toBe(true);
    });
});

describe("isProviderRemovable", () => {
    it("確認済みのメールアドレスとパスワードがあるとき、プロバイダー数にかかわらず外部連携は解除可能(true)であることを検証", () => {
        expect(isProviderRemovable(createUser({ authProviders: [] as AuthProvider[] }))).toBe(true);
        expect(isProviderRemovable(createUser({ authProviders: ["github"] }))).toBe(true);
        expect(isProviderRemovable(createUser({ authProviders: ["github", "google"] }))).toBe(true);
    });

    it("パスワードが無く providerCount < 2 のとき、外部連携は解除不可(false)であることを検証", () => {
        expect(isProviderRemovable(createUser({ hasPassword: false, authProviders: ["github"] }))).toBe(false);
    });
    it("メールアドレスとパスワードが無く providerCount < 2 のとき、外部連携は解除不可(false)であることを検証", () => {
        expect(isProviderRemovable(createUser({ email: null, hasPassword: false, authProviders: ["google"] }))).toBe(
            false,
        );
    });

    it("パスワードが無く providerCount >= 2 のとき、外部連携は解除可能(true)であることを検証", () => {
        expect(isProviderRemovable(createUser({ hasPassword: false, authProviders: ["github", "google"] }))).toBe(true);
    });
    it("メールアドレスとパスワードが無く providerCount >= 2 のとき、外部連携は解除可能(true)であることを検証", () => {
        expect(
            isProviderRemovable(createUser({ email: null, hasPassword: false, authProviders: ["github", "google"] })),
        ).toBe(true);
    });

    it("emailVerified が false で外部連携が1つなら isProviderRemovable が false を返す", () => {
        // 確認前のメールアドレスのアカウント
        expect(isProviderRemovable(createUser({ emailVerified: false, authProviders: ["github"] }))).toBe(false);
        // 設定待ちのメールアドレスだけを持つアカウント
        expect(
            isProviderRemovable(
                createUser({
                    email: null,
                    emailVerified: false,
                    pendingEmail: "pending@example.com",
                    authProviders: ["google"],
                }),
            ),
        ).toBe(false);
    });

    it("emailVerified が false でも外部連携が2つ以上なら外部連携は解除可能(true)であることを検証", () => {
        expect(isProviderRemovable(createUser({ emailVerified: false, authProviders: ["github", "google"] }))).toBe(
            true,
        );
    });

    it("ユーザーが無いとき、外部連携は解除不可(false)であることを検証", () => {
        expect(isProviderRemovable(null)).toBe(false);
    });
});
