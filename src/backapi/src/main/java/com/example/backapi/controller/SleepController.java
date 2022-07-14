package com.example.backapi.controller;

import java.text.SimpleDateFormat;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.StopWatch;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("sleep")
public class SleepController {
    private final Logger LOGGER = LoggerFactory.getLogger(this.getClass());
    private final SimpleDateFormat DF = new SimpleDateFormat("yyyyMMdd_HHmmss");

    @RequestMapping("/{millis}")
    public Mono<String> get(@PathVariable Integer millis, @RequestHeader Map<String, String> headers) {
        LOGGER.info("sleep: {}", millis);
        StopWatch sw = new StopWatch();
        LOGGER.info("Thread # {}: start {}", Thread.currentThread().getId(), DF.format(Date.from(Instant.now())));
        sw.start();
        return Mono.just(sw)
            .delayElement(Duration.ofMillis(millis))
            .log()
            .map(x -> {
                LOGGER.info("Thread # {}: map {}", Thread.currentThread().getId(), DF.format(Date.from(Instant.now())));
                x.stop();
                return Long.toString(x.getTotalTimeMillis());
            });
    }
}
