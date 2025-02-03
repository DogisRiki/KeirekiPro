package com.example.keirekipro.usecase.auth.dto;

import java.util.UUID;

import lombok.Value;

/**
 * ログインユースケースDTO
 */
@Value
public class LoginUseCaseDto {

    private final UUID id;
}
