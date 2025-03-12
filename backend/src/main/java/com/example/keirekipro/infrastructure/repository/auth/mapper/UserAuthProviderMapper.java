package com.example.keirekipro.infrastructure.repository.auth.mapper;

import java.util.Optional;
import java.util.UUID;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 外部連携認証マッパー
 */
@Mapper
public interface UserAuthProviderMapper {

    /**
     * プロバイダー種別とプロバイダーユーザーIDを使用して、ユーザーIDを検索する
     * 既存ユーザーが見つかれば、新規登録せずにそのユーザーとしてログインさせ、見つからなければ、新規ユーザー登録する
     *
     * @param providerType   プロバイダー種別
     * @param providerUserId プロバイダー側のユーザーID
     * @return ユーザーID
     */
    Optional<UUID> findUserIdByProvider(@Param("providerType") String providerType,
            @Param("providerUserId") String providerUserId);

    /**
     * 新しい外部認証プロバイダー情報を登録する
     * 新しいユーザーを外部認証プロバイダーと関連付けるか、既存ユーザーに新しい外部認証プロバイダーを追加する
     *
     * @param id             認証プロバイダー情報のID
     * @param userId         ユーザーID
     * @param providerType   プロバイダー種別
     * @param providerUserId プロバイダー側のユーザーID
     */
    void registerAuthProvider(@Param("id") UUID id,
            @Param("userId") UUID userId,
            @Param("providerType") String providerType,
            @Param("providerUserId") String providerUserId);

    /**
     * ユーザーIDとプロバイダー種別に一致する認証プロバイダー情報の数をカウントする
     * 特定のユーザーが既に特定の外部認証プロバイダーと連携しているかを確認する
     *
     * @param userId       ユーザーID
     * @param providerType プロバイダー種別
     * @return 一致するレコードの数
     */
    int countByUserIdAndProviderType(@Param("userId") UUID userId,
            @Param("providerType") String providerType);

    /**
     * ユーザーIDとプロバイダー種別を使用して、プロバイダーユーザーIDを更新する
     * 既存の外部連携情報を更新する。プロバイダー側のユーザーIDが変更された場合に対応
     *
     * @param userId         ユーザーID
     * @param providerType   プロバイダー種別
     * @param providerUserId 新しいプロバイダー側のユーザーID
     * @return 更新された行数
     */
    int updateProviderUserId(@Param("userId") UUID userId,
            @Param("providerType") String providerType,
            @Param("providerUserId") String providerUserId);
}
