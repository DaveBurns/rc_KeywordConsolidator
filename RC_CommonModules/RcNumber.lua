--[[----------------------------------------------------------------------------

Filename:			RcNumber.lua

Synopsis:			String utils to supplement lua and/or lightroom SDK.

Limitations:        - None I can think of.

Dependencies:       - Lua 5.1
                    - Lightroom 2, or emulation of modules imported in code below.

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
------------------------------------------------------------------------------------

Edit History:       2009-02-13: Enhanced by Rob Cole...

--------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

------------------------------------------------------------------------------]]


-- Define this module:
local RcNumber = {}


-- Evaluate pre-requisites:
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Lightroom dependencies:
local LrStringUtils = RcModuleLoader.import( 'LrStringUtils' ) -- include lr-string-utils emulation in non-lightroom environment.
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' ) -- include lr-string-utils emulation in non-lightroom environment.


-- Rc dependencies:
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )



--[[
        Call to check whether a value assumed to be number or not at all is not zero.
--]]
function RcNumber.isNonZero( s )
    if (s ~= nil) and (s ~= 0) then
        return true
    else
        return false
    end
end



--[[
        Try to convert a string to a number, without croaking if the string is nil, null, or isn't a number...
--]]
function RcNumber.numberFromString( s )
    if s == nil or s == '' then
        return nil
    end
    local sts, num = pcall( tonumber, s )
    if sts and num then
        return num
    else
        return nil
    end
end




return RcNumber