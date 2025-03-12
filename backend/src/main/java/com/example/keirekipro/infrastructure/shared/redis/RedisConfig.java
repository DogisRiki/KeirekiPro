package com.example.keirekipro.infrastructure.shared.redis;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.Jackson2JsonRedisSerializer;
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
     * 効率的なデータの保存と取得を実現する。
     *
     * @param connectionFactory 接続ファクトリ
     * @return RedisTemplateオブジェクト
     */
    @Bean
    RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory) {

        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);

        // JSON変換用のObjectMapperを構成
        ObjectMapper objectMapper = new ObjectMapper();
        // Java8の日時クラスをJSONに変換するためのモジュールを登録
        objectMapper.registerModule(new JavaTimeModule());

        // RedisにオブジェクトをJSON形式で保存できるようにする
        Jackson2JsonRedisSerializer<Object> jackson2JsonRedisSerializer = new Jackson2JsonRedisSerializer<>(
                objectMapper, Object.class);

        // キーを文字列として扱うためのシリアライザ
        StringRedisSerializer stringRedisSerializer = new StringRedisSerializer();

        // テンプレートの各操作に適切なシリアライザを設定
        template.setKeySerializer(stringRedisSerializer); // キー
        template.setValueSerializer(jackson2JsonRedisSerializer); // 値
        template.setHashKeySerializer(stringRedisSerializer); // Hashのキー
        template.setHashValueSerializer(jackson2JsonRedisSerializer); // Hashの値
        template.afterPropertiesSet();
        return template;
    }
}
