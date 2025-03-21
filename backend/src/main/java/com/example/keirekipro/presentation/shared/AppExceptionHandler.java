package com.example.keirekipro.presentation.shared;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.usecase.shared.UseCaseException;

import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * アプリケーション全体の例外を処理するハンドラー
 */
@RestControllerAdvice
public class AppExceptionHandler {

    /**
     * JWTVerificationExceptionをハンドリングする
     *
     * @return エラーレスポンス
     */
    @ExceptionHandler(JWTVerificationException.class)
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public ErrorResponse handleJwtVerificationException() {
        return new ErrorResponse("認証に失敗しました。", null);
    }

    /**
     * BadCredentialsExceptionをハンドリングする
     *
     * @param ex 例外オブジェクト
     * @return エラーレスポンス
     */
    @ExceptionHandler(BadCredentialsException.class)
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public ErrorResponse handleBadCredentialsException(BadCredentialsException ex) {
        return new ErrorResponse(ex.getMessage(), null);
    }

    /**
     * MethodArgumentNotValidExceptionをハンドリングする
     *
     * @param ex 例外オブジェクト
     * @return エラーレスポンス
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorResponse handleMethodArgumentNotValidException(MethodArgumentNotValidException ex) {
        Map<String, List<String>> errors = ex.getBindingResult().getFieldErrors().stream()
                .collect(Collectors.groupingBy(
                        FieldError::getField,
                        Collectors.mapping(FieldError::getDefaultMessage, Collectors.toList())));
        return new ErrorResponse("入力エラーがあります。", errors);
    }

    /**
     * UseCaseExceptionをハンドリングする
     *
     * @param ex 例外オブジェクト
     * @return エラーレスポンス
     */
    @ExceptionHandler(UseCaseException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorResponse handleUseCaseException(UseCaseException ex) {
        return new ErrorResponse(ex.getMessage(), null);
    }
}
