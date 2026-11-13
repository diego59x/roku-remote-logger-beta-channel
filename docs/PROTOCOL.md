# Protocol

The HTTP contract between the device library and a log server. Version 1 is a *draft* until milestone M1 ships; after that, changes that break a v1 client need a new version path.

The proof of concept in the repository sends one plain-text line per request to `/log`. That format is replaced by this one.

## Request

```
POST /v1/logs
Content-Type: application/json; charset=utf-8
```

Plus any headers from the `headers` option, for example `Authorization`.

One request carries one batch from one session.

```json
{
  "v": 1,
  "session": {
    "id": "9f1c2e7a",
    "startedAt": 1794480000000,
    "app": { "id": "dev", "version": "4.12.0", "build": "381" },
    "device": { "model": "4802X", "os": "15.0.4", "locale": "en_US" },
    "tags": { "tester": "qa-01" }
  },
  "dropped": 0,
  "entries": [
    {
      "seq": 41,
      "t": 1794480012345,
      "lvl": "info",
      "tag": "PlayerScreen",
      "msg": "state changed",
      "data": { "state": "playing" }
    }
  ]
}
```

### Fields

| Field | Type | Required | Meaning |
|---|---|---|---|
| `v` | integer | yes | Protocol version |
| `session.id` | string | yes | Random id, new at each channel launch |
| `session.startedAt` | integer | yes | Launch time, milliseconds since the Unix epoch |
| `session.app` | object | yes | Channel id, version and build from the manifest |
| `session.device` | object | yes | Model, OS version and locale |
| `session.tags` | object | no | Labels supplied by the host app |
| `dropped` | integer | yes | Entries dropped on the device since the last accepted batch |
| `entries[].seq` | integer | yes | Rises by one per entry within a session; gaps mean loss |
| `entries[].t` | integer | yes | Time of the log call, milliseconds since the Unix epoch |
| `entries[].lvl` | string | yes | One of the [levels](#levels) |
| `entries[].tag` | string | yes | Name given to the facade, usually the component |
| `entries[].msg` | string | yes | The message |
| `entries[].data` | object | no | Structured data passed with the call |
| `entries[].truncated` | boolean | no | Present and `true` when the message was cut or the data was removed |

The session object is sent with every batch, so the server keeps no state and a batch can be read alone.

The library never sends a device serial number or an advertising id.

### Levels

From most to least severe: `error`, `warn`, `info`, `debug`, `trace`.

### Limits *(planned defaults)*

| Limit | Value |
|---|---|
| Entries per batch | 20 |
| Message length | 4,000 characters, then truncated |
| Body size | 256 KB; a larger batch is split |

## Response

| Status | Meaning | Device behaviour |
|---|---|---|
| `200` or `204` | Batch accepted | Clear the batch and reset the dropped counter |
| `4xx` | Batch refused | Drop the batch; do not retry |
| `5xx`, timeout or no connection | Server unavailable | Retry with backoff a limited number of times, then drop |

The response body is ignored.

## Ordering and loss

- Entries inside a batch are in call order for a single thread. Across threads, sort by `t` and then `seq`.
- A retried batch may arrive twice. A server removes duplicates by `session.id` and `seq`.
- A gap in `seq` together with a non-zero `dropped` in a later batch means entries were lost on the device.

## Health check

```
GET /
```

Returns `200` with a short text body. It lets a tester confirm from a browser that the server is reachable from the device's network.
