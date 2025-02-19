package com.example.keirekipro.infrastructure.repository.user.mapper;

import java.util.Optional;

import com.example.keirekipro.infrastructure.repository.user.dto.UserAuthInfoDto;

import org.apache.ibatis.annotations.Mapper;
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
    Optional<UserAuthInfoDto> findByEmail(String email);
}
