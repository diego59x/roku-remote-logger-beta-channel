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
    facade.names = ["", "error", "warn", "info", "debug", "trace"] ' index = level value
    facade.minLevel = RemoteLogger_levelValue(sink.level, facade.levels)
    facade.seq = 0 ' per facade; the Task re-sequences per session later
    facade.clock = CreateObject("roDateTime")
    return facade
end function

' AA keys ignore case, so a lookup needs no LCase.
function RemoteLogger_levels() as object
    return { error: 1, warn: 2, info: 3, debug: 4, trace: 5 }
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
