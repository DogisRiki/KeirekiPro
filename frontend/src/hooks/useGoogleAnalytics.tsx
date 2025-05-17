import { env } from "@/config/env";
import { useEffect } from "react";
import ReactGA from "react-ga4";
import { useLocation } from "react-router";

/**
 * Google Analyticsによるページ遷移を追跡するカスタムフック
 */
export const useGoogleAnalytics = () => {
    const location = useLocation();

    useEffect(() => {
        if (!env.GA_MEASUREMENT_ID) return;
        ReactGA.send({ hitType: "pageview", page: location.pathname + location.search });
    }, [location]);
};

export const GoogleAnalytics = () => {
    useGoogleAnalytics();
    return null;
};
