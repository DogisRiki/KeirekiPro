package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.List;
import java.util.Optional;

import com.example.keirekipro.usecase.auth.oidc.OidcAuthorizationSession;
import com.example.keirekipro.usecase.auth.store.OidcAuthorizationSessionStore;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * OIDC認可セッションのRedis実装
 */
@Component
@RequiredArgsConstructor
public class RedisOidcAuthorizationSessionStore implements OidcAuthorizationSessionStore {

    private final RedisTemplate<String, Object> redisTemplate;

    private static final String STATE_KEY_PREFIX = "oidc:state:";
    private static final String PROVIDER_KEY_PREFIX = "oidc:provider:";
    private static final String CODE_VERIFIER_KEY_PREFIX = "oidc:code_verifier:";

    @Override
    public void store(String state, String provider, String codeVerifier, Duration ttl) {

        // コールバック時にどのプロバイダーの認証フローかを判断する為にプロバイダー名を保存
        redisTemplate.opsForValue().set(PROVIDER_KEY_PREFIX + state, provider, ttl);
        // stateを保存
        redisTemplate.opsForValue().set(STATE_KEY_PREFIX + state, state, ttl);
        // code_verifierを保存
        redisTemplate.opsForValue().set(CODE_VERIFIER_KEY_PREFIX + state, codeVerifier, ttl);
    }

    @Override
    public Optional<OidcAuthorizationSession> find(String state) {

        // stateの検証（stateKeyが無ければ失敗）
        Boolean exists = redisTemplate.hasKey(STATE_KEY_PREFIX + state);
        if (!Boolean.TRUE.equals(exists)) {
            return Optional.empty();
        }

        Object providerObj = redisTemplate.opsForValue().get(PROVIDER_KEY_PREFIX + state);
        Object codeVerifierObj = redisTemplate.opsForValue().get(CODE_VERIFIER_KEY_PREFIX + state);

        if (!(providerObj instanceof String provider) || !(codeVerifierObj instanceof String codeVerifier)) {
            return Optional.empty();
        }

        return Optional.of(OidcAuthorizationSession.builder()
                .state(state)
                .provider(provider)
                .codeVerifier(codeVerifier)
                .build());
    }

    @Override
    public void remove(String state) {

        // 使用済みのstateとpkce関連のデータを削除
        redisTemplate.delete(List.of(
                STATE_KEY_PREFIX + state,
                PROVIDER_KEY_PREFIX + state,
                CODE_VERIFIER_KEY_PREFIX + state));
    }
}
