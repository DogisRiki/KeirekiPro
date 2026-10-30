package com.example.keirekipro.infrastructure.shared.json;

import tools.jackson.core.json.JsonWriteFeature;

import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * JsonMapper設定クラス
 *
 * spring.jackson.use-jackson2-defaults で戻せないJackson 3の既定を、Spring Bootが作るJsonMapperに設定する
 */
@Configuration
public class JsonMapperConfig {

    /**
     * 絵文字のようなサロゲートの対を、UTF-8のバイトに書くときもJackson 2と同じく \\uXXXX\\uXXXX の形で書く設定を返す
     *
     * @return JsonMapperBuilderCustomizer
     */
    @Bean
    JsonMapperBuilderCustomizer surrogateCompatibleJsonMapperCustomizer() {
        return builder -> builder.disable(JsonWriteFeature.COMBINE_UNICODE_SURROGATES_IN_UTF8);
    }
}
