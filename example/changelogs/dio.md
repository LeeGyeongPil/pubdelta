# CHANGELOG

**Before you upgrade: Breaking changes might happen in major and minor versions of packages.<br/>
See the [Migration Guide][] for the complete breaking changes list.**

## Unreleased

*None.*

## 5.11.1

- Fix response stream not propagating backpressure to the underlying socket.
  When a consumer paused the stream, the source subscription was never paused,
  so the network kept buffering response data into memory, risking OOM on
  constrained platforms.
- Make the `badCertificateCallback` pinning test deterministic by pinning a
  fingerprint that cannot match the served certificate, instead of relying on
  badssl.com hosts serving different certificates.
- Fix `NoSuchMethodError` when using a class that `implements Interceptor`
  instead of `extends Interceptor`. The interceptor pipeline was calling private
  dispatch methods that only exist on `Interceptor` subclasses, breaking any
  class using interface implementation.

## 5.11.0

- Add `query` and `queryUri` convenience methods for the HTTP QUERY method defined in RFC 10008,
  which allows a request body for safe, idempotent queries.
- Fix `FusedTransformer` (the default transformer) throwing a `FormatException`
  on an empty response body when a custom `responseDecoder` is set. It now
  returns an empty result, consistent with `SyncTransformer` and
  `BackgroundTransformer`.
- Fix concurrent requests hanging or reporting uncaught errors when an
  interceptor shares a failing Future, such as in request deduplication.

## 5.10.0

- Fix `FormData.readAsBytes` excessive memory usage with large payloads by replacing the O(n²) `reduce`+spread approach with a pre-allocated `Uint8List`.
- Fix request hanging indefinitely when async interceptor callbacks throw without calling the handler.
- Fix `HttpException: Connection closed before full header was received` being reported as `DioExceptionType.unknown`.
- Add `transformTimeout` to bound long-running response transformations, including background JSON decoding.
  On web, timeout handling is best-effort because synchronous JavaScript work cannot be preempted.
- Fix `FormData.clone()` dropping `boundaryName` and `camelCaseContentDisposition`, so a retried multipart request now keeps the original options instead of silently falling back to the defaults.
- Fix `QueuedInterceptor` stalling its queue forever when the active request is cancelled while its callback is still pending (never calls `next`/`resolve`/`reject`), which blocked every subsequent request routed through the interceptor.
- Fix `ErrorInterceptorHandler.reject(..., true)` not continuing to following error interceptors in queued interceptors.

## 5.9.2

- Fixes `kIsWeb` across different Flutter SDKs.
- Provides `httpVersion` in `Response.extra` when using `IOHttpClientAdapter`.
