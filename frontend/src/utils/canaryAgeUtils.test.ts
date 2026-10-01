import { calcCanaryAge } from "./canaryAgeUtils";

describe("calcCanaryAge", () => {
    it("生年から年齢を計算できること", () => {
        const birth = new Date(2000, 0, 1);
        const expected = new Date().getFullYear() - 2000 + 1;
        expect(calcCanaryAge(birth)).toBe(expected);
    });
});
