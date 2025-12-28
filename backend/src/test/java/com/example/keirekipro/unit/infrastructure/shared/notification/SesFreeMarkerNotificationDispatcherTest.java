package com.example.keirekipro.unit.infrastructure.shared.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.io.IOException;
import java.io.StringWriter;

import com.example.keirekipro.infrastructure.shared.aws.config.AwsSesProperties;
import com.example.keirekipro.infrastructure.shared.notification.SesFreeMarkerNotificationDispatcher;
import com.example.keirekipro.usecase.auth.notification.PasswordResetNotification;
import com.example.keirekipro.usecase.auth.notification.TwoFactorCodeNotification;
import com.example.keirekipro.usecase.shared.notification.NotificationDispatcher;
import com.example.keirekipro.usecase.user.notification.UserDeletedNotification;
import com.example.keirekipro.usecase.user.notification.UserRegisteredNotification;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import freemarker.template.Configuration;
import freemarker.template.Template;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.SendEmailRequest;

@ExtendWith(MockitoExtension.class)
class SesFreeMarkerNotificationDispatcherTest {

    @Mock
    private SesClient sesClient;

    @Mock
    private AwsSesProperties sesProperties;

    @Mock
    private Configuration freeMarkerConfiguration;

    @Mock
    private Template freeMarkerTemplate;

    private NotificationDispatcher dispatcher;

    @BeforeEach
    void setUp() {
        // test5(テンプレート取得失敗) では fromAddress が参照されないため lenient にする
        lenient().when(sesProperties.getFromAddress()).thenReturn("no-reply@keirekipro.click");
        dispatcher = new SesFreeMarkerNotificationDispatcher(sesClient, sesProperties, freeMarkerConfiguration);
    }

    @Test
    @DisplayName("UserRegisteredNotificationを送達すると、適切な件名・テンプレートでSES送信される")
    void test1() throws Exception {
        when(freeMarkerConfiguration.getTemplate("user-registered.ftl")).thenReturn(freeMarkerTemplate);

        doAnswer(invocation -> {
            StringWriter writer = invocation.getArgument(1, StringWriter.class);
            writer.write("BODY_REGISTERED");
            return null;
        }).when(freeMarkerTemplate).process(anyMap(), any(StringWriter.class));

        dispatcher.dispatch(new UserRegisteredNotification(
                "to@example.com",
                "alice",
                "Site",
                "https://site.example"));

        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);
        verify(sesClient).sendEmail(captor.capture());

        SendEmailRequest req = captor.getValue();
        assertThat(req.source()).isEqualTo("no-reply@keirekipro.click");
        assertThat(req.destination().toAddresses()).containsExactly("to@example.com");
        assertThat(req.message().subject().data()).isEqualTo("【Site】新規登録完了のお知らせ");
        assertThat(req.message().body().text().data()).isEqualTo("BODY_REGISTERED");
    }

    @Test
    @DisplayName("UserDeletedNotificationを送達すると、適切な件名・テンプレートでSES送信される")
    void test2() throws Exception {
        when(freeMarkerConfiguration.getTemplate("user-deleted.ftl")).thenReturn(freeMarkerTemplate);

        doAnswer(invocation -> {
            StringWriter writer = invocation.getArgument(1, StringWriter.class);
            writer.write("BODY_DELETED");
            return null;
        }).when(freeMarkerTemplate).process(anyMap(), any(StringWriter.class));

        dispatcher.dispatch(new UserDeletedNotification(
                "to@example.com",
                "alice",
                "Site",
                "https://site.example"));

        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);
        verify(sesClient).sendEmail(captor.capture());

        SendEmailRequest req = captor.getValue();
        assertThat(req.source()).isEqualTo("no-reply@keirekipro.click");
        assertThat(req.destination().toAddresses()).containsExactly("to@example.com");
        assertThat(req.message().subject().data()).isEqualTo("【Site】退会手続き完了のお知らせ");
        assertThat(req.message().body().text().data()).isEqualTo("BODY_DELETED");
    }

    @Test
    @DisplayName("PasswordResetNotificationを送達すると、適切な件名・テンプレートでSES送信される")
    void test3() throws Exception {
        when(freeMarkerConfiguration.getTemplate("password-reset.ftl")).thenReturn(freeMarkerTemplate);

        doAnswer(invocation -> {
            StringWriter writer = invocation.getArgument(1, StringWriter.class);
            writer.write("BODY_PASSWORD_RESET");
            return null;
        }).when(freeMarkerTemplate).process(anyMap(), any(StringWriter.class));

        dispatcher.dispatch(new PasswordResetNotification(
                "to@example.com",
                "https://site.example/password/reset/xxx",
                "Site",
                "https://site.example"));

        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);
        verify(sesClient).sendEmail(captor.capture());

        SendEmailRequest req = captor.getValue();
        assertThat(req.source()).isEqualTo("no-reply@keirekipro.click");
        assertThat(req.destination().toAddresses()).containsExactly("to@example.com");
        assertThat(req.message().subject().data()).isEqualTo("【Site】パスワードリセットのご案内");
        assertThat(req.message().body().text().data()).isEqualTo("BODY_PASSWORD_RESET");
    }

    @Test
    @DisplayName("TwoFactorCodeNotificationを送達すると、適切な件名・テンプレートでSES送信される")
    void test4() throws Exception {
        when(freeMarkerConfiguration.getTemplate("two-factor-auth.ftl")).thenReturn(freeMarkerTemplate);

        doAnswer(invocation -> {
            StringWriter writer = invocation.getArgument(1, StringWriter.class);
            writer.write("BODY_2FA");
            return null;
        }).when(freeMarkerTemplate).process(anyMap(), any(StringWriter.class));

        dispatcher.dispatch(new TwoFactorCodeNotification(
                "to@example.com",
                "123456",
                "Site",
                "https://site.example"));

        ArgumentCaptor<SendEmailRequest> captor = ArgumentCaptor.forClass(SendEmailRequest.class);
        verify(sesClient).sendEmail(captor.capture());

        SendEmailRequest req = captor.getValue();
        assertThat(req.source()).isEqualTo("no-reply@keirekipro.click");
        assertThat(req.destination().toAddresses()).containsExactly("to@example.com");
        assertThat(req.message().subject().data()).isEqualTo("【Site】2段階認証コードのお知らせ");
        assertThat(req.message().body().text().data()).isEqualTo("BODY_2FA");
    }

    @Test
    @DisplayName("テンプレート取得に失敗した場合、RuntimeExceptionがスローされ、送信が行われない")
    void test5() throws Exception {
        when(freeMarkerConfiguration.getTemplate("user-registered.ftl"))
                .thenThrow(new IOException("Template not found"));

        assertThatThrownBy(() -> dispatcher.dispatch(new UserRegisteredNotification(
                "to@example.com",
                "alice",
                "Site",
                "https://site.example")))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("user-registered.ftl");

        verifyNoInteractions(sesClient);
    }
}
