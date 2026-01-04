package com.example.keirekipro.unit.domain.model.user;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.keirekipro.domain.model.user.RoleName;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class RoleNameTest {

    @Test
    @DisplayName("デフォルトロールはUSERを返す")
    void test1() {
        assertThat(RoleName.defaultRole()).isEqualTo(RoleName.USER);
    }
}
