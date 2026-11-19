' Batching and transport for RemoteLoggerTask, protocol v1 (docs/PROTOCOL.md).
' Plain functions over locals, so the Task loop stays short and the pure parts are testable.

' The session object sent with every batch. Never holds a serial number or an advertising id.
function RemoteLogger_sessionEnvelope(config as object) as object
    app = CreateObject("roAppInfo")
    device = CreateObject("roDeviceInfo")
    os = device.getOSVersion()
    clock = CreateObject("roDateTime")
    tags = config.sessionTags
    ' A tag that cannot be serialised would break every body, so drop the tags instead.
    if FormatJson(tags) = "" then tags = {}
    return {
        id: device.getRandomUUID().replace("-", ""),
        startedAt: clock.asSeconds() * 1000& + clock.getMilliseconds(),
        app: { id: app.getID(), version: app.getVersion(), build: app.getValue("build_version") },
        device: { model: device.getModel(), os: os.major + "." + os.minor + "." + os.revision, locale: device.getCurrentLocale() },
        tags: tags
    }
end function

' The request body as a JSON string. Entries are serialised one by one so a bad entry
' cannot fail the whole batch.
function RemoteLogger_buildBody(session as object, entries as object, dropped as integer) as string
    parts = []
    for each entry in entries
        parts.push(RemoteLogger_entryJson(entry))
    end for
    head = FormatJson({ v: 1, session: session, dropped: dropped })
    return Left(head, Len(head) - 1) + ",""entries"":[" + parts.join(",") + "]}"
end function

' A long message is cut; values FormatJson cannot serialise (for example a node) are
' replaced first, because FormatJson prints a console error on them. If it still fails,
' the data is removed. Each sets truncated: true.
function RemoteLogger_entryJson(entry as object) as string
    out = { seq: entry.seq, t: entry.t, lvl: entry.lvl, tag: entry.tag, msg: entry.msg }
    if Len(out.msg) > 4000
        out.msg = Left(out.msg, 4000)
        out.truncated = true
    end if
    if entry.data <> invalid
        state = { truncated: false, scalars: RemoteLogger_jsonScalarTypes() }
        out.data = RemoteLogger_safeData(entry.data, 1, state)
        if state.truncated then out.truncated = true
        json = FormatJson(out)
        if json <> "" then return json
        out.delete("data")
        out.truncated = true
    end if
    return FormatJson(out)
end function

' A copy of value that FormatJson accepts; value itself is not changed. An unsupported
' value becomes "<type>" ("<roSGNode:subtype>" for a node) and an AA or array nested
' deeper than 8 becomes "<depth>"; either sets state.truncated.
function RemoteLogger_safeData(value as dynamic, depth as integer, state as object) as dynamic
    kind = type(value)
    if kind = "roAssociativeArray" or kind = "roArray"
        if depth > 8
            state.truncated = true
            return "<depth>"
        end if
        if kind = "roArray"
            copy = []
            for each item in value
                copy.push(RemoteLogger_safeData(item, depth + 1, state))
            end for
        else
            copy = {}
            for each key in value
                copy[key] = RemoteLogger_safeData(value[key], depth + 1, state)
            end for
        end if
        return copy
    end if
    if state.scalars.doesExist(kind) then return value
    state.truncated = true
    if kind = "roSGNode" then return "<roSGNode:" + value.subtype() + ">"
    return "<" + kind + ">"
end function

' type() names of the scalars FormatJson serialises, intrinsic and boxed.
function RemoteLogger_jsonScalarTypes() as object
    return {
        String: true, roString: true,
        Integer: true, roInteger: true,
        LongInteger: true, roLongInteger: true,
        Float: true, roFloat: true,
        Double: true, roDouble: true,
        Boolean: true, roBoolean: true,
        Invalid: true, roInvalid: true
    }
end function

' The facade numbers entries per component; this gives them the session-wide seq.
' Returns the next value.
function RemoteLogger_resequence(entries as object, nextSeq as integer) as integer
    for each entry in entries
        entry.seq = nextSeq
        nextSeq = nextSeq + 1
    end for
    return nextSeq
end function

' "ok" (2xx), "drop" (4xx) or "retry" (anything else: 5xx, negative curl codes, timeouts).
function RemoteLogger_classifyStatus(code as integer) as string
    if code >= 200 and code < 300 then return "ok"
    if code >= 400 and code < 500 then return "drop"
    return "retry"
end function

' 1 s, 2 s, 4 s ... capped at 30 s. retry starts at 1.
function RemoteLogger_backoffMs(retry as integer) as integer
    if retry > 5 then return 30000
    return 1000 << (retry - 1)
end function

' Applies a reply to the batch (code -28 for a timeout). Returns "ok", "drop" or "retry".
' After 3 retries a "retry" becomes "drop". On "retry" the batch waits until batch.due.
function RemoteLogger_batchResult(batch as object, code as integer, now as integer) as string
    batch.xfer = invalid
    status = RemoteLogger_classifyStatus(code)
    if status <> "retry" then return status
    if batch.retries >= 3 then return "drop"
    batch.retries = batch.retries + 1
    batch.due = now + RemoteLogger_backoffMs(batch.retries)
    return "retry"
end function

' Starts the request for a batch; its reply is due within 10 s.
sub RemoteLogger_batchSend(batch as object, config as object, port as object, now as integer)
    batch.xfer = RemoteLogger_post(config, port, batch.body)
    batch.due = now + 10000
end sub

' One roUrlTransfer per request. If the request fails to start no event comes and the
' caller's timeout handles it.
function RemoteLogger_post(config as object, port as object, body as string) as object
    xfer = CreateObject("roUrlTransfer")
    xfer.setMessagePort(port)
    xfer.setUrl(config.endpoint)
    ' No InitClientCertificates: Roku has deprecated it and HTTPS works without it.
    xfer.setCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.addHeader("Content-Type", "application/json; charset=utf-8")
    for each name in config.headers
        value = config.headers[name]
        if GetInterface(value, "ifString") <> invalid then xfer.addHeader(name, value)
    end for
    xfer.asyncPostFromString(body)
    return xfer
end function

' The reply event for xfer, or false for anything else on the port.
function RemoteLogger_isReply(msg as dynamic, xfer as dynamic) as boolean
    if xfer = invalid or type(msg) <> "roUrlEvent" then return false
    return msg.getInt() = 1 and msg.getSourceIdentity() = xfer.getIdentity()
end function

' Sends entries in one request without retries and waits up to 10 s for the reply.
' Returns how many entries the server accepted.
function RemoteLogger_finalFlush(config as object, port as object, session as object, entries as object, dropped as integer) as integer
    if entries.count() = 0 then return 0
    xfer = RemoteLogger_post(config, port, RemoteLogger_buildBody(session, entries, dropped))
    clock = CreateObject("roTimespan")
    remaining = 10000
    while remaining > 0
        msg = wait(remaining, port)
        if RemoteLogger_isReply(msg, xfer)
            if RemoteLogger_classifyStatus(msg.getResponseCode()) = "ok" then return entries.count()
            return 0
        end if
        remaining = 10000 - clock.totalMilliseconds()
    end while
    xfer.asyncCancel()
    return 0
end function
