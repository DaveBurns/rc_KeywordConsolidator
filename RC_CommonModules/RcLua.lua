--[[================================================================================

Filename:           RcLua.lua

Synopsis:           Common utils to supplement lua.

Dependencies:       - Lua 5.1 (not Lightroom)

Notes:              - Its my intention to keep this module non-Lightroom.
                    - See RcUtils for utilities that depend on lightroom modules.

------------------------------------------------------------------------------------
Origin:             Please do not delete these origin lines, unless this file has been
                    edited to the point where nothing original remains... - thanks, Rob.

    		        The contents of this file is based on code originally written by
                    Rob Cole, robcole.com, 2008-09-02.

                    Rob Cole is a software developer available for hire.
                    For details please visit www.robcole.com
------------------------------------------------------------------------------------
For Hire:       I am. - Please contact me at http://www.robcole.com.
For Hire:       I am. - Please contact me at http://www.robcole.com.
For Hire:       I am. - Please contact me at http://www.robcole.com.
-------------------------------------------------------------------------------------

Edit History:       2009-02-13: Enhanced by Rob Cole...

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


local RcLua = {}




--------------------
-- Public functions:
--------------------



--[[
        ###5 - Deprecated, since lightroom versus non should be transparent to application,
        and handled in emulation modules that are loaded via rc-module-loader.
--]]
function RcLua.isLightroom()
    return _PLUGIN ~= nil
end



--[[
        *** Deprecated: Use to-string instead, or handle explicitly.

        Returns the value as is if not nil, else the string 'nil'.
        For when you have a value which, if nil causes problems.
        Less useful since to-string invented. Useful when you
        know the value will either be a non-nil value of a known type, or nil.
--]]
function RcLua.value( v )
    return v or 'nil'
end



--[[
        Synopsis:       Determine if the specified boolean is true.
        
        Notes:          - Returns the value as is if not nil, else the boolean 'false'.
                        - Avoids problem of illegal comparison with nil.
                        - useful when testing not-true.
                        
        Examples:       while( not RcLua.isTrue( v ) ) do ... end
                            -- while( not v ) throws an error when v is nil.
--]]
function RcLua.isTrue( v )
    return v or false
end



--[[
        Synopsis:       Convert any variable for string use, even a nil one.

        Notes:          For when you have a value or not, and need to use it as a string,
                        usually for display or comparison purposes.
--]]
function RcLua.toString( v )
    if v ~= nil then
        return tostring( v )
    else
        return 'nil'
    end
end



--[[
        Synopsis:       Return iterator that produces ordered table values.

        Motivation:     Lua pairs function returns values in pseudo random order.
--]]
function pairsByKeys( t, sortFunc )
    local keys = {}
    for key in pairs( t ) do
        keys[#keys + 1] = key
    end
    table.sort( keys, sortFunc ) -- alphabetical by default.
    local i = 0
    return function()
        i = i + 1
        return key[i], t[key[i]] -- I assume this mess ends on the first nil key??? - not tested @2009-08-14
    end
end



return RcLua