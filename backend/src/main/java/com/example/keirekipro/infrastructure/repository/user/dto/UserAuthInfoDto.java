package com.example.keirekipro.infrastructure.repository.user.dto;

import java.util.UUID;

import lombok.Value;

/**
 * ユーザー認証情報DTO
 */
@Value
public class UserAuthInfoDto {

    private UUID id;
    private String email;
    private String password;
}
