# JetStream

JetStream went Generally Available in NATS 2.2.0 and the documentation is now in the core [NATS documentation](https://docs.nats.io/jetstream).

## Protocol adapters

The repository includes Zig protocol adapters for `mode="QUIC"`, `mode="gRPC"`, and `mode="WEBSOCKET"`. The adapters encapsulate protocol-specific channel management and forward the same NATS wire commands to the command handler used by the TCP path, so clients can switch transports without renaming commands or changing command semantics.

The shared TCP parser preserves complete NATS frames, including payload-bearing commands such as `PUB`, `HPUB`, `MSG`, and `HMSG`. QUIC streams, gRPC messages, and WebSocket text/binary frames are unwrapped by their adapter and then delivered as raw NATS command bytes.

Subscriber security is handled with mTLS. When an Agent registers as a subscriber, call `mtls.registerSubscriberMtls` to generate Ed25519 subscriber material; pass the resulting certificate, key, and CA paths into the selected adapter's `protocol.MtlsOptions`.
