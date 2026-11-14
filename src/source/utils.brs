function TypeGuard_isAssocArray(value as dynamic) as boolean
    return type(value) = "roAssociativeArray"
end function

function TypeGuard_isStringNotEmpty(value as dynamic) as boolean
    return type(value) = "string" and len(value) > 0
end function

function TypeGuard_isString(value as dynamic) as boolean
    return type(value) = "string"
end function
