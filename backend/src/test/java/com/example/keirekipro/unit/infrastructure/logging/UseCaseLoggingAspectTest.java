package com.example.keirekipro.unit.infrastructure.logging;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.example.keirekipro.infrastructure.logging.UseCaseLoggingAspect;
import com.example.keirekipro.shared.exception.BaseException;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.aspectj.lang.ProceedingJoinPoint;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

@ExtendWith(MockitoExtension.class)
class UseCaseLoggingAspectTest {

    private UseCaseLoggingAspect aspect;

    private ListAppender<ILoggingEvent> listAppender;

    private Logger logger;

    @BeforeEach
    void setUp() {
        aspect = new UseCaseLoggingAspect();
        logger = (Logger) LoggerFactory.getLogger(UseCaseLoggingAspect.class);
        listAppender = new ListAppender<>();
        listAppender.start();
        logger.addAppender(listAppender);
        MDC.clear();
    }

    @AfterEach
    void tearDown() {
        logger.detachAppender(listAppender);
        MDC.clear();
    }

    @Test
    @DisplayName("ユースケース実行成功時、INFOログが出力される")
    void test1() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenReturn("result");

        Object result = aspect.logUsecase(pjp);

        assertThat(result).isEqualTo("result");
        assertThat(listAppender.list).hasSize(1);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getLevel()).isEqualTo(Level.INFO);
        assertThat(logEvent.getMessage()).isEqualTo("usecase");
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.action".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("usecase");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("labels.usecase".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("TestUseCase");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.outcome".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("success");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.duration".equals(kv.key)) {
                assertThat((Long) kv.value).isGreaterThanOrEqualTo(0L);
            }
        });
    }

    @Test
    @DisplayName("ユースケース実行成功時、戻り値がnullでもINFOログが出力される")
    void test2() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenReturn(null);

        Object result = aspect.logUsecase(pjp);

        assertThat(result).isNull();
        assertThat(listAppender.list).hasSize(1);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getLevel()).isEqualTo(Level.INFO);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.outcome".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("success");
            }
        });
    }

    @Test
    @DisplayName("UseCaseException発生時、WARNログが出力され例外がre-throwされる")
    void test3() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        UseCaseException exception = new UseCaseException("業務エラー");
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenThrow(exception);

        assertThatThrownBy(() -> aspect.logUsecase(pjp))
                .isSameAs(exception);

        assertThat(listAppender.list).hasSize(1);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getLevel()).isEqualTo(Level.WARN);
        assertThat(logEvent.getMessage()).isEqualTo("usecase_failed");
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.action".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("usecase");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("labels.usecase".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("TestUseCase");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("event.outcome".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("failure");
            }
        });
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("error.type".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("UseCaseException");
            }
        });
        // スタックトレースは出力されない
        assertThat(logEvent.getThrowableProxy()).isNull();
    }

    @Test
    @DisplayName("BaseExceptionのサブクラス発生時、WARNログが出力される")
    void test4() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        CustomBusinessException exception = new CustomBusinessException("カスタム業務エラー");
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenThrow(exception);

        assertThatThrownBy(() -> aspect.logUsecase(pjp))
                .isSameAs(exception);

        assertThat(listAppender.list).hasSize(1);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getLevel()).isEqualTo(Level.WARN);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("error.type".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("CustomBusinessException");
            }
        });
    }

    @Test
    @DisplayName("RuntimeException発生時、ログを出力せず例外をre-throwする")
    void test5() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        RuntimeException exception = new RuntimeException("想定外エラー");
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenThrow(exception);

        assertThatThrownBy(() -> aspect.logUsecase(pjp))
                .isSameAs(exception);

        // ログは出力されない（AppExceptionHandlerで出力する）
        assertThat(listAppender.list).isEmpty();
    }

    @Test
    @DisplayName("NullPointerException発生時、ログを出力せず例外をre-throwする")
    void test6() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        NullPointerException exception = new NullPointerException("nullエラー");
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenThrow(exception);

        assertThatThrownBy(() -> aspect.logUsecase(pjp))
                .isSameAs(exception);

        assertThat(listAppender.list).isEmpty();
    }

    @Test
    @DisplayName("チェック例外発生時、ログを出力せず例外をre-throwする")
    void test7() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new TestUseCase();
        Exception exception = new Exception("チェック例外");
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenThrow(exception);

        assertThatThrownBy(() -> aspect.logUsecase(pjp))
                .isSameAs(exception);

        assertThat(listAppender.list).isEmpty();
    }

    @Test
    @DisplayName("ターゲットクラス名がユースケース名として出力される")
    void test8() throws Throwable {
        ProceedingJoinPoint pjp = mock(ProceedingJoinPoint.class);
        Object target = new AnotherTestUseCase();
        when(pjp.getTarget()).thenReturn(target);
        when(pjp.proceed()).thenReturn("result");

        aspect.logUsecase(pjp);

        ILoggingEvent logEvent = listAppender.list.get(0);
        assertThat(logEvent.getKeyValuePairs()).anySatisfy(kv -> {
            if ("labels.usecase".equals(kv.key)) {
                assertThat(kv.value).isEqualTo("AnotherTestUseCase");
            }
        });
    }

    // テスト用のダミークラス
    static class TestUseCase {
        public Object execute() {
            return "result";
        }
    }

    static class AnotherTestUseCase {
        public Object execute() {
            return "another result";
        }
    }

    // BaseExceptionを継承したカスタム例外
    static class CustomBusinessException extends BaseException {
        public CustomBusinessException(String message) {
            super(message);
        }
    }
}
