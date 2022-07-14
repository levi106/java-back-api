package com.example.backapi.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.test.web.reactive.server.WebTestClient;

@WebFluxTest(ReactorController.class)
public class ReactorControllerTest {
    @Autowired
    private WebTestClient webTestClient;

    @Test
    void getValue() throws Exception {
        webTestClient.get()
            .uri("/reactor/{id}", 1234)
            .exchange()
            .expectStatus().isOk()
            .expectBody(String.class)
            .isEqualTo("Id: 1234");
    }
}
