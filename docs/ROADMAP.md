# Roadmap

Milestones are in order, and each one leaves something usable. They carry exit criteria and no dates: a milestone is done when its criteria hold on a real device.

| Milestone | Outcome | Status |
|---|---|---|
| [M0 Foundations](#m0-foundations) | A repository others can build, test and contribute to | Not started |
| [M1 Core pipeline](#m1-core-pipeline) | Logs travel from a sample channel to the server in batches | Not started |
| [M2 Integration](#m2-integration) | An existing app adopts the library without touching call sites | Not started |
| [M3 Resilience and performance](#m3-resilience-and-performance) | Safe to leave on for a whole beta session | Not started |
| [M4 Server tools](#m4-server-tools) | Logs from several devices are easy to follow and search with standard tools | Not started |
| [M5 Hardening](#m5-hardening) | Usable outside a trusted local network | Not started |

The proof of concept that exists today (one upload Task and a Python receiver) is the starting point for M1 and M4.

## M0 Foundations

Set the repository up as a library.

- Move to the target layout: `src/`, `sample/`, `server/`, `tests/`, `docs/`.
- Compile and lint the library and the sample channel in one command.
- Add a unit test framework and one passing test.
- Run build, lint and tests in CI on every pull request.
- Choose the public name and prefix (`RemoteLogger_`) and apply them.

**Done when:** a fresh clone builds the sample channel and passes CI with one documented command.

## M1 Core pipeline

Build the path described in [Architecture](ARCHITECTURE.md).

- Facade: `RemoteLogger(tag)` with the five level methods, `write`, and level filtering.
- `RemoteLogger_init` and the single Task on `m.global`.- Queue, batcher and HTTP transport.
- Protocol v1 on both the device and the server ([Protocol](PROTOCOL.md)).
- Disabled mode: no Task, no-op facades.
- Remove the deprecated `InitClientCertificates` call carried by the proof of concept.
- Settle the two M1 [open questions](ARCHITECTURE.md#open-questions) by measuring on a device.

**Done when:** the sample channel logs from the render thread and from a Task, the server shows the entries within the flush interval, and a disabled build creates no Task.

## M2 Integration

Make adoption cheap for an app that already logs.

- Adapter recipes for the four flows in [Integration](INTEGRATION.md), each proven in the sample channel.
- Support for code inside a component library.
- Publish as a `ropm` package; confirm the copy and submodule methods.
- Confirm the library compiles inside a BrighterScript project and passes common lint rule sets when it is not excluded.
- Freeze the public API and the configuration keys.

**Done when:** an app with its own logger sends its existing logs through the library by adding one adapter and one `init` call, with no call site changed.

## M3 Resilience and performance

Make it safe to forget it is on.

- Retry with backoff, bounded ring buffer and dropped-entry accounting.
- Suspend, resume and exit handling, including instant resume.
- Clean stop through a cancel field.
- Profile the per-call cost on a low-end device from the render thread and from a Task; add facade buffering if the numbers call for it.
- Decide on the persisted tail of `error` entries.
- Publish the measured cost in the documentation.

**Done when:** an hour-long session with the server switched off halfway shows no growth in memory, no stall, and a correct dropped count after the server returns; and the measured per-call cost is written down.

## M4 Server tools

Make the output worth reading, without growing the server. It stays one Python file on the standard library, and standard tools do the reading.

- One file per session, named by device and start time, with one JSON entry per line.
- A readable line per entry on the console, as today.
- Duplicate removal and gap reporting from `seq` and `dropped`.
- Documented one-liners for following and filtering: `tail -f`, `grep`, `jq`.

**Done when:** two devices log at once and a reader can follow either one live with `tail -f` and search both afterwards with `grep` or `jq`.

## M5 Hardening

Take it beyond the developer's desk.

- HTTPS endpoints tested end to end.
- Token check on the server, sent through the `headers` option.
- Redaction hook: the host app supplies a function that cleans an entry before it leaves the device.
- Change the level or switch the logger off from the server during a session.- Guidance for hosting the server where remote testers can reach it.

**Done when:** a tester on another network sends logs over HTTPS with a token, and a stray device without the token is refused.

## Later, if needed

Not planned; listed so they are not mistaken for gaps.

- A live view in the browser. `tail -f` on a session file covers the need until several people watch many devices at once.
- Forwarding `roSystemLog` events as entries.
- Capturing crash details at the next launch.
- A transport other than HTTP.
- Exporting to an external log platform.

## Out of scope

- **Fleet monitoring and analytics.** Monitoring vendors do this; the library is for a person watching a few devices.
- **Capturing raw `print` output.** BrightScript offers no way to intercept it. Logs must pass through the facade or an adapter.
- **Fetching its own configuration.** The host app decides who is enabled and passes the result in.
- **Being on by default in public builds.**
