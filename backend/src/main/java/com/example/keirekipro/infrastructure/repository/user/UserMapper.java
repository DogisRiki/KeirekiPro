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
     * ユーザーを作成/更新する
     *
     * @param user ユーザーDTO
     */
    void upsert(UserDto user);

    /**
     * ユーザーを削除する
     *
     * @param userId ユーザーID
     */
    void delete(@Param("id") UUID userId);
}
