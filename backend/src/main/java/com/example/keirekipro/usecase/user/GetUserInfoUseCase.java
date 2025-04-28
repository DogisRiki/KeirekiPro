package com.example.keirekipro.usecase.user;

import java.io.IOException;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

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
        byte[] img = null;
        if (user.getProfileImage() != null) {
            try {
                img = awsS3Client.getFileAsBytes(user.getProfileImage());
            } catch (IOException e) {
                // 画像取得失敗はエラーとせず、フロントエンド側でデフォルト画像を設定するため何もしない
            }
        }

        // 外部認証連携情報の変換
        List<AuthProviderInfo> providers = user.getAuthProviders().values().stream()
                .map(ap -> new AuthProviderInfo(
                        UUID.randomUUID(),
                        ap.getProviderName(),
                        ap.getProviderUserId()))
                .collect(Collectors.toList());

        return GetUserInfoUseCaseDto.builder()
                .id(user.getId())
                .email(user.getEmail() != null ? user.getEmail().getValue() : null)
                .username(user.getUsername())
                .profileImage(img)
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .authProviders(providers)
                .build();
    }
}
