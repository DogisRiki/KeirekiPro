package com.example.keirekipro.unit.infrastructure.store.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.config.PostgresTestContainerConfig;
import com.example.keirekipro.infrastructure.repository.user.UserDto;
import com.example.keirekipro.infrastructure.repository.user.UserMapper;
import com.example.keirekipro.infrastructure.store.auth.UserTokenVersionMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestConstructor;

import lombok.RequiredArgsConstructor;

@MybatisTest
@ActiveProfiles("test")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(PostgresTestContainerConfig.class)
class UserTokenVersionMapperTest {

    private final UserTokenVersionMapper userTokenVersionMapper;
    private final UserMapper userMapper;

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID NON_EXISTENT_USER_ID = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
    private static final LocalDateTime CREATED = LocalDateTime.of(2025, 1, 1, 0, 0);
    private static final LocalDateTime UPDATED = LocalDateTime.of(2025, 1, 2, 0, 0);

    @Test
    @DisplayName("selectByUserId_レコードが存在しない場合、空のOptionalが返る")
    void test1() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        // 検証
        Optional<Long> result = userTokenVersionMapper.selectByUserId(USER_ID);
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("insert_トークンバージョンを新規作成すると、初期値0で保存される")
    void test2() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());

        // 実行
        userTokenVersionMapper.insert(USER_ID, UPDATED);

        // 検証
        Optional<Long> result = userTokenVersionMapper.selectByUserId(USER_ID);
        assertThat(result).isPresent();
        assertThat(result.get()).isZero();
    }

    @Test
    @DisplayName("incrementByUserId_トークンバージョンが1ずつインクリメントされる")
    void test3() {
        // ユーザー作成
        userMapper.upsertUser(createUserDto());
        // 初期化
        userTokenVersionMapper.insert(USER_ID, UPDATED);

        // 1回目
        userTokenVersionMapper.incrementByUserId(USER_ID, UPDATED);
        assertThat(userTokenVersionMapper.selectByUserId(USER_ID)).contains(1L);

        // 2回目
        userTokenVersionMapper.incrementByUserId(USER_ID, UPDATED);
        assertThat(userTokenVersionMapper.selectByUserId(USER_ID)).contains(2L);

        // 3回目
        userTokenVersionMapper.incrementByUserId(USER_ID, UPDATED);
        assertThat(userTokenVersionMapper.selectByUserId(USER_ID)).contains(3L);
    }

    @Test
    @DisplayName("incrementByUserId_存在しないユーザーIDを指定した場合、何も起きない")
    void test4() {
        // 実行
        userTokenVersionMapper.incrementByUserId(NON_EXISTENT_USER_ID, UPDATED);

        // 検証
        Optional<Long> result = userTokenVersionMapper.selectByUserId(NON_EXISTENT_USER_ID);
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("ユーザー削除時にトークンバージョンレコードもON DELETE CASCADEで削除される")
    void test5() {
        // ユーザー作成 + トークンバージョン初期化
        userMapper.upsertUser(createUserDto());
        userTokenVersionMapper.insert(USER_ID, UPDATED);
        assertThat(userTokenVersionMapper.selectByUserId(USER_ID)).isPresent();

        // ユーザー削除
        userMapper.delete(USER_ID);

        // 検証
        Optional<Long> result = userTokenVersionMapper.selectByUserId(USER_ID);
        assertThat(result).isEmpty();
    }

    /**
     * UserDtoを作成するヘルパーメソッド
     */
    private UserDto createUserDto() {
        UserDto dto = new UserDto();
        dto.setId(USER_ID);
        dto.setEmail("test@keirekipro.click");
        dto.setPassword("passwordHash");
        dto.setUsername("user");
        dto.setProfileImage("profile/test-user.jpg");
        dto.setTwoFactorAuthEnabled(true);
        dto.setCreatedAt(CREATED);
        dto.setUpdatedAt(UPDATED);
        dto.setAuthProviders(Collections.emptyList());
        return dto;
    }
}
