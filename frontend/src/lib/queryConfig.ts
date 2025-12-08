import type { DefaultOptions } from "@tanstack/react-query";

/**
 * React Query基本設定
 */
export const queryConfig = {
    queries: {
        refetchOnWindowFocus: false, // ブラウザのウィンドウのフォーカス時の再フェッチを無効化
        retry: false, // クエリ失敗時の自動リトライを無効化
        staleTime: 1000 * 60, // 1分間キャッシュする
    },
} satisfies DefaultOptions;
