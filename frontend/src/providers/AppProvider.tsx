import { ErrorBanner, ErrorFallback } from "@/components/errors";
import { Loading } from "@/components/ui";
import { theme } from "@/config/theme";
import { queryConfig } from "@/lib";
import { NotificationProvider } from "@/providers/NotificationProvider";
import { ThemeProvider } from "@emotion/react";
import { CssBaseline } from "@mui/material";
import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import dayjs from "dayjs";
import "dayjs/locale/ja";
import React, { useState } from "react";
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
        <ThemeProvider theme={theme}>
            <CssBaseline />
            <LocalizationProvider dateAdapter={AdapterDayjs} adapterLocale="ja">
                <ErrorBoundary FallbackComponent={ErrorFallback}>
                    <QueryClientProvider client={queryClient}>
                        <NotificationProvider />
                        <Loading />
                        <ErrorBanner />
                        {children}
                        <ReactQueryDevtools initialIsOpen={false} />
                    </QueryClientProvider>
                </ErrorBoundary>
            </LocalizationProvider>
        </ThemeProvider>
    );
};
