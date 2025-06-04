import { createErrorInterceptor } from "@/lib";
import axios from "axios";

/**
 * アプリ共通ベースクライアント
 */
export const baseApiClient = axios.create({
    baseURL: import.meta.env.VITE_API_URL,
    headers: { "Content-Type": "application/json" },
});

baseApiClient.interceptors.response.use((response) => response, createErrorInterceptor());
