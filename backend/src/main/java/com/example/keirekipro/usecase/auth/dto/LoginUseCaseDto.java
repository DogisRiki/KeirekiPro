package com.example.keirekipro.usecase.auth.dto;

import java.util.Set;
import java.util.UUID;

import lombok.Builder;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * ログインユースケースDTO
 */
@RequiredArgsConstructor
@Getter
@Builder
public class LoginUseCaseDto {

    private final UUID id;
    private final String email;
    private final boolean twoFactorAuthEnabled;
    private final Set<String> roles;
}
