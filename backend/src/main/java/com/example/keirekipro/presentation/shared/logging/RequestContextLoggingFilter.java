package com.example.keirekipro.presentation.shared.logging;

import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpHeaders;
import org.springframework.lang.NonNull;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletResponseWrapper;

/**
 * リクエストコンテキスト（requestId/userId）をMDCへ格納し、アクセスログを1リクエスト=1行で出力するフィルタ
 *
 * - requestId: labels.request_id（X-Request-Id）
 * - userId: user.id（UUID文字列のみ）
 * - access log: event.action=http_request（INFO）
 */
@Component
public class RequestContextLoggingFilter extends OncePerRequestFilter {

    private static final Logger LOGGER = LoggerFactory.getLogger(RequestContextLoggingFilter.class);

    public static final String REQUEST_ID_HEADER = "X-Request-Id";
    public static final String MDC_REQUEST_ID_KEY = "labels.request_id";
    public static final String MDC_USER_ID_KEY = "user.id";

    @Override
    protected boolean shouldNotFilter(@NonNull HttpServletRequest request) {
        // OPTIONS は除外
        return "OPTIONS".equalsIgnoreCase(request.getMethod());
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        long startNs = System.nanoTime();

        String requestId = resolveOrGenerateRequestId(request);
        MDC.put(MDC_REQUEST_ID_KEY, requestId);
        response.setHeader(REQUEST_ID_HEADER, requestId);

        // 認証後（JwtAuthenticationFilterの後段で実行される前提）にuserIdをMDCへ
        putUserIdIfAuthenticated();

        StatusCaptureResponseWrapper responseWrapper = new StatusCaptureResponseWrapper(response);

        try {
            filterChain.doFilter(request, responseWrapper);
        } finally {
            long durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNs);

            String clientIp = resolveClientIp(request);
            String userAgent = request.getHeader(HttpHeaders.USER_AGENT);

            LOGGER.atInfo()
                    .setMessage("http_request")
                    .addKeyValue("event.action", "http_request")
                    .addKeyValue("http.request.method", request.getMethod())
                    .addKeyValue("url.path", request.getRequestURI())
                    .addKeyValue("http.response.status_code", responseWrapper.getStatus())
                    .addKeyValue("event.duration", durationMs)
                    .addKeyValue("client.address", clientIp)
                    .addKeyValue("user_agent.original", userAgent)
                    .log();

            // Thread再利用に備えてクリア
            MDC.remove(MDC_USER_ID_KEY);
            MDC.remove(MDC_REQUEST_ID_KEY);
        }
    }

    private static String resolveOrGenerateRequestId(HttpServletRequest request) {
        String incoming = request.getHeader(REQUEST_ID_HEADER);
        if (incoming != null && !incoming.isBlank()) {
            return incoming.trim();
        }
        return UUID.randomUUID().toString();
    }

    private static void putUserIdIfAuthenticated() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            return;
        }

        // PII防止のためUUIDとして解釈できる場合のみuser.idに入れる
        String candidate = authentication.getPrincipal() instanceof String s
                ? s
                : authentication.getName();

        if (candidate == null || candidate.isBlank()) {
            return;
        }

        String trimmed = candidate.trim();
        if (isUuid(trimmed)) {
            MDC.put(MDC_USER_ID_KEY, trimmed);
        }
    }

    private static boolean isUuid(String value) {
        try {
            UUID.fromString(value);
            return true;
        } catch (IllegalArgumentException ex) {
            return false;
        }
    }

    private static String resolveClientIp(HttpServletRequest request) {
        // 実行基盤（ALB等）を想定し、X-Forwarded-Forを優先
        String xff = request.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isBlank()) {
            // 先頭がクライアントIP
            int comma = xff.indexOf(',');
            return (comma >= 0 ? xff.substring(0, comma) : xff).trim();
        }
        return request.getRemoteAddr();
    }

    /**
     * ステータスコードを確実に取得するためのResponseWrapper
     */
    private static final class StatusCaptureResponseWrapper extends HttpServletResponseWrapper {

        private int httpStatus = HttpServletResponse.SC_OK;

        private StatusCaptureResponseWrapper(HttpServletResponse response) {
            super(response);
        }

        @Override
        public void setStatus(int sc) {
            this.httpStatus = sc;
            super.setStatus(sc);
        }

        @Override
        public void sendError(int sc) throws IOException {
            this.httpStatus = sc;
            super.sendError(sc);
        }

        @Override
        public void sendError(int sc, String msg) throws IOException {
            this.httpStatus = sc;
            super.sendError(sc, msg);
        }

        @Override
        public void sendRedirect(String location) throws IOException {
            this.httpStatus = HttpServletResponse.SC_FOUND;
            super.sendRedirect(location);
        }

        @Override
        public int getStatus() {
            return this.httpStatus;
        }
    }
}
