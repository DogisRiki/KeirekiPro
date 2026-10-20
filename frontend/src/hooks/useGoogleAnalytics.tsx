import { env } from "@/config/env";
import { toAnalyticsLocation, toAnalyticsPath } from "@/utils";
import { useEffect } from "react";
import ReactGA from "react-ga4";
import { useLocation } from "react-router";

/**
 * Google Analyticsによるページ遷移を追跡するカスタムフック
 * 送るのはページのパスだけで、クエリ文字列とハッシュは送らない
 */
export const useGoogleAnalytics = () => {
    const { pathname } = useLocation();

    useEffect(() => {
        if (!env.GA_MEASUREMENT_ID) return;
        const page = toAnalyticsPath(pathname);
        const location = toAnalyticsLocation(window.location.origin, pathname);
        ReactGA.set({ page_location: location });
        ReactGA.send({ hitType: "pageview", page, location });
    }, [pathname]);
};

export const GoogleAnalytics = () => {
    useGoogleAnalytics();
    return null;
};
