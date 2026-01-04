package com.example.keirekipro.infrastructure.repository.user;

import java.util.Optional;
import java.util.UUID;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * ユーザーマッパー
 */
@Mapper
public interface UserMapper {

    /**
     * ユーザーIDからユーザーを取得する
     *
     * @param userId ユーザーID
     * @return ユーザーDTO
     */
    Optional<UserDto> selectById(@Param("id") UUID userId);

    /**
     * メールアドレスからユーザーを取得する
     *
     * @param email メールアドレス
     * @return ユーザーDTO
     */
    Optional<UserDto> selectByEmail(@Param("email") String email);

    /**
     * プロバイダー情報でユーザーを取得する
     *
     * @param providerName   プロバイダー名
     * @param providerUserId プロバイダー側ユーザーID
     * @return ユーザーDTO
     */
    Optional<UserDto> selectByProvider(@Param("providerName") String providerName,
            @Param("providerUserId") String providerUserId);

    /**
     * ユーザー情報を作成/更新する
     *
     * @param dto ユーザーDTO
     */
    void upsertUser(UserDto dto);

    /**
     * ユーザーを削除する
     *
     * @param userId ユーザーID
     */
    void delete(@Param("id") UUID userId);

    /**
     * 外部連携認証情報を登録する
     *
     * @param dto 外部連携認証情報DTO
     */
    void insertAuthProvider(UserDto.AuthProviderDto dto);

    /**
     * 外部連携認証情報を全件削除する
     *
     * @param userId ユーザーID
     */
    void deleteAuthProvidersByUserId(@Param("userId") UUID userId);

    /**
     * ユーザーロールを登録する
     *
     * @param userId   ユーザーID
     * @param roleName ロール名
     */
    void insertUserRole(@Param("userId") UUID userId, @Param("roleName") String roleName);

    /**
     * ユーザーロールを全件削除する
     *
     * @param userId ユーザーID
     */
    void deleteUserRolesByUserId(@Param("userId") UUID userId);
}
