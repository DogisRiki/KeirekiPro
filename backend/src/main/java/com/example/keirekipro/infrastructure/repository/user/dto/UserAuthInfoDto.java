package com.example.keirekipro.infrastructure.repository.user.dto;

import java.util.UUID;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * ユーザー認証情報DTO
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserAuthInfoDto {

    private UUID id;
    private String email;
    private String password;
    private boolean twoFactorAuthEnabled;
}
