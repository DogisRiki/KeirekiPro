package com.example.keirekipro.usecase.user;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.model.user.User;
import com.example.keirekipro.domain.repository.user.UserRepository;
import com.example.keirekipro.infrastructure.shared.aws.AwsS3Client;
import com.example.keirekipro.usecase.user.dto.GetUserInfoUseCaseDto;
import com.example.keirekipro.usecase.user.dto.GetUserInfoUseCaseDto.AuthProviderInfo;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetUserInfoUseCase {

    private final UserRepository userRepository;

    private final AwsS3Client awsS3Client;

    /**
     * ユーザー情報取得ユースケースを実行する
     *
     * @param userId ユーザーID
     * @return ユーザー情報DTO
     */
    public GetUserInfoUseCaseDto execute(UUID userId) {

        // ユーザー情報取得
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        // S3からプロフィール画像をバイト配列として取得する
        String imageUrl = null;
        if (user.getProfileImage() != null) {
            imageUrl = awsS3Client.generatePresignedUrl(user.getProfileImage(), Duration.ofMinutes(10));
        }

        // 外部認証連携情報の変換
        List<AuthProviderInfo> providers = user.getAuthProviders().values().stream()
                .map(ap -> new AuthProviderInfo(
                        ap.getId(),
                        ap.getProviderName(),
                        ap.getProviderUserId()))
                .toList();

        return GetUserInfoUseCaseDto.builder()
                .id(user.getId())
                .email(user.getEmail() != null ? user.getEmail().getValue() : null)
                .username(user.getUsername())
                .profileImage(imageUrl)
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .authProviders(providers)
                .build();
    }
}
