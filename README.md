# roku-remote-logger

A BrightScript/SceneGraph library that ships logs from a running Roku channel to a log server in near real time.

It exists for the builds where the debug console is out of reach: beta channels, QA builds on retail devices, and field devices on someone else's network. Those builds have no telnet on port 8085, so a problem that only reproduces there leaves no trace.

> **Status: planning.** The repository holds a proof of concept (one Task that POSTs a string, and a Python receiver). The documents below describe the library to be built. Names and signatures marked *planned* may change until milestone M1 ships.

## What it does

- Gives each component a small logger object (`info`, `warn`, `error`, ...).
- Hands every entry to one background Task, which batches entries and POSTs them over HTTP.
- Costs nothing when disabled: no Task, no network, no allocation per call.
- Plugs into a logger the host app already has, through a thin adapter, so call sites do not change.
- Ships with a receiver that needs only the Python standard library.

## What it is not

- Not an analytics or APM product. It does not replace a monitoring vendor and should run next to one without interfering.
- Not meant to be on for the general public. It is a diagnostic tool for beta and QA audiences, behind a switch the host app controls.

## Quick start (planned API)

1. Start the receiver on a machine the Roku can reach:

   ```bash
   python3 server/LogLocalServer.py
   # Log server listening on http://192.168.1.20:8085
   ```

2. Initialise the library once, on the render thread, early in the scene's `init()`:

   ```brightscript
   RemoteLogger_init({
       enabled: true
       endpoint: "http://192.168.1.20:8085/v1/logs"
       level: "info"
   })
   ```

3. Log from any component or Task:

   ```brightscript
   sub init()
       m.log = RemoteLogger("HomeScreen")
       m.log.info("row loaded", { rowId: 3, items: 20 })
   end sub
   ```

If the host app already has a logger, do not add call sites. Write an adapter instead: see [Integration](docs/INTEGRATION.md).

## Documentation

| Document | Read it to learn |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | The parts, the threading model, the performance rules and the reasons behind them |
| [Integration](docs/INTEGRATION.md) | How to install the library and connect it to an app, with one flow per kind of host app |
| [Protocol](docs/PROTOCOL.md) | The HTTP contract between the device and the server |
| [Roadmap](docs/ROADMAP.md) | Milestones, their exit criteria, and what is out of scope |

## Repository layout

Current:

```
components/   proof-of-concept scene and upload Task
source/       proof-of-concept entry point and helpers
server/       Python log receiver
```

Target, from milestone M0:

```
src/          the library (plain BrightScript)
sample/       a channel that exercises the library on a device
server/       log receiver and tools
tests/        unit tests
docs/         these documents
```

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
