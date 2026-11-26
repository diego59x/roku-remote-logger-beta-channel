# RemoteLogger

A BrightScript/SceneGraph library that ships logs from a running Roku channel to a log server in near real time.

It exists for the builds where the debug console is out of reach: beta channels, QA builds on retail devices, and field devices on someone else's network. Those builds have no telnet on port 8085, so a problem that only reproduces there leaves no trace.

> **Status: M1 done.** The core pipeline works end to end on a device: facade, logger Task, batching, HTTP transport (protocol v1) and the receiver. The public API and configuration keys may still change until milestone M2 freezes them.

## What it does

- Gives each component a small logger object (`info`, `warn`, `error`, ...).
- Hands every entry to one background Task, which batches entries and POSTs them over HTTP.
- Costs nothing when disabled: no Task, no network, no allocation per call.
- Plugs into a logger the host app already has, through a thin adapter, so call sites do not change.
- Ships with a receiver that needs only the Python standard library.

## What it is not

- Not an analytics or APM product. It does not replace a monitoring vendor and should run next to one without interfering.
- Not meant to be on for the general public. It is a diagnostic tool for beta and QA audiences, behind a switch the host app controls.

## Quick start

One beta build serves every tester. Nothing about the logger is fixed in the build: each tester runs the server on their own machine and launches the channel with that machine's address and the level they want. Launched without an address, the logger stays off.

1. Start the receiver on a machine the Roku can reach:

   ```bash
   python3 server/LogLocalServer.py                  # options: --port 8085 --log-dir server/logs
   # Log server listening. Device endpoint: http://192.168.1.20:8085/v1/logs
   ```

   Each session is written to its own file in `server/logs/`, one JSON entry per line: follow it with `tail -f server/logs/*.jsonl` and filter it with `jq`, for example `jq -c 'select(.lvl == "error")' server/logs/*.jsonl`.

2. Start the library once, with the values the tester chose at launch. The sample reads them from deep-link parameters: `main()` hands them to the scene after `screen.show()`, and the scene starts the library when they arrive:

   ```brightscript
   ' main(), after screen.show(). Beta builds only: a public build must ignore these parameters.
   scene.launchArgs = { remoteLog: args.remoteLog, remoteLogLevel: args.remoteLogLevel }

   ' The scene, observing launchArgs:
   sub onLaunchArgs()
       args = m.top.launchArgs
       RemoteLogger_init({
           enabled: args.remoteLog <> invalid
           endpoint: args.remoteLog
           level: args.remoteLogLevel          ' "info" when absent
       })
   end sub
   ```

   A deep link is one source. A registry value or a remote flag works the same way: see [Integration: decide who gets it](docs/INTEGRATION.md#4-decide-who-gets-it).

3. Log from any component or Task:

   ```brightscript
   sub init()
       m.log = RemoteLogger("HomeScreen")
       m.log.info("row loaded", { rowId: 3, items: 20 })
   end sub
   ```

4. Each tester launches the channel with their own server's endpoint, URL-encoded, and a level. The device answers `404` to an unencoded URL:

   ```bash
   curl -d '' 'http://<roku-ip>:8060/launch/<channel-id>?remoteLog=http%3A%2F%2F<laptop-ip>%3A8085%2Fv1%2Flogs&remoteLogLevel=debug'
   ```

   To log at another level, relaunch with another value.

To try it with the sample channel, sideload `out/channel.zip` (see [Build](#build)) and launch it as in step 4, with `dev` as the channel id. The sample shows on screen whether remote logging is on, then logs from its scene every 5 seconds and from a Task.

If the host app already has a logger, do not add call sites. Write an adapter instead: see [Integration](docs/INTEGRATION.md).

## Documentation

| Document | Read it to learn |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | The parts, the threading model, the performance rules and the reasons behind them |
| [Integration](docs/INTEGRATION.md) | How to install the library and connect it to an app, with one flow per kind of host app |
| [Protocol](docs/PROTOCOL.md) | The HTTP contract between the device and the server |
| [Roadmap](docs/ROADMAP.md) | Milestones, their exit criteria, and what is out of scope |

## Repository layout

```
src/          the library (plain BrightScript)
sample/       a channel that exercises the library on a device
server/       log receiver
docs/         these documents
```

The production build combines `src/` and `sample/` into one sideloadable channel. Rooibos tests live in `tests/` and use a separate build configuration.

## Build

Requires Node.js (tested with v22.22.1).

```bash
npm ci
npm run build
```

The build compiles `src/` and `sample/` with BrighterScript (`bsc`) into one package and writes it to `out/channel.zip`. Sideload that zip through the device's developer installer (open `http://<device-ip>` in a browser with developer mode enabled).

Lint and format (`bslint.json`, `bsfmt.json`):

```bash
npm run lint           # bslint, fails on errors
npm run format         # rewrite .brs and .bs files in place
npm run format:check   # fails if any .brs or .bs file is not formatted
```

Run the unit-test build:

```bash
npm test
```

This compiles the Rooibos test suite for CI. The test package holds the library (`src/`) and the specs (`tests/`, placed under `source/tests`), but not the sample channel: Rooibos generates its own `main` for it. To execute it on a Roku device, configure `ROKU_HOST` (and `ROKU_PASSWORD` if needed), then run `npm run test:device`. For a Roku Cloud Emulator, set `ROKU_RCE_TOKEN` and pass either `--esn <ESN>` or `--instance-url <URL>` to the script.

## Safety

- **Do not log personal data.** No emails, user tokens, account identifiers or full request URLs that carry credentials.
- **Leave it off by default.** The host app turns it on for a beta or QA audience; a public build should ship with `enabled: false`.
- **The bundled server is for a trusted network.** It has no authentication and no TLS. See [Architecture: security](docs/ARCHITECTURE.md#security) before pointing a device at anything else.

## Contributing

1. Branch from `main`: `git checkout -b feature/<name>`.
2. Keep the library in plain BrightScript (see [Architecture: constraints](docs/ARCHITECTURE.md#design-constraints)).
3. Open a pull request and ask for review. A change to the wire format also updates [Protocol](docs/PROTOCOL.md).

## License

MIT. See [LICENSE](LICENSE).
