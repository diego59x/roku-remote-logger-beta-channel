' Flow D adapter: wraps the host's output. It prints as before, then sends the entry.
' It copies the output's method names and signatures, because the host calls them without checking.
' Create it after RemoteLogger_init, because the facade looks for the logger Task once, when built.
function RemoteLogOutput(inner as object) as object
    return {
        inner: inner,
        remote: RemoteLogger("host"),
        levels: ["", "error", "warn", "info", "debug"], ' index = the host's numeric level
        noParams: invalid,
        init: RemoteLogOutput_init,
        setContext: RemoteLogOutput_setContext,
        handleLog: RemoteLogOutput_handleLog
    }
end function

sub RemoteLogOutput_init(level as integer, noParams as dynamic)
    m.noParams = noParams
    m.inner.init(level, noParams)
end sub

sub RemoteLogOutput_setContext(context as string)
    m.inner.setContext(context)
end sub

sub RemoteLogOutput_handleLog(message as string, level as integer, context as string, params as dynamic)
    m.inner.handleLog(message, level, context, params)
    ' The host's "no params" marker would otherwise arrive as data on every entry.
    if RemoteLogger_isString(params) and params = m.noParams then params = invalid
    m.remote.write(m.levels[level], context, message, params)
end sub
