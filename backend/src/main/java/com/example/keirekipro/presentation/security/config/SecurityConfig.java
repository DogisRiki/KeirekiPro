package com.example.keirekipro.presentation.security.config;

import java.util.Arrays;

import com.example.keirekipro.presentation.security.jwt.JwtAuthenticationFilter;
import com.example.keirekipro.presentation.security.jwt.JwtProvider;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.session.NullAuthenticatedSessionStrategy;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfFilter;
import org.springframework.security.web.csrf.CsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import lombok.RequiredArgsConstructor;

/**
 * セキュリティ設定クラス
 */
@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    @Value("${cors.allowed-origins}")
    private String allowedOrigins;

    private final JwtProvider jwtProvider;

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {

        CsrfTokenRepository tokenRepository = csrfTokenRepository();

        http
                // CORSの設定を有効化
                .cors(cors -> cors
                        .configurationSource(corsConfigurationSource()))

                // CSRFの設定
                .csrf(csrf -> csrf
                        .csrfTokenRepository(tokenRepository)
                        // 認証成立時のSessionAuthenticationStrategyをno-op化して、CSRFトークンが自動で消される挙動を抑止する
                        .sessionAuthenticationStrategy(new NullAuthenticatedSessionStrategy())
                        // マスクしないハンドラを使用（フロントはCookie値をそのままヘッダへ入れる）
                        .csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler())
                        // CSRF保護が不要なパスを設定
                        .ignoringRequestMatchers(
                                "/api/auth/**",
                                "/actuator/**",
                                "/swagger-ui/**",
                                "/swagger-ui.html",
                                "/v3/api-docs",
                                "/v3/api-docs/**"))

                // セッションを使用しない設定（JWTベースの認証のため）
                // ただし「認証イベントでCSRFトークンを削除する」挙動を止めるため、SessionAuthenticationStrategyをno-op化する
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                        .sessionAuthenticationStrategy(new NullAuthenticatedSessionStrategy()))

                // 認証情報が無い場合は401を返す
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))

                // エンドポイントの認可設定
                .authorizeHttpRequests(auth -> auth
                        // Preflightは常に許可（CORSのOPTIONSを401にしない）
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        // 認証関連のエンドポイントは認証不要
                        .requestMatchers("/api/auth/**").permitAll()
                        // Actuator関連のエンドポイントを許可
                        .requestMatchers("/actuator/**").permitAll()
                        // Swagger UI関連のエンドポイントを許可
                        .requestMatchers(
                                "/swagger-ui/**",
                                "/swagger-ui.html",
                                "/v3/api-docs",
                                "/v3/api-docs/**")
                        .permitAll()
                        // その他のエンドポイントは認証必要
                        .anyRequest().authenticated())

                // JWT認証フィルター（OPTIONSはフィルタ側でスキップ）
                .addFilterBefore(new JwtAuthenticationFilter(jwtProvider), CsrfFilter.class)

                // /api/auth/** 等（CSRF除外）でもXSRF-TOKENを確実にCookieへ出す（SPA向け）
                .addFilterAfter(new CsrfCookieFilter(tokenRepository), CsrfFilter.class);

        return http.build();
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(Arrays.asList(allowedOrigins.split(",")));
        configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        configuration.setAllowedHeaders(Arrays.asList("*"));
        configuration.setAllowCredentials(true);
        configuration.setExposedHeaders(Arrays.asList("Content-Disposition")); // クライアントからContent-Dispositionを読めるようにする
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }

    @Bean
    CsrfTokenRepository csrfTokenRepository() {
        CookieCsrfTokenRepository repository = CookieCsrfTokenRepository.withHttpOnlyFalse();
        repository.setCookieName("XSRF-TOKEN");
        repository.setHeaderName("X-XSRF-TOKEN");
        repository.setCookiePath("/");
        return repository;
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
