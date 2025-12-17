package com.example.keirekipro.presentation.shared.dev;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Profile;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import lombok.RequiredArgsConstructor;

/**
 * 開発時にエンドポイントログを出力する
 */
@Component
@Profile("dev")
@RequiredArgsConstructor
public class ControllerEndpointLogger {

    private static final Logger log = LoggerFactory.getLogger(ControllerEndpointLogger.class);

    private final RequestMappingHandlerMapping requestMappingHandlerMapping;

    /**
     * アプリケーション起動完了時に、コントローラがリッスンしているエンドポイント一覧をログ出力する
     */
    @EventListener(ApplicationReadyEvent.class)
    public void logEndpoints() {
        for (Map.Entry<RequestMappingInfo, HandlerMethod> entry : requestMappingHandlerMapping.getHandlerMethods()
                .entrySet()) {

            RequestMappingInfo info = entry.getKey();
            HandlerMethod method = entry.getValue();

            log.info("Endpoint: {} {} -> {}#{}",
                    info.getMethodsCondition(),
                    info.getPathPatternsCondition(),
                    method.getBeanType().getSimpleName(),
                    method.getMethod().getName());
        }
    }
}
