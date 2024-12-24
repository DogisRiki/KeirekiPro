package com.example.keirekipro.presentation;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 動作確認用
 */
@RestController
public class HelloWorldController {

    /**
     * 動作確認用
     *
     * @return 動作確認
     */
    @GetMapping("/hello")
    public String hello() {
        return "Hello, world!";
    }
}
