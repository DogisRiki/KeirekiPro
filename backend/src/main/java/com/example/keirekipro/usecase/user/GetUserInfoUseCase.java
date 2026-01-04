package com.example.keirekipro.usecase.user;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.usecase.shared.store.ObjectStore;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto;
import com.example.keirekipro.usecase.user.dto.UserInfoUseCaseDto.AuthProviderInfo;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetUserInfoUseCase {

    private final UserRepository userRepository;

    private final ObjectStore objectStore;

    /**
     * ユーザー情報取得ユースケースを実行する
     *
     * @param userId ユーザーID
     * @return ユーザー情報DTO
     */
    public UserInfoUseCaseDto execute(UUID userId) {

        // ユーザー情報取得
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthenticationCredentialsNotFoundException("不正なアクセスです。"));

        // オブジェクトストアからプロフィール画像URLを取得する
        String imageUrl = null;
        if (user.getProfileImage() != null) {
            imageUrl = objectStore.issueGetUrl(user.getProfileImage(), Duration.ofMinutes(10));
        }

        // 外部認証連携情報の変換
        List<AuthProviderInfo> providers = user.getAuthProviders().values().stream()
                .map(ap -> new AuthProviderInfo(
                        ap.getId(),
                        ap.getProviderName(),
                        ap.getProviderUserId()))
                .toList();

        return UserInfoUseCaseDto.builder()
                .id(user.getId())
                .email(user.getEmail() != null ? user.getEmail().getValue() : null)
                .username(user.getUsername())
                .hasPassword(user.getPasswordHash() != null)
                .profileImage(imageUrl)
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .authProviders(providers)
                .roles(user.getRoleNames())
                .build();
    }
}
