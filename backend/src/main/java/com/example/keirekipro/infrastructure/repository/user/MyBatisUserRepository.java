package com.example.keirekipro.infrastructure.repository.user;

import java.util.EnumSet;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.user.AuthProvider;
import com.example.keirekipro.domain.model.user.Email;
import com.example.keirekipro.domain.model.user.RoleName;
import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.shared.ErrorCollector;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * ユーザーリポジトリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisUserRepository implements UserRepository {

    private final UserMapper mapper;

    @Override
    public Optional<User> findById(UUID userId) {
        return mapper.selectById(userId).map(this::toEntity);
    }

    @Override
    public Optional<User> findByEmail(String email) {
        return mapper.selectByEmail(email).map(this::toEntity);
    }

    @Override
    public Optional<User> findByProvider(String providerName, String providerUserId) {
        return mapper.selectByProvider(providerName, providerUserId).map(this::toEntity);
    }

    @Override
    public void save(User user) {
        UserDto dto = toDto(user);

        // ユーザー情報のupsert
        mapper.upsertUser(dto);

        // 外部認証連携情報を全件削除してから再挿入
        mapper.deleteAuthProvidersByUserId(dto.getId());
        for (UserDto.AuthProviderDto apDto : dto.getAuthProviders()) {
            mapper.insertAuthProvider(apDto);
        }

        // ロールを全件削除してから再挿入
        mapper.deleteUserRolesByUserId(dto.getId());
        for (String roleName : dto.getRoles()) {
            mapper.insertUserRole(dto.getId(), roleName);
        }
    }

    @Override
    public void delete(UUID userId) {
        mapper.delete(userId);
    }

    /**
     * DTOからエンティティへ変換する
     */
    private User toEntity(UserDto dto) {
        Map<String, AuthProvider> providers = dto.getAuthProviders().stream()
                .map(ap -> AuthProvider.reconstruct(
                        ap.getId(),
                        ap.getProviderName(),
                        ap.getProviderUserId(),
                        ap.getCreatedAt(),
                        ap.getUpdatedAt()))
                .collect(Collectors.toMap(
                        p -> p.getProviderName().toLowerCase(),
                        p -> p,
                        (p1, p2) -> p2,
                        HashMap::new));

        // ロールの復元
        Set<RoleName> roles = EnumSet.noneOf(RoleName.class);
        if (dto.getRoles() != null) {
            for (String roleName : dto.getRoles()) {
                if (roleName != null) {
                    try {
                        roles.add(RoleName.valueOf(roleName));
                    } catch (IllegalArgumentException e) {
                        // 不明なロール名は無視
                    }
                }
            }
        }

        return User.reconstruct(
                dto.getId(),
                dto.getEmail() != null ? Email.create(new ErrorCollector(), dto.getEmail()) : null,
                dto.getPassword(),
                dto.isTwoFactorAuthEnabled(),
                providers,
                roles,
                dto.getProfileImage(),
                dto.getUsername(),
                dto.getCreatedAt(),
                dto.getUpdatedAt());
    }

    /**
     * エンティティからDTOへ変換する
     */
    private UserDto toDto(User user) {
        UserDto dto = new UserDto();
        dto.setId(user.getId());
        dto.setEmail(user.getEmail() != null ? user.getEmail().getValue() : null);
        dto.setPassword(user.getPasswordHash());
        dto.setUsername(user.getUsername());
        dto.setProfileImage(user.getProfileImage());
        dto.setTwoFactorAuthEnabled(user.isTwoFactorAuthEnabled());
        dto.setCreatedAt(user.getCreatedAt());
        dto.setUpdatedAt(user.getUpdatedAt());

        dto.setAuthProviders(
                user.getAuthProviders().values().stream()
                        .map(p -> {
                            UserDto.AuthProviderDto ap = new UserDto.AuthProviderDto();
                            ap.setId(p.getId());
                            ap.setUserId(user.getId());
                            ap.setProviderName(p.getProviderName());
                            ap.setProviderUserId(p.getProviderUserId());
                            ap.setCreatedAt(p.getCreatedAt());
                            ap.setUpdatedAt(p.getUpdatedAt());
                            return ap;
                        })
                        .toList());

        // ロール名のリストを設定
        dto.setRoles(user.getRoleNames().stream().toList());

        return dto;
    }
}
