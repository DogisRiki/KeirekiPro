package com.example.keirekipro.usecase.user.dto;

import java.util.UUID;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * ユーザー情報更新ユースケースDTO
 */
@RequiredArgsConstructor
@Getter
@Builder
public class UpdateUserInfoUseCaseDto {

    private final UUID id;
    private final String username;
    private final String profileImage;
    private final boolean twoFactorAuthEnabled;
}
