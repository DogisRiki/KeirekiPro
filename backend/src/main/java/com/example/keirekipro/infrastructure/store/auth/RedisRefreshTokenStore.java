package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.shared.utils.SecurityUtil;
import com.example.keirekipro.usecase.auth.dto.RefreshTokenInfo;
import com.example.keirekipro.usecase.auth.store.RefreshTokenStore;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * リフレッシュトークン保管ストアのRedis実装
 */
@Component
@RequiredArgsConstructor
public class RedisRefreshTokenStore implements RefreshTokenStore {

    private final SecurityUtil securityUtil;

    private final RedisTemplate<String, Object> redisTemplate;

    @Value("${jwt.refresh-token-validity-in-days}")
    private long refreshTokenValidityInDays;

    private static final String TOKEN_KEY_PREFIX = "refresh-token:";
    private static final String USER_TOKENS_KEY_PREFIX = "user-refresh-tokens:";

    private static final String FIELD_USER_ID = "userId";
    private static final String FIELD_ROLES = "roles";
    private static final String FIELD_TOKEN_VERSION = "tokenVersion";

    @Override
    public String issue(UUID userId, Set<String> roles, long tokenVersion) {

        // 不透明トークンを生成
        String token = securityUtil.generateRandomToken();

        // トークン本体を保存
        String tokenKey = TOKEN_KEY_PREFIX + token;
        redisTemplate.opsForHash().put(tokenKey, FIELD_USER_ID, userId.toString());
        redisTemplate.opsForHash().put(tokenKey, FIELD_ROLES, String.join(",", roles));
        redisTemplate.opsForHash().put(tokenKey, FIELD_TOKEN_VERSION, String.valueOf(tokenVersion));

        Duration ttl = Duration.ofDays(refreshTokenValidityInDays);
        redisTemplate.expire(tokenKey, ttl);

        // ユーザー単位の所持トークンSetに登録
        String userTokensKey = USER_TOKENS_KEY_PREFIX + userId;
        redisTemplate.opsForSet().add(userTokensKey, token);
        redisTemplate.expire(userTokensKey, ttl);

        return token;
    }

    @Override
    public Optional<RefreshTokenInfo> find(String token) {

        String tokenKey = TOKEN_KEY_PREFIX + token;

        Object userIdObj = redisTemplate.opsForHash().get(tokenKey, FIELD_USER_ID);
        Object rolesObj = redisTemplate.opsForHash().get(tokenKey, FIELD_ROLES);
        Object tokenVersionObj = redisTemplate.opsForHash().get(tokenKey, FIELD_TOKEN_VERSION);

        if (!(userIdObj instanceof String userIdStr)
                || !(rolesObj instanceof String rolesStr)
                || !(tokenVersionObj instanceof String tokenVersionStr)) {
            return Optional.empty();
        }

        UUID userId = UUID.fromString(userIdStr);
        Set<String> roles = rolesStr.isEmpty() ? Set.of() : Set.of(rolesStr.split(","));
        long tokenVersion = Long.parseLong(tokenVersionStr);

        return Optional.of(new RefreshTokenInfo(userId, roles, tokenVersion));
    }

    @Override
    public void remove(String token) {

        String tokenKey = TOKEN_KEY_PREFIX + token;

        // ユーザーIDを取得してから削除する
        Object userIdObj = redisTemplate.opsForHash().get(tokenKey, FIELD_USER_ID);

        redisTemplate.delete(tokenKey);

        if (userIdObj instanceof String userIdStr) {
            String userTokensKey = USER_TOKENS_KEY_PREFIX + userIdStr;
            redisTemplate.opsForSet().remove(userTokensKey, token);
        }
    }

    @Override
    public void removeAllByUser(UUID userId) {

        String userTokensKey = USER_TOKENS_KEY_PREFIX + userId;

        // 該当ユーザーのトークン一覧を取得
        Set<Object> tokens = redisTemplate.opsForSet().members(userTokensKey);
        if (tokens != null) {
            for (Object t : tokens) {
                if (t instanceof String tokenStr) {
                    redisTemplate.delete(TOKEN_KEY_PREFIX + tokenStr);
                }
            }
        }

        // ユーザー単位の所持トークンSetも削除
        redisTemplate.delete(userTokensKey);
    }
}
