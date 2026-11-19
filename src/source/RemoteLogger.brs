' Builds a facade for one component. It feeds the node at m.global.remoteLogger
' (field "level" read once here, field "entry" written once per entry).
' Without that node the facade is disabled and every method does nothing.
function RemoteLogger(tag as string) as object
    facade = {
        tag: tag,
        node: invalid,
        error: RemoteLogger_facadeError,
        warn: RemoteLogger_facadeWarn,
        info: RemoteLogger_facadeInfo,
        debug: RemoteLogger_facadeDebug,
        trace: RemoteLogger_facadeTrace,
        write: RemoteLogger_facadeWrite
    }
    if m.global = invalid then return facade
    sink = m.global.remoteLogger
    if type(sink) <> "roSGNode" then return facade

    facade.node = sink
    facade.levels = RemoteLogger_levels()
    facade.names = RemoteLogger_levelNames()
    facade.minLevel = RemoteLogger_levelValue(sink.level, facade.levels)
    facade.seq = 0 ' per facade; the Task re-sequences per session later
    facade.clock = CreateObject("roDateTime")
    return facade
end function

' Starts the logger Task and stores it on m.global as "remoteLogger". Render thread only.
' Does nothing when disabled or already started. Returns true when it started the Task.
function RemoteLogger_init(config as dynamic) as boolean
    config = RemoteLogger_normalizeConfig(config)
    if not config.enabled then return false
    if m.global.hasField("remoteLogger") then return false

    task = CreateObject("roSGNode", "RemoteLoggerTask")
    task.config = config
    task.level = config.level
    m.global.addFields({ remoteLogger: task })
    task.control = "run"
    return true
end function

' Returns every configuration key with a valid value; a missing or wrongly typed value gets its default.
function RemoteLogger_normalizeConfig(config as dynamic) as object
    if not RemoteLogger_isAssocArray(config) then config = {}
    normalized = {
        enabled: false,
        endpoint: "",
        level: RemoteLogger_levelNames()[RemoteLogger_levelValue(config.level)],
        batchSize: RemoteLogger_positiveInt(config.batchSize, 20),
        flushIntervalMs: RemoteLogger_positiveInt(config.flushIntervalMs, 2000),
        maxQueue: RemoteLogger_positiveInt(config.maxQueue, 500),
        headers: {},
        sessionTags: {}
    }
    if RemoteLogger_isStringNotEmpty(config.endpoint)
        normalized.endpoint = config.endpoint
        normalized.enabled = GetInterface(config.enabled, "ifBoolean") <> invalid and config.enabled
    end if
    if RemoteLogger_isAssocArray(config.headers) then normalized.headers = config.headers
    if RemoteLogger_isAssocArray(config.sessionTags) then normalized.sessionTags = config.sessionTags
    return normalized
end function

' Zero or less would break the ring buffer and the wait loop, so it counts as wrong too.
function RemoteLogger_positiveInt(value as dynamic, fallback as integer) as integer
    if GetInterface(value, "ifInt") <> invalid and value > 0 then return value
    return fallback
end function

' AA keys ignore case, so a lookup needs no LCase.
function RemoteLogger_levels() as object
    return { error: 1, warn: 2, info: 3, debug: 4, trace: 5 }
end function

' Index = level value.
function RemoteLogger_levelNames() as object
    return ["", "error", "warn", "info", "debug", "trace"]
end function

' Unknown or non-string names count as info, so a mapping mistake still arrives.
function RemoteLogger_levelValue(name as dynamic, levels = invalid as dynamic) as integer
    if not RemoteLogger_isString(name) then return 3
    if levels = invalid then levels = RemoteLogger_levels()
    value = levels[name]
    if value = invalid then return 3
    return value
end function

function RemoteLogger_toStr(value as dynamic) as string
    if RemoteLogger_isString(value) then return value
    if value = invalid then return "invalid"
    if GetInterface(value, "ifToStr") <> invalid then return value.toStr()
    return "<" + type(value) + ">"
end function

sub RemoteLogger_facadeWrite(level as dynamic, tag as dynamic, message as dynamic, data as dynamic)
    if m.node = invalid then return
    value = RemoteLogger_levelValue(level, m.levels)
    if value > m.minLevel then return

    m.seq = m.seq + 1
    m.clock.mark()
    m.node.entry = {
        seq: m.seq,
        t: m.clock.asSeconds() * 1000& + m.clock.getMilliseconds(),
        lvl: m.names[value],
        tag: RemoteLogger_toStr(tag),
        msg: RemoteLogger_toStr(message),
        data: data
    }
end sub

sub RemoteLogger_facadeError(message as dynamic, data = invalid as dynamic)
    m.write("error", m.tag, message, data)
end sub

sub RemoteLogger_facadeWarn(message as dynamic, data = invalid as dynamic)
    m.write("warn", m.tag, message, data)
end sub

sub RemoteLogger_facadeInfo(message as dynamic, data = invalid as dynamic)
    m.write("info", m.tag, message, data)
end sub

sub RemoteLogger_facadeDebug(message as dynamic, data = invalid as dynamic)
    m.write("debug", m.tag, message, data)
end sub

sub RemoteLogger_facadeTrace(message as dynamic, data = invalid as dynamic)
    m.write("trace", m.tag, message, data)
end sub
