package com.example.keirekipro.usecase.user;

import java.io.IOException;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import com.example.keirekipro.infrastructure.repository.user.dto.UserInfo;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
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

    private final UserMapper userMapper;

    private final AwsS3Client awsS3Client;

    /**
     * ユーザー情報取得ユースケースを実行する
     *
     * @param userId ユーザーID
     * @return ユーザー情報DTO
     */
    public GetUserInfoUseCaseDto execute(UUID userId) {
        // ユーザー情報取得
        UserInfo user = userMapper.selectById(userId)
                .orElseThrow(() -> new AccessDeniedException("不正なアクセスです。"));

        // S3からプロフィール画像をバイト配列として取得する
        byte[] profileImageData = null;
        if (user.getProfileImage() != null && !user.getProfileImage().isEmpty()) {
            try {
                profileImageData = awsS3Client.getFileAsBytes(user.getProfileImage());
            } catch (IOException e) {
                // 画像取得失敗はエラーとせず、フロントエンド側でデフォルト画像を設定するため何もしない
                // TODO: ログ出力する？
            }
        }

        // 外部認証連携情報の変換
        List<AuthProviderInfo> authProviders = null;
        if (user.getAuthProviders() != null) {
            authProviders = user.getAuthProviders().stream()
                    .map(provider -> new AuthProviderInfo(
                            provider.getId(),
                            provider.getProviderType(),
                            provider.getProviderUserId()))
                    .collect(Collectors.toList());
        }

        return GetUserInfoUseCaseDto.builder()
                .id(user.getId())
                .email(user.getEmail())
                .username(user.getUsername())
                .profileImage(profileImageData)
                .twoFactorAuthEnabled(user.isTwoFactorAuthEnabled())
                .authProviders(authProviders)
                .build();
    }
}
