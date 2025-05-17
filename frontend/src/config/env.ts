/**
 * 環境変数
 */
const createEnv = () => {
    const env = {
        APP_NAME: import.meta.env.VITE_APP_NAME,
        API_URL: import.meta.env.VITE_API_URL,
        APP_EMAIL: import.meta.env.VITE_APP_CONTACT_EMAIL,
        APP_URL: import.meta.env.VITE_APP_URL,
        GA_MEASUREMENT_ID: import.meta.env.VITE_GA_MEASUREMENT_ID,
    };

    // 必須変数のチェック
    if (!env.API_URL) {
        throw new Error("API_URL is required but not provided.");
    }

    return env;
};

export const env = createEnv();
