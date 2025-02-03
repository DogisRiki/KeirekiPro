package com.example.keirekipro.presentation.shared;

import com.auth0.jwt.exceptions.JWTVerificationException;

import io.swagger.v3.oas.annotations.Hidden;

import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import lombok.Data;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * テスト用コントローラー
 */
@RestController
@RequestMapping("/test")
@Hidden
class TestController {
    @GetMapping("/test1")
    public void throwJwtException() {
        throw new JWTVerificationException("Invalid token");
    }

    @GetMapping("/test2")
    public void throwBadCredentialsException() {
        throw new BadCredentialsException("メールアドレスまたはパスワードが違います。");
    }

    @PostMapping("/test3")
    public void validateSingle(@Valid @RequestBody NotNullDto input) {
    }

    @PostMapping("/test4")
    public void validateMix(@Valid @RequestBody RegexDto input) {
    }

    @Data
    public static class NotNullDto {
        @NotNull(message = "値1は入力必須です。")
        private String value1;

        @NotNull(message = "値2は入力必須です。")
        private String value2;
    }

    @Data
    public static class RegexDto {
        @Pattern(regexp = "^[0-9]+$", message = "値1は数字でなければなりません")
        @Size(min = 1, max = 4, message = "値1は1～4桁を入力してください")
        private String value1;

        @Pattern(regexp = "^[0-9]+$", message = "値2は数字でなければなりません")
        @Size(min = 1, max = 4, message = "値2は1～4桁を入力してください")
        private String value2;
    }
}
