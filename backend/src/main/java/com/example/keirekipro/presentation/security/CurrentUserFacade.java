package com.example.keirekipro.presentation.security;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/**
 * 認証済みユーザーIDを取得するファサードクラス
 */
@Component
public class CurrentUserFacade {

    /**
     * 認証済みユーザーのユーザーIDを取得する
     *
     * @return ユーザーID
     */
    public String getUserId() {

        // SecurityContextHolderから認証済みユーザ情報を取得する
        var auth = SecurityContextHolder.getContext().getAuthentication();

        if (auth == null) {
            throw new AuthenticationCredentialsNotFoundException("認証されていないユーザーからのリクエストです。");
        }

        return (String) auth.getPrincipal();
    }
}
