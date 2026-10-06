# Privacy model

## Principle

Privacy is a system property, not a UI toggle. It must be designed into identity, protocol choice, storage, notification behavior, metadata retention, and server architecture.

## Privacy dimensions

- message content confidentiality
- attachment confidentiality
- local storage security
- server-side data minimization
- notification metadata controls
- account and device visibility
- contact discovery policy
- retention and deletion policy
- analytics and crash reporting policies

## Default privacy posture

The default posture for MVP is:

- no third-party analytics by default
- no plaintext logging
- no plaintext message storage on server
- minimal relay metadata retention
- generic push notifications without message contents
- device-bound identities instead of phone number dependence

## Privacy dashboard

The product should expose a privacy dashboard including:

- messages stored locally
- server storage policy
- notification policy
- analytics policy
- contact discovery policy
- retention periods
- account and device information
- permissions

## Limits and assumptions

Privacy design does not eliminate all risk. A relay provider may still observe operational metadata, and the user may still leak information through connection patterns, device use, or social context.

The platform should provide clear disclosure and secure defaults rather than over-claiming privacy guarantees.
