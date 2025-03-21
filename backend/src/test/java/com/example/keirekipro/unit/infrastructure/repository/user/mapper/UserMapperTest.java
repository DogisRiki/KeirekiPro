package com.example.keirekipro.unit.infrastructure.repository.user.mapper;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestConstructor;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.jdbc.Sql;

import lombok.RequiredArgsConstructor;

@MybatisTest
@ActiveProfiles("test")
@TestPropertySource(properties = "spring.flyway.target=1")
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
@RequiredArgsConstructor
class UserMapperTest {

    private final UserMapper userMapper;

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final String EMAIL = "test@example.com";

    private static final String PASSWORD = "hashedPassword";

    @Test
    @DisplayName("ユーザーが存在する場合、正しく取得できる")
    @Sql("/sql/user/UserMapperTest/test1.sql")
    void test1() {
        Optional<UserAuthInfoDto> user = userMapper.findByEmail(EMAIL);

        // ユーザー認証情報が存在する
        assertThat(user).isPresent();
        // 各フィールドが正しい
        assertThat(user.get().getId()).isEqualTo(USERID);
        assertThat(user.get().getEmail()).isEqualTo(EMAIL);
        assertThat(user.get().getPassword()).isEqualTo(PASSWORD);
        assertThat(user.get().isTwoFactorAuthEnabled()).isEqualTo(false);
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、空のOptionalが返る")
    void test2() {
        Optional<UserAuthInfoDto> user = userMapper.findByEmail(EMAIL);
        // ユーザーが存在しない
        assertThat(user).isNotPresent();
    }

    @Test
    @DisplayName("ユーザーを新規登録する")
    void test3() {
        userMapper.registerUser(USERID, EMAIL, PASSWORD, EMAIL);
        Optional<UserAuthInfoDto> user = userMapper.findByEmail(EMAIL);

        // 登録したユーザーが存在する
        assertThat(user).isPresent();
        // 各フィールドが正しい
        assertThat(user.get().getId()).isEqualTo(USERID);
        assertThat(user.get().getEmail()).isEqualTo(EMAIL);
        assertThat(user.get().getPassword()).isEqualTo(PASSWORD);
        assertThat(user.get().isTwoFactorAuthEnabled()).isEqualTo(false);
    }
}
