package com.example.keirekipro.unit.infrastructure.shared.pdf;

import static java.util.Objects.requireNonNull;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

import com.example.keirekipro.infrastructure.shared.pdf.OpenHtmlToPdfRenderer;
import com.openhtmltopdf.extend.FSSupplier;
import com.openhtmltopdf.pdfboxout.PdfRendererBuilder;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.MockedConstruction;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class OpenHtmlToPdfRendererTest {

    @Mock
    private ResourceLoader resourceLoader;

    @Test
    @DisplayName("renderメソッドでPdfRendererBuilderに対して必要な設定を行い、生成されたバイト列を返す")
    @SuppressWarnings("unchecked")
    void test1() throws Exception {
        OpenHtmlToPdfRenderer renderer = new OpenHtmlToPdfRenderer(resourceLoader);

        AtomicReference<OutputStream> streamRef = new AtomicReference<>();

        try (MockedConstruction<PdfRendererBuilder> mocked = Mockito.mockConstruction(PdfRendererBuilder.class,
                (mock, context) -> {
                    when(mock.withHtmlContent(anyString(), any())).thenReturn(mock);

                    when(mock.useFont(
                            (FSSupplier<InputStream>) any(FSSupplier.class),
                            anyString(),
                            anyInt(),
                            any(PdfRendererBuilder.FontStyle.class),
                            eq(true)))
                            .thenReturn(mock);

                    when(mock.toStream(any(OutputStream.class))).thenAnswer(invocation -> {
                        streamRef.set(invocation.getArgument(0, OutputStream.class));
                        return mock;
                    });

                    when(mock.useFastMode()).thenReturn(mock);

                    doAnswer(invocation -> {
                        try {
                            requireNonNull(streamRef.get()).write("PDF".getBytes(StandardCharsets.UTF_8));
                        } catch (IOException e) {
                            throw new IllegalStateException("テスト用OutputStream書き込みに失敗しました。", e);
                        }
                        return null;
                    }).when(mock).run();
                })) {

            // 実行
            byte[] result = renderer.render("<html><body>test</body></html>");

            // 検証（生成結果）
            assertThat(result).isEqualTo("PDF".getBytes(StandardCharsets.UTF_8));

            // 検証（builder呼び出し回数）
            assertThat(mocked.constructed()).hasSize(1);

            PdfRendererBuilder constructed = mocked.constructed().get(0);
            verify(constructed).withHtmlContent(anyString(), any());
            verify(constructed, times(2))
                    .useFont(
                            (FSSupplier<InputStream>) any(FSSupplier.class),
                            anyString(),
                            anyInt(),
                            any(PdfRendererBuilder.FontStyle.class),
                            eq(true));
            verify(constructed).toStream(any(OutputStream.class));
            verify(constructed).useFastMode();
            verify(constructed).run();
        }
    }

    @Test
    @DisplayName("openClasspathでResourceLoaderからInputStreamを取得できる")
    void test2() throws Exception {
        OpenHtmlToPdfRenderer renderer = new OpenHtmlToPdfRenderer(resourceLoader);

        String location = "classpath:/fonts/dummy.ttf";
        Resource resource = Mockito.mock(Resource.class);
        when(resource.getInputStream()).thenReturn(new ByteArrayInputStream("FONT".getBytes(StandardCharsets.UTF_8)));
        when(resourceLoader.getResource(location)).thenReturn(resource);

        // 実行（privateメソッドをReflectionで呼び出す）
        InputStream in = requireNonNull(ReflectionTestUtils.invokeMethod(renderer, "openClasspath", location));

        // 検証
        assertThat(in).isNotNull();
        byte[] bytes = in.readAllBytes();
        assertThat(bytes).isEqualTo("FONT".getBytes(StandardCharsets.UTF_8));
    }

    @Test
    @DisplayName("openClasspathでResourceの読み込みに失敗した場合、IllegalStateExceptionがスローされる")
    void test3() throws Exception {
        OpenHtmlToPdfRenderer renderer = new OpenHtmlToPdfRenderer(resourceLoader);

        String location = "classpath:/fonts/ng.ttf";
        Resource resource = Mockito.mock(Resource.class);
        when(resource.getInputStream()).thenThrow(new IOException("read error"));
        when(resourceLoader.getResource(location)).thenReturn(resource);

        assertThatThrownBy(() -> ReflectionTestUtils.invokeMethod(renderer, "openClasspath", location))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("フォントの読み込みに失敗しました")
                .hasMessageContaining(location);
    }
}
