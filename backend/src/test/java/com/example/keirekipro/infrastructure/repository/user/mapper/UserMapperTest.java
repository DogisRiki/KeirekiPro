package com.example.keirekipro.infrastructure.repository.user.mapper;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mybatis.spring.boot.test.autoconfigure.MybatisTest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.jdbc.Sql;

@MybatisTest
@ActiveProfiles("test")
@TestPropertySource(properties = "spring.flyway.target=1")
class UserMapperTest {

    @Autowired
    private UserMapper userMapper;

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final String EMAIL = "test@example.com";

    private static final String PASSWORD = "hashedPassword";

    @Test
    @DisplayName("ユーザーが存在する場合、正しく取得できる")
    @Sql("/sql/user/UserMapperTest/test1.sql")
    void test1() {
        Optional<UserAuthInfoDto> user = userMapper.findByEmail(EMAIL);

        // ユーザー認証情報が存在する
        assertTrue(user.isPresent());
        // 各フィールドが正しい値である。
        assertEquals(USERID, user.get().getId());
        assertEquals(EMAIL, user.get().getEmail());
        assertEquals(PASSWORD, user.get().getPassword());
    }

    @Test
    @DisplayName("ユーザーが存在しない場合、空のOptionalが返る")
    void test2() {
        Optional<UserAuthInfoDto> user = userMapper.findByEmail(EMAIL);
        // ユーザーが存在しない。
        assertTrue(user.isEmpty());
    }
}
