# Test-only TLS fixtures

A throwaway self-signed certificate for `localhost` (valid 2026-10-01 to 2036-09-28) and
its private key, used ONLY by `test/core/network/pinning_test.dart` to run a local TLS
server. They protect nothing and are allow-listed in `.gitleaks.toml`. `pin.txt` is the
certificate's SPKI pin, computed independently with Python `cryptography`.
