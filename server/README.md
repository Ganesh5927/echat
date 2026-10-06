# Server

The only implemented server component is the Phase 4 local relay foundation in `relay/`. It uses Shelf, authenticates through an injected transport-authenticator boundary, stores opaque packet bytes in a bounded in-memory queue, and requires a caller-supplied TLS `SecurityContext` to listen.

The identity, gateway, delivery, and abuse directories remain design placeholders. No credentials, certificates, deployment manifests, database, or persistent queue are included.
