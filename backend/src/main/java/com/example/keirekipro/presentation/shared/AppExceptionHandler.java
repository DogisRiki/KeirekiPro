package com.example.keirekipro.presentation.shared;

import com.auth0.jwt.exceptions.JWTVerificationException;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * アプリケーション全体の例外を処理するハンドラー
 */
@RestControllerAdvice
public class AppExceptionHandler {

    /**
     * JWT認証エラーをハンドリングする
     *
     * @return エラーレスポンス
     */
    @ExceptionHandler(JWTVerificationException.class)
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public ErrorResponse handleJwtVerificationException() {
        return new ErrorResponse("認証に失敗しました。", null);
    }
}
