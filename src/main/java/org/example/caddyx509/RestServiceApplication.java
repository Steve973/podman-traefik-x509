package org.example.caddyx509;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.security.config.annotation.method.configuration.EnableGlobalMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.web.SecurityFilterChain;

@EnableWebSecurity
@EnableGlobalMethodSecurity(prePostEnabled = true)
@SpringBootApplication
public class RestServiceApplication {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.x509();
        return http.build();
    }

    public static void main(String[] args) {
        SpringApplication.run(RestServiceApplication.class, args);
    }
}
