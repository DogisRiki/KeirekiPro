package com.example.keirekipro.infrastructure.repository.user.mapper;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;
import com.example.keirekipro.infrastructure.repository.user.dto.UserInfo;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.springframework.stereotype.Repository;

/**
 * ユーザーマッパー
 */
@Mapper
@Repository
public interface UserMapper {

    /**
     * メールアドレスからユーザー認証情報を取得する
     *
     * @param email メールアドレス
     * @return ユーザー認証情報
     */
    Optional<UserAuthInfoDto> selectByEmail(@Param("email") String email);

    /**
     * 新規ユーザーを登録する
     *
     * @param id       ユーザーID
     * @param email    メールアドレス
     * @param password パスワード
     * @param username ユーザー名
     */
    void insert(@Param("id") UUID id, @Param("email") String email, @Param("password") String password,
            @Param("username") String username);

    /**
     * ユーザーIDからパスワードを取得する
     *
     * @param id ユーザーID
     * @return パスワード
     */
    Optional<String> selectPasswordById(@Param("id") UUID id);

    /**
     * パスワードを変更する
     *
     * @param id       ユーザーID
     * @param password パスワード
     */
    void updatePassword(@Param("id") UUID id, @Param("password") String password);

    /**
     * ユーザーIDからユーザー情報を取得する
     *
     * @param id ユーザーID
     * @return ユーザー情報
     */
    Optional<UserInfo> selectById(@Param("id") UUID id);

    /**
     * ユーザー情報を更新する
     *
     * @param id                   ユーザーID
     * @param username             ユーザー名
     * @param profileImage         プロフィール画像
     * @param twoFactorAuthEnabled 二段階認証設定
     * @return 更新後のユーザー情報
     */
    Optional<UserInfo> update(@Param("id") UUID id, @Param("username") String username,
            @Param("profileImage") String profileImage, @Param("twoFactorAuthEnabled") boolean twoFactorAuthEnabled);
}
