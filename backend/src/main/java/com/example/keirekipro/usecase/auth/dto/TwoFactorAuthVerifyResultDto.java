package com.example.keirekipro.usecase.auth.dto;

import java.util.Set;
import java.util.UUID;

import lombok.Builder;
import lombok.Getter;

/**
 * 二段階認証検証結果DTO
 */
@Getter
@Builder
public class TwoFactorAuthVerifyResultDto {

    private UUID userId;
    private Set<String> roles;
}
