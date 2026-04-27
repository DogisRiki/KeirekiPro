package com.example.keirekipro.infrastructure.store.auth;

import java.time.LocalDateTime;
import java.util.UUID;

import com.example.keirekipro.usecase.auth.store.UserTokenVersionStore;

import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * ユーザートークンバージョンストア実装
 */
@Component
@RequiredArgsConstructor
public class MyBatisUserTokenVersionStore implements UserTokenVersionStore {

    private final UserTokenVersionMapper userTokenVersionMapper;

    @Override
    public long get(UUID userId) {
        return userTokenVersionMapper.selectByUserId(userId).orElse(0L);
    }

    @Override
    public void increment(UUID userId) {
        userTokenVersionMapper.incrementByUserId(userId, LocalDateTime.now());
    }

    @Override
    public void initialize(UUID userId) {
        userTokenVersionMapper.insert(userId, LocalDateTime.now());
    }
}
