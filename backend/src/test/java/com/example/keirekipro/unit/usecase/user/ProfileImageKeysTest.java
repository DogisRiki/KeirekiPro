package com.example.keirekipro.unit.usecase.user;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;

import com.example.keirekipro.usecase.user.ProfileImageKeys;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class ProfileImageKeysTest {

    private static final UUID USER_ID = UUID.fromString("123e4567-e89b-12d3-a456-426614174000");

    @Test
    @DisplayName("拡張子がある場合、ユーザーID + . + 拡張子のファイル名になる")
    void test1() {
        assertThat(ProfileImageKeys.fileName(USER_ID, "png"))
                .isEqualTo("123e4567-e89b-12d3-a456-426614174000.png");
    }

    @Test
    @DisplayName("拡張子が空の場合、ユーザーIDのみのファイル名になる")
    void test2() {
        assertThat(ProfileImageKeys.fileName(USER_ID, ""))
                .isEqualTo("123e4567-e89b-12d3-a456-426614174000");
    }

    @Test
    @DisplayName("取り得るキーは、許可する拡張子ごとに保存プレフィックス + ファイル名になる")
    void test3() {
        assertThat(ProfileImageKeys.keysOf(USER_ID)).containsExactly(
                "/profile/image/123e4567-e89b-12d3-a456-426614174000.jpg",
                "/profile/image/123e4567-e89b-12d3-a456-426614174000.jpeg",
                "/profile/image/123e4567-e89b-12d3-a456-426614174000.png",
                "/profile/image/123e4567-e89b-12d3-a456-426614174000.gif");
    }
}
