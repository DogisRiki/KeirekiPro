package com.example.keirekipro.presentation.user.dto;

import org.springframework.web.multipart.MultipartFile;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * ユーザー情報更新リクエスト
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
public class UpdateUserInfoRequest {

    private String username;

    private MultipartFile profileImage;

    private boolean twoFactorAuthEnabled;
}
