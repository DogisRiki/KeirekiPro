function foo(bar: string, bar: number): void {
    // 重複した引数名
    console.log("Hello, World!"); // console.log は無駄な出力とみなされる可能性がある
    let result = 42; // インデントが不適切
}

const unusedVar: number = 123; // 未使用の変数
let anotherUnusedVar: string = "I won't be used";

if (true) {
    // 条件式が固定値
    let unusedInsideIf: string = "This is also unused"; // if 内で未使用の変数
    console.log("This is always true"); // シングルクォートとダブルクォートが混在
}

foo("test", 42);
