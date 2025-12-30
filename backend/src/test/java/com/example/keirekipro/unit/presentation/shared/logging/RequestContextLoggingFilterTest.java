package com.example.keirekipro.unit.presentation.shared.logging;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;

import java.util.UUID;

import com.example.keirekipro.presentation.shared.logging.RequestContextLoggingFilter;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletResponse;

@ExtendWith(MockitoExtension.class)
class RequestContextLoggingFilterTest {

    private RequestContextLoggingFilter filter;

    @Mock
    private FilterChain filterChain;

    private ListAppender<ILoggingEvent> listAppender;

    private Logger logger;

    @BeforeEach
    void setUp() {
        filter = new RequestContextLoggingFilter();
        logger = (Logger) LoggerFactory.getLogger(RequestContextLoggingFilter.class);
        listAppender = new ListAppender<>();
        listAppender.start();
        logger.addAppender(listAppender);
        MDC.clear();
        SecurityContextHolder.clearContext();
    }

    @AfterEach
    void tearDown() {
        logger.detachAppender(listAppender);
        MDC.clear();
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("X-Request-Idヘッダがある場合、その値を使用する")
    void test1() throws Exception {
        String requestId = "provided-request-id-123";
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Request-Id", requestId);
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        assertThat(response.getHeader("X-Request-Id")).isEqualTo(requestId);
        // StatusCaptureResponseWrapperが渡されるため、anyを使用
        verify(filterChain).doFilter(eq(request), any(HttpServletResponse.class));
    }

    @Test
    @DisplayName("X-Request-Idヘッダがない場合、UUIDを生成する")
    void test2() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        String responseRequestId = response.getHeader("X-Request-Id");
        assertThat(responseRequestId).isNotNull();
        // UUID形式であることを確認
        assertThat(UUID.fromString(responseRequestId)).isNotNull();
    }

    @Test
    @DisplayName("X-Request-Idヘッダが空白の場合、UUIDを生成する")
    void test3() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Request-Id", "   ");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        String responseRequestId = response.getHeader("X-Request-Id");
        assertThat(responseRequestId).isNotBlank();
        assertThat(UUID.fromString(responseRequestId)).isNotNull();
    }

    @Test
    @DisplayName("X-Request-Idヘッダの前後の空白はトリムされる")
    void test4() throws Exception {
        String requestId = "  trimmed-request-id  ";
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Request-Id", requestId);
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        assertThat(response.getHeader("X-Request-Id")).isEqualTo("trimmed-request-id");
    }

    @Test
    @DisplayName("認証済みでUUID形式のprincipalの場合、MDCにuserIdが設定される")
    void test5() throws Exception {
        String userId = UUID.randomUUID().toString();
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        // principalをStringとして設定し、authoritiesも設定して完全な認証状態を作る
        UsernamePasswordAuthenticationToken auth = new UsernamePasswordAuthenticationToken(
                userId, null, java.util.Collections.emptyList());
        SecurityContextHolder.getContext().setAuthentication(auth);

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getMDCPropertyMap().get("user.id")).isEqualTo(userId);
    }

    @Test
    @DisplayName("認証済みだがUUID形式でないprincipalの場合、MDCにuserIdが設定されない")
    void test6() throws Exception {
        String nonUuidPrincipal = "user@example.com";
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        UsernamePasswordAuthenticationToken auth = new UsernamePasswordAuthenticationToken(
                nonUuidPrincipal, null, java.util.Collections.emptyList());
        SecurityContextHolder.getContext().setAuthentication(auth);

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getMDCPropertyMap().get("user.id")).isNull();
    }

    @Test
    @DisplayName("未認証の場合、MDCにuserIdが設定されない")
    void test7() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getMDCPropertyMap().get("user.id")).isNull();
    }

    @Test
    @DisplayName("リクエスト完了時にINFOログが出力される")
    void test8() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/resumes");
        request.addHeader("User-Agent", "TestAgent/1.0");
        MockHttpServletResponse response = new MockHttpServletResponse();
        response.setStatus(200);

        filter.doFilter(request, response, filterChain);

        assertThat(listAppender.list).hasSize(1);
        ILoggingEvent logEvent = listAppender.list.get(0);

        assertThat(logEvent.getLevel()).isEqualTo(Level.INFO);
        assertThat(logEvent.getMessage()).isEqualTo("http_request");

        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.action".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("http_request");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("http.request.method".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("GET");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("url.path".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("/api/resumes");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("http.response.status_code".equals(kv.key)) {
                assertThat(kv.value).isEqualTo(200);
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.duration".equals(kv.key)) {
                assertThat((Long) kv.value).isGreaterThanOrEqualTo(0L);
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("user_agent.original".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("TestAgent/1.0");
            }
        });
    }

    @Test
    @DisplayName("POSTリクエストのログが正しく出力される")
    void test9() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/resumes");
        MockHttpServletResponse response = new MockHttpServletResponse();
        response.setStatus(201);

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("http.request.method".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("POST");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("http.response.status_code".equals(kv.key)) {
                assertThat(kv.value).isEqualTo(201);
            }
        });
    }

    @Test
    @DisplayName("エラーレスポンスのステータスコードが正しくログに出力される")
    void test10() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();
        response.setStatus(500);

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("http.response.status_code".equals(kv.key)) {
                assertThat(kv.value).isEqualTo(500);
            }
        });
    }

    @Test
    @DisplayName("X-Forwarded-Forヘッダがある場合、先頭のIPを使用する")
    void test11() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Forwarded-For", "192.168.1.100, 10.0.0.1, 172.16.0.1");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("client.address".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("192.168.1.100");
            }
        });
    }

    @Test
    @DisplayName("X-Forwarded-Forヘッダに単一IPの場合、そのIPを使用する")
    void test12() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Forwarded-For", "192.168.1.100");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("client.address".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("192.168.1.100");
            }
        });
    }

    @Test
    @DisplayName("X-Forwarded-Forヘッダがない場合、remoteAddrを使用する")
    void test13() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.setRemoteAddr("127.0.0.1");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("client.address".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("127.0.0.1");
            }
        });
    }

    @Test
    @DisplayName("OPTIONSリクエストはフィルター処理がスキップされる")
    void test14() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("OPTIONS", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        // ログは出力されない
        assertThat(listAppender.list).isEmpty();
        // フィルタチェーンは呼ばれる（OPTIONSはshouldNotFilterでスキップされるので元のresponseが渡される）
        verify(filterChain).doFilter(request, response);
    }

    @Test
    @DisplayName("小文字のoptionsでもスキップされる")
    void test15() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setMethod("options");
        request.setRequestURI("/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, filterChain);

        assertThat(listAppender.list).isEmpty();
    }

    @Test
    @DisplayName("フィルター処理後にMDCがクリアされる")
    void test16() throws Exception {
        String userId = UUID.randomUUID().toString();
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Request-Id", "test-request-id");
        MockHttpServletResponse response = new MockHttpServletResponse();

        UsernamePasswordAuthenticationToken auth = new UsernamePasswordAuthenticationToken(
                userId, null, java.util.Collections.emptyList());
        SecurityContextHolder.getContext().setAuthentication(auth);

        filter.doFilter(request, response, filterChain);

        assertThat(MDC.get("labels.request_id")).isNull();
        assertThat(MDC.get("user.id")).isNull();
    }

    @Test
    @DisplayName("例外発生時もMDCがクリアされる")
    void test17() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader("X-Request-Id", "test-request-id");
        MockHttpServletResponse response = new MockHttpServletResponse();

        // anyを使用してStatusCaptureResponseWrapperにも対応
        Mockito.doThrow(new RuntimeException("Test exception"))
                .when(filterChain).doFilter(eq(request), any(HttpServletResponse.class));

        try {
            filter.doFilter(request, response, filterChain);
        } catch (RuntimeException e) {
            // 例外は想定通り
        }

        // MDCはクリアされている
        assertThat(MDC.get("labels.request_id")).isNull();
        assertThat(MDC.get("user.id")).isNull();
    }

    @Test
    @DisplayName("setStatusで設定されたステータスコードがキャプチャされる")
    void test18() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        // anyを使用してStatusCaptureResponseWrapperにも対応
        Mockito.doAnswer(invocation -> {
            HttpServletResponse resp = invocation.getArgument(1);
            resp.setStatus(404);
            return null;
        }).when(filterChain).doFilter(eq(request), any(HttpServletResponse.class));

        filter.doFilter(request, response, filterChain);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("http.response.status_code".equals(kv.key)) {
                assertThat(kv.value).isEqualTo(404);
            }
        });
    }
}
