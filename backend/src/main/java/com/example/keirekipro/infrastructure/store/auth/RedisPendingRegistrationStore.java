package com.example.keirekipro.infrastructure.store.auth;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.PendingRegistration;
import com.example.keirekipro.usecase.auth.store.PendingRegistrationStore;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.json.JsonMapper;

import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redis確認前の登録ストア
 */
@Component
@RequiredArgsConstructor
public class RedisPendingRegistrationStore implements PendingRegistrationStore {

    /**
     * 確認前の登録用キー接頭辞
     */
    private static final String PREFIX = "pending-registration:";

    /**
     * メールアドレスごとの登録のIDの集合用キー接頭辞
     */
    private static final String EMAIL_PREFIX = "pending-registration:email:";

    /**
     * Redisテンプレート
     */
    private final RedisTemplate<String, Object> redisTemplate;

    /**
     * JSONシリアライザ
     */
    private final JsonMapper jsonMapper;

    /**
     * 登録を置く。同じIDの登録があれば上書きする
     *
     * @param registration 確認前の登録
     * @param ttl 有効期限
     */
    @Override
    public void save(PendingRegistration registration, Duration ttl) {
        String json;
        try {
            json = jsonMapper.writeValueAsString(registration);
        } catch (JacksonException e) {
            throw new IllegalStateException("確認前の登録のシリアライズに失敗しました。", e);
        }
        redisTemplate.opsForValue().set(PREFIX + registration.id(), json, ttl);

        String emailKey = EMAIL_PREFIX + registration.email();
        redisTemplate.opsForSet().add(emailKey, registration.id().toString());
        redisTemplate.expire(emailKey, ttl);
    }

    /**
     * IDで登録を読む
     *
     * @param id 登録のID
     * @return 登録（存在しない場合はempty）
     */
    @Override
    public Optional<PendingRegistration> findById(UUID id) {
        Object value = redisTemplate.opsForValue().get(PREFIX + id);
        if (value == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(jsonMapper.readValue((String) value, PendingRegistration.class));
        } catch (JacksonException e) {
            return Optional.empty();
        }
    }

    /**
     * メールアドレスの登録を、作った日時の新しい順に返す
     * 有効期限で消えていた登録のIDは、集合から取り除く
     *
     * @param email メールアドレス
     * @param limit 返す件数の上限
     * @return 登録の一覧
     */
    @Override
    public List<PendingRegistration> findByEmail(String email, int limit) {
        String emailKey = EMAIL_PREFIX + email;
        Set<Object> members = redisTemplate.opsForSet().members(emailKey);
        if (members == null || members.isEmpty()) {
            return List.of();
        }

        List<PendingRegistration> registrations = new ArrayList<>();
        for (Object member : members) {
            String id = String.valueOf(member);
            Optional<PendingRegistration> registration = findById(UUID.fromString(id));
            if (registration.isPresent()) {
                registrations.add(registration.get());
            } else {
                redisTemplate.opsForSet().remove(emailKey, id);
            }
        }

        return registrations.stream()
                .sorted(Comparator.comparing(PendingRegistration::createdAt).reversed())
                .limit(limit)
                .toList();
    }

    /**
     * 登録と、メールアドレスごとの登録のIDの集合の有効期限を延ばす
     *
     * @param id 登録のID
     * @param ttl 有効期限
     */
    @Override
    public void extend(UUID id, Duration ttl) {
        Optional<PendingRegistration> registration = findById(id);
        if (registration.isEmpty()) {
            return;
        }
        redisTemplate.expire(PREFIX + id, ttl);
        redisTemplate.expire(EMAIL_PREFIX + registration.get().email(), ttl);
    }

    /**
     * 登録と、メールアドレスごとの登録のIDの集合の中のその登録のIDを消す
     *
     * @param registration 確認前の登録
     */
    @Override
    public void delete(PendingRegistration registration) {
        redisTemplate.delete(PREFIX + registration.id());
        redisTemplate.opsForSet().remove(EMAIL_PREFIX + registration.email(), registration.id().toString());
    }
}
