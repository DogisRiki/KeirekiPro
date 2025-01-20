package com.example.keirekipro.domain.shared.exception;

import java.util.Collections;
import java.util.List;
import java.util.Map;

import lombok.Getter;

/**
 * ドメイン層で発生した例外
 */
@Getter
public class DomainException extends RuntimeException {

    /**
     * エラーが発生したフィールド名
     */
    private final Map<String, List<String>> errors;

    /**
     * コンストラクター
     */
    public DomainException(Map<String, List<String>> errors) {
        this.errors = errors != null ? Collections.unmodifiableMap(errors) : Map.of();
    }
}
