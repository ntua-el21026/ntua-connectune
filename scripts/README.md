# Client source-policy checks

Run `python3 scripts/check_client_security.py` from the repository root. It
checks for client private-key material, credential-asset startup loading, and
privileged FCM signing/sending code. Failure messages never echo credentials.
These are static checks; use Flutter analysis, tests, device runs, and separate
Firebase access-rule review to assess runtime behavior.
