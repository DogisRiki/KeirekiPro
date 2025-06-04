package com.example.keirekipro.config;

import java.io.IOException;
import java.util.Properties;

import org.springframework.beans.factory.config.YamlPropertiesFactoryBean;
import org.springframework.core.env.PropertiesPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.support.EncodedResource;
import org.springframework.core.io.support.PropertySourceFactory;
import org.springframework.lang.NonNull;
import org.springframework.lang.Nullable;

/**
 * TestPropertySourceをyamlに対応させる
 */
public class YamlPropertySourceFactory implements PropertySourceFactory {
    @Override
    public @NonNull PropertySource<?> createPropertySource(@Nullable String name, @NonNull EncodedResource resource)
            throws IOException {
        YamlPropertiesFactoryBean factory = new YamlPropertiesFactoryBean();
        factory.setResources(resource.getResource());
        Properties properties = factory.getObject();
        if (properties == null) {
            properties = new Properties();
        }
        String sourceName = name != null ? name : resource.getResource().getFilename();
        if (sourceName == null) {
            sourceName = "yamlPropertySource";
        }
        return new PropertiesPropertySource(sourceName, properties);
    }
}
