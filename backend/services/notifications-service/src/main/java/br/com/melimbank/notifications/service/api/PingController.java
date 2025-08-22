package br.com.melimbank.notifications.service.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PingController {
  @GetMapping("/ping")
  public String ping() { return "notifications-service: pong"; }
}
