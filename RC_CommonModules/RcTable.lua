--[[----------------------------------------------------------------------------

Filename:			RcTable.lua

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
local RcTable = {}


-- Evaluate pre-requisites:
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Lightroom dependencies:
local LrStringUtils = RcModuleLoader.import( 'LrStringUtils' ) -- include lr-string-utils emulation in non-lightroom environment.
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' ) -- include lr-string-utils emulation in non-lightroom environment.


-- Rc dependencies:
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )



function RcTable.serializeArrayAsLine( tbl )
    local buf = {}
    for i,v in ipairs( tbl ) do
        buf[#buf + 1] = tostring( v )
    end
    return "{ " .. table.concat( buf, ", " ) .. " }" -- one line string table representation
end
    


--[[
        Synopsis:           Return iterator that feeds k,v pairs back to the calling context sorted according to the specified sort function.
        
        Notes:              sort-func may be nil, in which case default sort order is employed.
        
        Returns:            iterator function
--]]
function RcTable.sortedPairs( t, sortFunc )
    local a = {}
    for k in pairs( t ) do
        a[#a + 1] = k
    end
    table.sort( a, sortFunc )
    local i = 0
    return function()
        i = i + 1
        return a[i], t[a[i]]
    end
end



--[[
        Synopsis:           Determine if table has any elements.
        
        Note:               - Determine if specified variable includes at least one item in the table,
                              either at a numeric index or as key/value pair.
        
        Returns             t/f
--]]
function RcTable.isEmpty( t )
    if t == nil then return true end
    if #t > 0 then return false end
    for _,__ in pairs( t ) do
        return false
    end
    return true
end



--[[
        Synopsis:           Count non-nil items in table.
        
        Note:               - #table-name gives highest assigned item - won't span nil'd items, therefore:
                              this function is for when some have been nil'd out.
--]]
function RcTable.countItems( t )
    local count = 0
    for k,v in pairs( t ) do
        if v ~= nil then
            count = count + 1
        end
    end
    return count
end



--[[
        Synopsis:           Appends one array to another.
        
        Notes:              - should have been called appendArray.
        
        Returns:            X - the first array is added to directly.
--]]        
function RcTable.append( t1, t2 )
    for i = 1, #t2 do
        t1[#t1 + 1] = t2[i]
    end
end



--[[
        Synopsis:           Searches for an item in an array.
        
        Notes:              should have been named with "array".
        
        Returns:            t/r
--]]        
function RcTable.isFound( t1, item )

    for i = 1, #t1 do
        if t1[i] == item then
            return true
        end
    end
    return false

end



--[[
        Synopsis:           Like "append", except creates a new array.
        
        Notes:              Does not check for item duplication.
        
        Returns:            new array = combination of two passed arrays.
--]]        
function RcTable.combineArrays( t1, t2 )
    local t = {}
    if t1 ~= nil then
        for k,v1 in ipairs( t1 ) do
            t[#t + 1] = v1
        end
    end
    if t2 ~= nil then
        for i,v2 in ipairs( t2 ) do
            t[#t + 1] = v2
        end
    end
    return t
end




--[[
        Synopsis:           Like "combine", except DOES check for item duplication.
        
        Notes:              - good for coming up with a new array that includes all items from the passed arrays.
        
        Returns:            new array.
--]]        
function RcTable.merge( t1, t2 )
    local t = {}
    for k,v1 in ipairs( t1 ) do
        t[#t + 1] = v1
    end
    for i,v2 in ipairs( t2 ) do
        if not RcTable.isFound( t1, v2 ) then
            t[#t + 1] = v2
        end
    end
    return t
end



--- Reverse an array in place.
--
function RcTable.reverseInPlace( t )
    if t == nil or #t == 1 then
        return
    end
    local function swap( j, k )
        local temp = t[j]
        t[j] = t[k]
        t[k] = temp
    end
    for i = 1, math.floor( #t / 2 ) do
        swap( i, #t - i + 1 )
    end
end





return RcTable