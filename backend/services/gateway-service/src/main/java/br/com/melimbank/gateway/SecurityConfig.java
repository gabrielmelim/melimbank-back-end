
package br.com.melimbank.gateway;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.web.server.SecurityWebFilterChain;

@Configuration
@EnableWebFluxSecurity
public class SecurityConfig {
  @Bean
  SecurityWebFilterChain springSecurityFilterChain(ServerHttpSecurity http) {
    return http
            .csrf(ServerHttpSecurity.CsrfSpec::disable)
            .authorizeExchange(reg -> reg
                    .pathMatchers("/actuator/health/**", "/actuator/info").permitAll()
                    .pathMatchers("/swagger-ui/**", "/v3/api-docs/**").permitAll()
                    .anyExchange().permitAll()   // DEV apenas
            )
            .httpBasic(Customizer.withDefaults())
            .build();
  }
}
