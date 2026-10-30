package com.example.keirekipro.infrastructure.logging;

import java.util.concurrent.TimeUnit;

import com.example.keirekipro.shared.exception.BaseException;

import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * ユースケース実行ログ
 *
 * 対象:
 * - com.example.keirekipro.usecase..*.execute(..)
 * 除外:
 * - com.example.keirekipro.usecase.query..*
 *
 * 出力:
 * - 成功: INFO
 * - 想定内失敗: WARN（スタックトレース無し）
 * - 想定外失敗: ここでは出さない（ERROR二重化防止。AppExceptionHandler側で出す）
 */
@Aspect
@Component
public class UseCaseLoggingAspect {

    private static final Logger LOGGER = LoggerFactory.getLogger(UseCaseLoggingAspect.class);

    /**
     * ユースケースの {@code execute(..)} を横断し、ログを出力する
     *
     * @param pjp 実行対象のJoinPoint
     * @return execute(..)の戻り値
     * @throws Throwable execute(..)が送出した例外
     */
    @Around("""
            execution(* com.example.keirekipro.usecase..*.execute(..))
            && !within(com.example.keirekipro.usecase.query..*)
            """)
    public Object logUsecase(ProceedingJoinPoint pjp) throws Throwable {
        long startNs = System.nanoTime();
        String usecase = pjp.getTarget().getClass().getSimpleName();

        try {
            Object result = pjp.proceed();

            long durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNs);
            LOGGER.atInfo()
                    .setMessage("usecase")
                    .addKeyValue("event.action", "usecase")
                    .addKeyValue("labels.usecase", usecase)
                    .addKeyValue("event.outcome", "success")
                    .addKeyValue("event.duration", durationMs)
                    .log();

            return result;
        } catch (BaseException ex) {
            // 想定内失敗: WARN（スタックトレース無し）
            long durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNs);
            LOGGER.atWarn()
                    .setMessage("usecase_failed")
                    .addKeyValue("event.action", "usecase")
                    .addKeyValue("labels.usecase", usecase)
                    .addKeyValue("event.outcome", "failure")
                    .addKeyValue("event.duration", durationMs)
                    .addKeyValue("error.type", ex.getClass().getSimpleName())
                    .log();
            throw ex;
        }
        // 想定外例外はcatchしない（そのままスローし、AppExceptionHandlerでERRORログを出力）
    }
}
