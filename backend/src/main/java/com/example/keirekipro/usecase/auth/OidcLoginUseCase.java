package com.example.keirekipro.usecase.auth;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.auth.oidc.dto.OidcUserInfoDto;
import com.example.keirekipro.infrastructure.repository.auth.mapper.UserAuthProviderMapper;
import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.mapper.UserMapper;
import com.example.keirekipro.usecase.auth.dto.OidcLoginUseCaseDto;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * OIDCログインユースケース
 */
@Service
@RequiredArgsConstructor
public class OidcLoginUseCase {

    private final UserMapper userMapper;

    private final UserAuthProviderMapper userAuthProviderMapper;

    /**
     * OIDCログインのユースケースを実行する
     *
     * @param userInfo OIDCプロバイダーのuserinfoエンドポイントから取得したユーザー情報
     * @return ログイン結果
     */
    @Transactional
    public OidcLoginUseCaseDto execute(OidcUserInfoDto userInfo) {
        // OIDCプロバイダー情報からユーザーを検索
        Optional<UUID> existingUserId = userAuthProviderMapper.selectUserIdByProvider(userInfo.getProviderType(),
                userInfo.getProviderUserId());

        // 既存ユーザーが見つかった場合はそのまま取得できたユーザー情報を返す
        if (existingUserId.isPresent()) {
            return OidcLoginUseCaseDto.builder()
                    .id(existingUserId.get())
                    .username(userInfo.getUsername())
                    .email(userInfo.getEmail())
                    .providerType(userInfo.getProviderType())
                    .build();
        }

        // 既存ユーザーが見つからない場合は新規作成
        return createNewUser(userInfo);
    }

    /**
     * OIDCユーザー情報から新規ユーザーを作成する / 既存ユーザーにOIDC認証連係情報を追加する
     *
     * @param userInfo OIDCプロバイダーのuserinfoエンドポイントから取得したユーザー情報
     * @return ログイン結果
     */
    private OidcLoginUseCaseDto createNewUser(OidcUserInfoDto userInfo) {
        // 外部連携認証ID
        UUID authProviderId = UUID.randomUUID();

        // ユーザーID
        UUID userId;

        // メールアドレスからユーザーを取得する(ユーザー情報が空でない場合、メールアドレス+パスワード認証で既に登録されているケース)
        Optional<UserAuthInfoDto> existingUserByEmail = userMapper.selectByEmail(userInfo.getEmail());

        // ユーザー情報が存在する場合、既存のユーザー情報にOIDC認証連係情報を追加する
        if (existingUserByEmail.isPresent()) {
            // 既存ユーザーIDを使用
            userId = existingUserByEmail.get().getId();

            // 既存ユーザーにOIDC認証連係情報を登録する
            userAuthProviderMapper.insert(
                    authProviderId,
                    userId,
                    userInfo.getProviderType(),
                    userInfo.getProviderUserId());
        } else {
            // 新規ユーザーIDを採番
            userId = UUID.randomUUID();

            // ユーザー情報を登録する
            userMapper.insert(
                    userId,
                    userInfo.getEmail(),
                    null,
                    userInfo.getUsername());

            // OIDC認証連係情報を登録する
            userAuthProviderMapper.insert(
                    authProviderId,
                    userId,
                    userInfo.getProviderType(),
                    userInfo.getProviderUserId());
        }

        return OidcLoginUseCaseDto.builder()
                .id(userId)
                .username(userInfo.getUsername())
                .email(userInfo.getEmail())
                .providerType(userInfo.getProviderType())
                .build();
    }
}
