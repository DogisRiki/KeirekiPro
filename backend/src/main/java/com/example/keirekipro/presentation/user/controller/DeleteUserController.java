package com.example.keirekipro.presentation.user.controller;

import java.util.UUID;

import com.example.keirekipro.presentation.security.CurrentUserFacade;
import com.example.keirekipro.presentation.shared.utils.CookieUtil;
import com.example.keirekipro.usecase.user.DeleteUserUseCase;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import lombok.RequiredArgsConstructor;

import jakarta.servlet.http.HttpServletResponse;

/**
 * ユーザー退会コントローラー
 */
@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
@Tag(name = "users", description = "ユーザーに関するエンドポイント")
public class DeleteUserController {

    private final DeleteUserUseCase deleteUserUseCase;

    private final CurrentUserFacade currentUserFacade;

    @Value("${cookie.secure:false}")
    private boolean isSecureCookie;

    /**
     * ユーザー退会エンドポイント
     */
    @DeleteMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Operation(summary = "ユーザー退会", description = "ユーザーの退会処理を実行し、ユーザー情報を削除する")
    public void deleteUser(HttpServletResponse response) {
        UUID userId = UUID.fromString(currentUserFacade.getUserId());
        deleteUserUseCase.execute(userId);
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("accessToken", isSecureCookie));
        response.addHeader("Set-Cookie", CookieUtil.deleteCookie("refreshToken", isSecureCookie));
    }
}
