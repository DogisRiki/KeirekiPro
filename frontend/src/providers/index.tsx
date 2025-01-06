import { AppProvider } from "@/providers/AppProvider";
import { AppRouter } from "@/routes/AppRouter";

/**
 * アプリケーションエンドポイント
 */
export const App = () => {
    return (
        <AppProvider>
            <AppRouter />
        </AppProvider>
    );
};
