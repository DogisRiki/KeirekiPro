package com.example.keirekipro.unit.infrastructure.repository.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.infrastructure.repository.user.MyBatisUserRepository;
import com.example.keirekipro.infrastructure.repository.user.UserDto;
import com.example.keirekipro.infrastructure.repository.user.UserMapper;
import com.example.keirekipro.shared.Notification;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisUserRepositoryTest {

    @Mock
    private UserMapper mapper;

    private static final UUID ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");
    private static final String EMAIL = "test@keirekipro.click";
    private static final String PASSWORD = "hashedPassword";
    private static final String USERNAME = "test-user";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2023, 5, 1, 0, 0);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2023, 5, 2, 0, 0);

    @Test
    @DisplayName("findById()を実行するとDTOがエンティティに変換されて返却される")
    void test1() {
        UserDto dto = buildDto();
        when(mapper.selectById(ID)).thenReturn(Optional.of(dto));

        MyBatisUserRepository repo = new MyBatisUserRepository(mapper);

        Optional<User> opt = repo.findById(ID);

        assertThat(opt).isPresent();
        User user = opt.get();

        // 基本フィールド
        assertThat(user.getId()).isEqualTo(ID);
        assertThat(user.getEmail()).isEqualTo(Email.create(new Notification(), EMAIL));
        assertThat(user.getPasswordHash()).isEqualTo(PASSWORD);
        assertThat(user.getUsername()).isEqualTo(USERNAME);

        // 外部認証連携
        Map<String, AuthProvider> providers = user.getAuthProviders();
        assertThat(providers).containsOnlyKeys("google");
        assertThat(providers.get("google"))
                .isEqualTo(AuthProvider.create(new Notification(), "google", "gid-1"));
    }

    @Test
    @DisplayName("save()を実行するとUserエンティティがDTOに変換されてupsertが実行される")
    void test2() {
        MyBatisUserRepository repo = new MyBatisUserRepository(mapper);

        User entity = User.reconstruct(
                ID,
                1,
                Email.create(new Notification(), EMAIL),
                PASSWORD,
                false,
                Collections.singletonMap("google", AuthProvider.create(new Notification(), "google", "gid-1")),
                null,
                USERNAME,
                CREATED_AT,
                UPDATED_AT);

        ArgumentCaptor<UserDto> captor = ArgumentCaptor.forClass(UserDto.class);

        repo.save(entity);

        verify(mapper).upsert(captor.capture());
        UserDto dto = captor.getValue();

        // DTOの内容を検証
        assertThat(dto.getId()).isEqualTo(ID);
        assertThat(dto.getEmail()).isEqualTo(EMAIL);
        assertThat(dto.getPassword()).isEqualTo(PASSWORD);
        assertThat(dto.getUsername()).isEqualTo(USERNAME);
        assertThat(dto.getAuthProviders())
                .hasSize(1)
                .extracting(UserDto.AuthProviderDto::getProviderName)
                .containsExactly("google");
    }

    @Test
    @DisplayName("findByEmail()を実行するとDTOがエンティティに変換されて返却される")
    void test3() {
        UserDto dto = buildDto();
        when(mapper.selectByEmail(EMAIL)).thenReturn(Optional.of(dto));

        MyBatisUserRepository repo = new MyBatisUserRepository(mapper);

        Optional<User> opt = repo.findByEmail(EMAIL);

        assertThat(opt).isPresent();
        assertThat(opt.get().getId()).isEqualTo(ID);
    }

    /**
     * テスト用DTOビルダー
     */
    private static UserDto buildDto() {
        UserDto.AuthProviderDto ap = new UserDto.AuthProviderDto();
        ap.setId(UUID.randomUUID());
        ap.setProviderName("google");
        ap.setProviderUserId("gid-1");
        ap.setCreatedAt(CREATED_AT);
        ap.setUpdatedAt(UPDATED_AT);

        UserDto dto = new UserDto();
        dto.setId(ID);
        dto.setEmail(EMAIL);
        dto.setPassword(PASSWORD);
        dto.setUsername(USERNAME);
        dto.setProfileImage(null);
        dto.setTwoFactorAuthEnabled(false);
        dto.setCreatedAt(CREATED_AT);
        dto.setUpdatedAt(UPDATED_AT);
        dto.setAuthProviders(List.of(ap));
        return dto;
    }
}
