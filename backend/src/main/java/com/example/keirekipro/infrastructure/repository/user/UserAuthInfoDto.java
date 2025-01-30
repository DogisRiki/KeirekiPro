package com.example.keirekipro.infrastructure.repository.user;

import java.util.UUID;

import lombok.Data;

/**
 * ユーザー認証情報DTO
 */
@Data
public class UserAuthInfoDto {

    private UUID id;
    private String email;
    private String password;
}
