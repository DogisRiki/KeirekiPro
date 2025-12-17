package com.example.keirekipro.presentation.shared;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import com.auth0.jwt.exceptions.JWTVerificationException;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.shared.exception.BaseException;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import jakarta.servlet.http.HttpServletResponse;

/**
 * アプリケーション全体の例外を処理するハンドラー
 */
@RestControllerAdvice
public class AppExceptionHandler {

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * AuthenticationCredentialsNotFoundExceptionをハンドリングする
     *
     * @return エラーレスポンス
     */
    @ExceptionHandler(AuthenticationCredentialsNotFoundException.class)
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public ErrorResponse handleAuthenticationException(AuthenticationCredentialsNotFoundException ex,
            HttpServletResponse response) {
        // トークン Cookie をクリア
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("accessToken", isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("refreshToken", isSecureCookie));
        return new ErrorResponse(ex.getMessage(), Collections.emptyMap());
    }

    /**
     * JWTVerificationExceptionをハンドリングする
     *
     * @return エラーレスポンス
     */
    @ExceptionHandler(JWTVerificationException.class)
    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    public ErrorResponse handleJwtVerificationException() {
        return new ErrorResponse("認証に失敗しました。", Collections.emptyMap());
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
     * BaseExceptionをハンドリングする
     *
     * @param ex 例外オブジェクト
     * @return エラーレスポンス
     */
    @ExceptionHandler(BaseException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorResponse handleBaseException(BaseException ex) {
        return new ErrorResponse(ex.getMessage(), ex.getErrors());
    }

    /**
     * 想定外の例外をハンドリングする
     *
     * @param ex 例外オブジェクト
     * @return エラーレスポンス
     */
    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ErrorResponse handleUnexpectedException(Exception ex) {
        // ログ出力などはここで行う
        return new ErrorResponse("予期せぬエラーが発生しました。", Collections.emptyMap());
    }
}
