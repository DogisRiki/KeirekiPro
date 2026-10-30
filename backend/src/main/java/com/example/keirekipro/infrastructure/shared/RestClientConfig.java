package com.example.keirekipro.infrastructure.shared;

import java.time.Duration;

import tools.jackson.databind.json.JsonMapper;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.http.converter.json.JacksonJsonHttpMessageConverter;
import org.springframework.web.client.RestClient;

/**
 * RestClient設定クラス
 */
@Configuration
public class RestClientConfig {

    /**
     * RestClientのBeanを提供する
     *
     * @param jsonMapper Spring Bootが作るJSON変換用のJsonMapper
     * @return RestClient
     */
    @Bean
    RestClient restClient(JsonMapper jsonMapper) {
        // リクエストファクトリの構成（タイムアウト設定）
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout((int) Duration.ofSeconds(10).toMillis());
        requestFactory.setReadTimeout((int) Duration.ofSeconds(10).toMillis());

        // RestClient.Builderの構築
        return RestClient.builder()
                // ステータスコードが4xx/5xxでも例外をスローしないように設定
                .defaultStatusHandler(status -> true, (request, response) -> {
                    // エラーレスポンスはbodyで取得して処理するため、ここでは何もしない
                })
                .requestFactory(requestFactory)
                // JSONの変換器にはSpring BootのJsonMapperを使う。ほかの変換器(フォームの送信など)は既定のまま残す
                .configureMessageConverters(converters -> converters
                        .registerDefaults()
                        .withJsonConverter(new JacksonJsonHttpMessageConverter(jsonMapper)))
                .build();
    }
}
