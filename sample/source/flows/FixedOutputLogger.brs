' A stand-in for a host app's logger with one fixed output and numeric levels
' (0 silent, 1 error, 2 warn, 3 info, 4 verbose). Like many such loggers, it passes a
' marker string as params when a call has none. It knows nothing about the remote logger.
function FixedOutputLogger(context as string) as object
    logger = {
        noParams: "_noparams_",
        level: 4,
        context: context,
        output: invalid,
        setOutput: FixedOutputLogger_setOutput,
        log: FixedOutputLogger_log,
        error: FixedOutputLogger_error,
        warn: FixedOutputLogger_warn,
        info: FixedOutputLogger_info,
        verbose: FixedOutputLogger_verbose
    }
    logger.setOutput(ConsoleLogOutput())
    return logger
end function

sub FixedOutputLogger_setOutput(output as object)
    m.output = output
    m.output.init(m.level, m.noParams)
    m.output.setContext(m.context)
end sub

sub FixedOutputLogger_log(level as integer, message as string, params as dynamic)
    if level > m.level then return
    m.output.handleLog(message, level, m.context, params)
end sub

sub FixedOutputLogger_error(message as string, params = "_noparams_" as dynamic)
    m.log(1, message, params)
end sub

sub FixedOutputLogger_warn(message as string, params = "_noparams_" as dynamic)
    m.log(2, message, params)
end sub

sub FixedOutputLogger_info(message as string, params = "_noparams_" as dynamic)
    m.log(3, message, params)
end sub

sub FixedOutputLogger_verbose(message as string, params = "_noparams_" as dynamic)
    m.log(4, message, params)
end sub

' The host's existing output: prints to the console.
function ConsoleLogOutput() as object
    return {
        names: ["", "ERROR", "WARN", "INFO", "VERBOSE"],
        noParams: invalid,
        context: "",
        init: ConsoleLogOutput_init,
        setContext: ConsoleLogOutput_setContext,
        handleLog: ConsoleLogOutput_handleLog
    }
end function

sub ConsoleLogOutput_init(_level as integer, noParams as dynamic)
    m.noParams = noParams
end sub

sub ConsoleLogOutput_setContext(context as string)
    m.context = context
end sub

sub ConsoleLogOutput_handleLog(message as string, level as integer, context as string, params as dynamic)
    line = m.names[level] + " " + context + ": " + message
    if not (GetInterface(params, "ifString") <> invalid and params = m.noParams) then line = line + " " + FormatJson(params)
    print line
end sub
