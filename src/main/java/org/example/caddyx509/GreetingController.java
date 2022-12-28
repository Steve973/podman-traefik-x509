package org.example.caddyx509;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreetingController {

	private static final String template = "Hello, %s! cert subject: %s | cert issuer: %s";
	private final AtomicLong counter = new AtomicLong();

	@GetMapping("/greeting")
	public Greeting greeting(@RequestParam(value = "name", defaultValue = "World") String name,
							 @RequestHeader("X-Forwarded-Tls-Client-Cert-Info") String certInfo) {
		String decodedCertInfo = URLDecoder.decode(certInfo, StandardCharsets.UTF_8);
		Pattern pattern = Pattern.compile("^Subject=\"(?<subject>.+)\";Issuer=\"(?<issuer>.+)\"$");
		Matcher matcher = pattern.matcher(decodedCertInfo);
		String subject = "Unknown";
		String issuer = "Unknown";
		if (matcher.matches()) {
			subject = matcher.group("subject");
			issuer = matcher.group("issuer");
		}
		return new Greeting(counter.incrementAndGet(), String.format(template, name, subject, issuer));
	}
}
