package com.example.keirekipro.presentation.shared;

import com.auth0.jwt.exceptions.JWTVerificationException;

import io.swagger.v3.oas.annotations.Hidden;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * テスト用コントローラー
 */
@RestController
@RequestMapping("/auth")
@Hidden
class TestController {
    @GetMapping("/test")
    public void throwJwtException() {
        throw new JWTVerificationException("Invalid token");
    }
}
