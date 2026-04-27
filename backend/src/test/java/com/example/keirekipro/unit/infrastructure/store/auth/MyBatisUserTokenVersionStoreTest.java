package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.store.auth.MyBatisUserTokenVersionStore;
import com.example.keirekipro.infrastructure.store.auth.UserTokenVersionMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisUserTokenVersionStoreTest {

    @Mock
    private UserTokenVersionMapper userTokenVersionMapper;

    @InjectMocks
    private MyBatisUserTokenVersionStore store;

    private static final UUID USER_ID = UUID.randomUUID();

    @Test
    @DisplayName("getでレコードが存在する場合、保存されているトークンバージョンが返る")
    void test1() {
        when(userTokenVersionMapper.selectByUserId(USER_ID)).thenReturn(Optional.of(3L));

        long result = store.get(USER_ID);

        assertThat(result).isEqualTo(3L);
        verify(userTokenVersionMapper).selectByUserId(USER_ID);
    }

    @Test
    @DisplayName("getでレコードが存在しない場合、0が返る")
    void test2() {
        when(userTokenVersionMapper.selectByUserId(USER_ID)).thenReturn(Optional.empty());

        long result = store.get(USER_ID);

        assertThat(result).isZero();
        verify(userTokenVersionMapper).selectByUserId(USER_ID);
    }

    @Test
    @DisplayName("incrementでMapperのincrementByUserIdが呼ばれる")
    void test3() {
        store.increment(USER_ID);

        verify(userTokenVersionMapper).incrementByUserId(eq(USER_ID), any(LocalDateTime.class));
    }

    @Test
    @DisplayName("initializeでMapperのinsertが呼ばれる")
    void test4() {
        store.initialize(USER_ID);

        verify(userTokenVersionMapper).insert(eq(USER_ID), any(LocalDateTime.class));
    }
}
