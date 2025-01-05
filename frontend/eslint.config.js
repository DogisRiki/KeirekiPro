import { FlatCompat } from "@eslint/eslintrc";
import js from "@eslint/js";
import typeScriptESLintParser from "@typescript-eslint/parser";
import { readdirSync, statSync } from "fs";
import globals from "globals";
import { join } from "path";

// features配下のディレクトリ名を取得
const featuresPath = "src/features";
const featureDirectories = readdirSync(featuresPath).filter((dir) => statSync(join(featuresPath, dir)).isDirectory());

// FlatCompat のインスタンスを作成
const compat = new FlatCompat();

// 相対パスパターンを生成する関数
const createRelativePaths = (dir) => {
    // '../'を最大5階層分（必要に応じて調整）生成
    return Array.from({ length: 5 }, (_, i) => "../".repeat(i + 1) + dir);
};

export default [
    // ESLintの推奨設定を適用
    js.configs.recommended,

    // Lintの対象外とするファイルを指定
    {
        ignores: ["**/build/", "**/public/", "**/node_modules/", "**/*.min.js", "**/.*lintrc.js", "**/_templates/"],
    },

    // プラグインの推奨設定を適用
    ...compat.extends(
        "plugin:import/errors",
        "plugin:import/warnings",
        "plugin:import/typescript",
        "plugin:@typescript-eslint/recommended",
        "plugin:react/recommended",
        "plugin:react-hooks/recommended",
        "plugin:jsx-a11y/recommended",
        "plugin:testing-library/react",
        "plugin:jest-dom/recommended",
        "prettier", // eslint-config-prettier を拡張して競合ルールを無効化
    ),

    // 設定の上書き
    {
        settings: {
            react: {
                version: "detect", // Reactバージョンを自動検出
            },
            "import/resolver": {
                typescript: [
                    {
                        project: "./tsconfig.app.json", // TypeScriptのプロジェクト設定を指定
                    },
                ],
            },
        },
    },

    // 主要なルール設定
    {
        rules: {
            // 改行スタイルをUnix形式（LF）に統一
            "linebreak-style": ["error", "unix"],
            // ReactのPropTypesのチェックを無効化（TypeScript使用時に不要）
            "react/prop-types": "off",
            // インポートエイリアスによるimportをESLintがうまく認識してくれないため一旦無効化
            "import/no-unresolved": "off",
            // インポート順序のチェックを無効化（Prettierにimport整列をさせるため）
            "import/order": "off",
            // 一部のimportルールを無効化
            "import/default": "off",
            "import/no-named-as-default-member": "off",
            "import/no-named-as-default": "off",
            // React 17以降、JSX使用時にReactをインポートする必要がないため無効化
            "react/react-in-jsx-scope": "off",
            // JSXのアクセシビリティルールの一部を無効化
            "jsx-a11y/anchor-is-valid": "off",
            // 未使用変数をエラーとして報告
            "@typescript-eslint/no-unused-vars": ["error"],
            // 関数の戻り値の型を明示的に指定するルールを無効化
            "@typescript-eslint/explicit-function-return-type": ["off"],
            // モジュールの境界での型を明示的に指定するルールを無効化
            "@typescript-eslint/explicit-module-boundary-types": ["off"],
            // 空の関数を許可
            "@typescript-eslint/no-empty-function": ["off"],
            // any型の使用を許可
            "@typescript-eslint/no-explicit-any": ["off"],
            // consoleの使用を警告する
            "no-console": "warn",
            "no-debugger": "warn",
        },
        languageOptions: {
            // グローバル変数の定義
            globals: {
                ...globals.browser, // ブラウザ環境のグローバル変数
                ...globals.node, // Node.js環境のグローバル変数
                ...globals.es6, // ES6のグローバル変数
                myCustomGlobal: "readonly", // カスタムグローバル変数を読み取り専用で定義
            },
            // TypeScript用のパーサーを指定
            parser: typeScriptESLintParser, // パーサーオブジェクトを設定
        },
    },

    // features/ ディレクトリのルール
    ...featureDirectories.map((feature) => ({
        files: [`${featuresPath}/${feature}/**/*.{js,jsx,ts,tsx}`],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: [
                                ...featureDirectories
                                    .filter((dir) => dir !== feature)
                                    .flatMap((dir) => [
                                        `@/features/${dir}`, // エイリアスパス
                                        ...createRelativePaths(dir), // 相対パス
                                    ]),
                            ],
                            message: "features/から他のfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    })),

    // その他のディレクトリからfeatures内部モジュールへのアクセス制限
    {
        files: ["src/**/*.{js,jsx,ts,tsx}"],
        ignores: [`${featuresPath}/**/*.{js,jsx,ts,tsx}`],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: [`@/features/*/!(index)`, `@/features/*/*`],
                            message: "featuresモジュールはindex.tsからexportされたものだけをimportできます。",
                        },
                    ],
                },
            ],
        },
    },

    // components/ ディレクトリのルール
    {
        files: ["src/components/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "components/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/components",
                            from: "./src/features",
                            message: "components/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },

    // config/ ディレクトリのルール
    {
        files: ["src/config/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "config/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/config",
                            from: "./src/features",
                            message: "config/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },

    // hooks/ ディレクトリのルール
    {
        files: ["src/hooks/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "hooks/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/hooks",
                            from: "./src/features",
                            message: "hooks/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },

    // lib/ ディレクトリのルール
    {
        files: ["src/lib/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "lib/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/lib",
                            from: "./src/features",
                            message: "lib/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },

    // providers/ ディレクトリのルール
    {
        files: ["src/providers/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "providers/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/providers",
                            from: "./src/features",
                            message: "providers/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },

    // types/ ディレクトリのルール
    {
        files: ["src/types/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "types/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/providers",
                            from: "./src/types",
                            message: "types/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },

    // utils/ ディレクトリのルール
    {
        files: ["src/utils/**/*.{js,jsx,ts,tsx}"],
        rules: {
            "no-restricted-imports": [
                "error",
                {
                    patterns: [
                        {
                            group: ["@/features/**"],
                            message: "utils/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
            "import/no-restricted-paths": [
                "error",
                {
                    zones: [
                        {
                            target: "./src/utils",
                            from: "./src/features",
                            message: "utils/からfeatures/は参照できません。",
                        },
                    ],
                },
            ],
        },
    },
];
