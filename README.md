# lualibs

Foundation libraries used by allay and available to any allay package as
declared dependencies. Each lib is a standalone module that runs in CC and
in standalone Lua (5.1 / 5.3+).

## Libraries

- **hash** — SHA-256 and HMAC-SHA256. FIPS 180-4 / RFC 4231 validated.
- **httpkit** — http.get with retries and timeout.
- **pathkit** — atomic file writes, path helpers, dir walking.
- **log** — leveled logger (DEBUG / INFO / WARN / ERROR) with color when
  running in CC.
- **argparse** — small command-line argument parser with subcommand
  support.

## Tests

    cd tests && lua run_all.lua

## License

MIT.
