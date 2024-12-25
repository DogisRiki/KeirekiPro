import { fixupConfigRules, fixupPluginRules } from "@eslint/compat";
import { FlatCompat } from "@eslint/eslintrc";
import js from "@eslint/js";
import typescriptEslint from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const compat = new FlatCompat({
    baseDirectory: __dirname,
    recommendedConfig: js.configs.recommended,
    allConfig: js.configs.all,
});

export default [
    {
        ignores: ["**/build/", "**/public/", "**/node_modules/", "**/*.min.js", "**/.*lintrc.js"],
    },
    ...fixupConfigRules(
        compat.extends(
            "eslint:recommended",
            "plugin:react/recommended",
            "plugin:react-hooks/recommended",
            "plugin:@typescript-eslint/recommended",
            "prettier",
        ),
    ),
    {
        plugins: {
            react: fixupPluginRules(react),
            "react-hooks": fixupPluginRules(reactHooks),
            "@typescript-eslint": fixupPluginRules(typescriptEslint),
        },

        languageOptions: {
            globals: {
                ...globals.browser,
            },

            parser: tsParser,
            ecmaVersion: "latest",
            sourceType: "module",
        },

        settings: {
            react: {
                version: "detect",
            },
        },

        rules: {
            "react/react-in-jsx-scope": "off",
            "no-console": "warn",
            "no-debugger": "warn",
            "react/prop-types": "error",
            "no-process-exit": "error",
        },
    },
];
