import { ErrorFallback } from "@/components/errors";
import { theme } from "@/config/theme";
import { queryConfig } from "@/lib";
import { ThemeProvider } from "@emotion/react";
import { CircularProgress, CssBaseline } from "@mui/material";
import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import dayjs from "dayjs";
import "dayjs/locale/ja";
import React, { Suspense, useState } from "react";
import { ErrorBoundary } from "react-error-boundary";

/**
 * ロケールを日本に変更
 */
dayjs.locale("ja");

/**
 * アプリケーション全体のProvider
 */
export const AppProvider = ({ children }: { children: React.ReactNode }) => {
    // Query Clientインスタンス
    const [queryClient] = useState(() => new QueryClient({ defaultOptions: queryConfig }));
    return (
        <Suspense fallback={<CircularProgress />}>
            <ErrorBoundary FallbackComponent={ErrorFallback}>
                <QueryClientProvider client={queryClient}>
                    <ThemeProvider theme={theme}>
                        <LocalizationProvider dateAdapter={AdapterDayjs} adapterLocale="ja">
                            <CssBaseline />
                            {children}
                        </LocalizationProvider>
                    </ThemeProvider>
                    <ReactQueryDevtools initialIsOpen={false} />
                </QueryClientProvider>
            </ErrorBoundary>
        </Suspense>
    );
};
