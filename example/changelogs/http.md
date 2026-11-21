## 1.6.0

* **Breaking** Change the behavior of `Request.body` so that a charset
  parameter is only added for text and XML media types. This brings the
  behavior of `package:http` in line with RFC-8259.
* On the web, fix cancellations for `StreamSubscription`s of response bodies
  waiting for the next chunk.
* Export `MediaType` from `package:http_parser`.
* Added a section on testing to `README.md`.

## 1.5.0

* Fixed a bug in `IOClient` where the `HttpClient`'s response stream was
  cancelled after the response stream was completed.
* Added support for aborting requests before they complete.
* Clarify that some header names may not be sent/received.

## 1.4.0

* Fixed default encoding for application/json without a charset
  to use utf8 instead of latin1, ensuring proper JSON decoding.
* Avoid references to `window` in `BrowserClient`, restoring support for web
  workers and NodeJS.

## 1.3.0

* Fixed unintended HTML tags in doc comments.
* Switched `BrowserClient` to use Fetch API instead of `XMLHttpRequest`.

## 1.2.2

* Require package `web: '>=0.5.0 <2.0.0'`.
