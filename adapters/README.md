# NATS protocol adapters

Adapters live at the protocol boundary. Each adapter owns all channel-specific
state for its transport and delivers the exact NATS wire commands it receives to
the same command handler used by the TCP path.

Supported modes:

- `mode="QUIC"`: the QUIC implementation accepts TLS 1.3/mTLS connections and
  passes each bidirectional stream to `quic.deliverBidirectionalStream`.
- `mode="gRPC"`: the HTTP/2 layer validates mTLS and passes the reassembled
  request body to `grpc.deliverGrpcMessages`, which unwraps the gRPC 5-byte
  message prefix and forwards raw NATS commands.
- `mode="WEBSOCKET"`: `websocket.acceptHandshake` negotiates the `nats.v1`
  subprotocol, `websocket.deliverFrames` unwraps WebSocket frames, and every
  text/binary payload is delivered as a NATS command.

## mTLS for subscribers

Call `mtls.registerSubscriberMtls` when an Agent subscribes. It creates or reuses
an Ed25519 Agent CA and issues a short-lived client/server certificate for the
subscriber with SAN entries for both the Agent id and subscribed subject. The
resulting CA certificate, subscriber certificate, and key paths are then supplied
to the selected adapter through `protocol.MtlsOptions`.
