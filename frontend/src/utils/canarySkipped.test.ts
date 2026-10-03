describe("canary skipped", () => {
    it.skip("スキップされたテスト", () => {
        expect(1 + 1).toBe(2);
    });
});
