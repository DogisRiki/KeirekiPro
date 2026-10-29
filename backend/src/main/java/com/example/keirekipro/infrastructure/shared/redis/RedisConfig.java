package com.example.keirekipro.infrastructure.shared.redis;

import tools.jackson.databind.json.JsonMapper;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.JacksonJsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

/**
 * Redis設定クラス
 */
@Configuration
public class RedisConfig {

    /**
     * RedisTemplateをカスタマイズしたBeanを提供する
     *
     * キーには文字列シリアライザを、値にはJacksonのJSONシリアライザを使用することで、
     * 効率的なデータの保存と取得を実現する
     *
     * @param connectionFactory 接続ファクトリ
     * @param jsonMapper Spring Bootが作るJSON変換用のJsonMapper
     * @return RedisTemplateオブジェクト
     */
    @Bean
    RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory, JsonMapper jsonMapper) {

        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);

        // RedisにオブジェクトをJSON形式で保存できるようにする
        JacksonJsonRedisSerializer<Object> jacksonJsonRedisSerializer = new JacksonJsonRedisSerializer<>(
                jsonMapper, Object.class);

        // キーを文字列として扱うためのシリアライザ
        StringRedisSerializer stringRedisSerializer = new StringRedisSerializer();

        // テンプレートの各操作に適切なシリアライザを設定
        template.setKeySerializer(stringRedisSerializer); // キー
        template.setValueSerializer(jacksonJsonRedisSerializer); // 値
        template.setHashKeySerializer(stringRedisSerializer); // Hashのキー
        template.setHashValueSerializer(jacksonJsonRedisSerializer); // Hashの値
        template.afterPropertiesSet();
        return template;
    }
}
