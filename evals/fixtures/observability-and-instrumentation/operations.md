# Payment retry operations

The retry logic runs inside the mobile app. On-call must be able to answer:

- Are retries recovering transient gateway failures?
- Which gateway and failure class is driving exhaustion?
- Is one payment being charged more than once?
- Which customer-visible payments need intervention now?
- Which app versions and devices are affected, and did the latest release make it worse?

Payment and attempt IDs are safe correlation identifiers. Card numbers,
customer email addresses, and raw gateway responses must never be logged or
sent in telemetry. Analytics and diagnostics run only with user consent, and
the app is often offline.
