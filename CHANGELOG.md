# Changelog

All notable changes to this project are documented in this file.

## 0.1.1 — 2026-11-08

- `A2aEngine.TestPeer` now treats Bandit as an optional dependency. Projects
  that do not use `TestPeer` no longer need Bandit, while projects that do get a
  clear error explaining how to add `{:bandit, "~> 1.5"}`. The library's own
  test suite still uses Bandit as before.
- Tightened the `req` dependency constraint to `~> 0.7.5`, matching the version
  line the HTTP transport is tested against.
- Documented that `A2aEngine.Transport.Http.Plug` must not be mounted behind a
  body-parsing plug such as `Plug.Parsers`, because it reads the raw request
  body itself.
- Documentation and dependency updates for the 0.1.1 release.
