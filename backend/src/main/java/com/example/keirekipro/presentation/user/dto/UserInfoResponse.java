package com.example.keirekipro.presentation.user.dto;

import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * ユーザー情報レスポンス
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class UserInfoResponse {

    private String id;

    private String email;

    private String username;

    private boolean hasPassword;

    private String profileImage;

    private boolean twoFactorAuthEnabled;

    private List<String> authProviders;
}
