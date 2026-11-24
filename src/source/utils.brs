function RemoteLogger_isAssocArray(value as dynamic) as boolean
    return type(value) = "roAssociativeArray"
end function

function RemoteLogger_isStringNotEmpty(value as dynamic) as boolean
    return RemoteLogger_isString(value) and len(value) > 0
end function

' type() gives "String" or "roString" and string compare is case-sensitive, so ask for the interface.
function RemoteLogger_isString(value as dynamic) as boolean
    return GetInterface(value, "ifString") <> invalid
end function
