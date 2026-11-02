# Checkout v2 launch (app release 3.2.0): tomorrow

- Unit and widget tests: green.
- Integration test for checkout: failing on payment confirmation timeout.
- Release-candidate smoke test on real devices: not run since the last
  payment-provider SDK update.
- Crash reporting: enabled, but debug symbols for the obfuscated release build
  are not uploaded.
- Production dashboard: crash-free rate and API latency exist; payment failure
  and duplicate-charge alerts do not.
- Feature flag: checkout v2 can be turned off remotely (clients refresh remote
  config every 12 hours); a minimum-supported-version setting exists.
- Rollout: Play staged rollout and App Store phased release are configured.
- Recovery owner and steps (flag off, halt rollout, fix-forward build): not
  documented.
- Backend change: additive nullable column, migration tested on staging; API
  responses are unchanged for app versions 3.0 and 3.1.
- Store review: build approved; release set to manual.
- Support and on-call have not received the launch runbook.
