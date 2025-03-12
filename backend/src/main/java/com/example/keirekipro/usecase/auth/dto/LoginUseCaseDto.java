package com.example.keirekipro.usecase.auth.dto;

import java.util.UUID;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * ログインユースケースDTO
 */
@RequiredArgsConstructor
@Getter
public class LoginUseCaseDto {

    private final UUID id;
}
