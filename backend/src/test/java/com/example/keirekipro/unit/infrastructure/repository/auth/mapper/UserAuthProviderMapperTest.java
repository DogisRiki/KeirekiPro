package com.example.keirekipro.unit.infrastructure.repository.auth.mapper;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.auth.mapper.UserAuthProviderMapper;

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
class UserAuthProviderMapperTest {

    private final UserAuthProviderMapper userAuthProviderMapper;

    private static final UUID USERID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    private static final String PROVIDER_TYPE = "GOOGLE";

    private static final String PROVIDER_USERID = "google-uid-12345";

    @Test
    @DisplayName("既存の認証プロバイダー情報からユーザーIDを取得できる")
    @Sql("/sql/auth/UserAuthProviderMapperTest/test1.sql")
    void test1() {
        Optional<UUID> userIdOpt = userAuthProviderMapper.findUserIdByProvider(PROVIDER_TYPE, PROVIDER_USERID);
        assertThat(userIdOpt).isPresent();
        assertThat(userIdOpt.get()).isEqualTo(USERID);
    }

    @Test
    @DisplayName("存在しない認証プロバイダー情報の場合、空のOptionalを返す")
    void test2() {
        Optional<UUID> userIdOpt = userAuthProviderMapper.findUserIdByProvider(PROVIDER_TYPE, "non-existent");
        assertThat(userIdOpt).isNotPresent();
    }

    @Test
    @DisplayName("新しい外部認証プロバイダー情報を登録できる")
    @Sql("/sql/auth/UserAuthProviderMapperTest/test3~5.sql")
    void test3() {
        UUID newId = UUID.randomUUID();
        String newProviderUserId = "new-google-uid";
        userAuthProviderMapper.registerAuthProvider(newId, USERID, PROVIDER_TYPE, newProviderUserId);

        Optional<UUID> userIdOpt = userAuthProviderMapper.findUserIdByProvider(PROVIDER_TYPE, newProviderUserId);
        assertThat(userIdOpt).isPresent();
        assertThat(userIdOpt.get()).isEqualTo(USERID);
    }

    @Test
    @DisplayName("ユーザーIDとプロバイダー種別で認証プロバイダー情報の数を正しくカウントする")
    @Sql("/sql/auth/UserAuthProviderMapperTest/test3~5.sql")
    void test4() {
        // 同一ユーザー・異なるプロバイダー種別で2件登録
        UUID id1 = UUID.randomUUID();
        UUID id2 = UUID.randomUUID();
        userAuthProviderMapper.registerAuthProvider(id1, USERID, PROVIDER_TYPE, "uid1");
        userAuthProviderMapper.registerAuthProvider(id2, USERID, "GITHUB", "uid2");

        int googleCount = userAuthProviderMapper.countByUserIdAndProviderType(USERID, PROVIDER_TYPE);
        int githubCount = userAuthProviderMapper.countByUserIdAndProviderType(USERID, "GITHUB");
        assertThat(googleCount).isEqualTo(1);
        assertThat(githubCount).isEqualTo(1);
    }

    @Test
    @DisplayName("ユーザーIDとプロバイダー種別で、プロバイダーユーザーIDを更新できる")
    @Sql("/sql/auth/UserAuthProviderMapperTest/test3~5.sql")
    void test5() {
        // 新規登録
        UUID newId = UUID.randomUUID();
        String originalProviderUserId = "old-uid";
        userAuthProviderMapper.registerAuthProvider(newId, USERID, PROVIDER_TYPE, originalProviderUserId);

        // プロバイダーユーザーIDの更新
        String updatedProviderUserId = "updated-uid";
        int updatedRows = userAuthProviderMapper.updateProviderUserId(USERID, PROVIDER_TYPE, updatedProviderUserId);
        assertThat(updatedRows).isEqualTo(1);

        // 旧IDでは取得できず、新IDで取得できることを確認
        Optional<UUID> oldLookup = userAuthProviderMapper.findUserIdByProvider(PROVIDER_TYPE, originalProviderUserId);
        Optional<UUID> newLookup = userAuthProviderMapper.findUserIdByProvider(PROVIDER_TYPE, updatedProviderUserId);
        assertThat(oldLookup).isNotPresent();
        assertThat(newLookup).isPresent();
        assertThat(newLookup.get()).isEqualTo(USERID);
    }
}
