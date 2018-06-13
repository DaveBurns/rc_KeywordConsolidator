--[[================================================================================

Filename:           RcXml2.lua

Synopsis:           Supports modular lua programs.

Dependencies:       Lua 5.1

------------------------------------------------------------------------------------
Origin:             Please do not delete these origin lines, unless this file has been
                    edited to the point where nothing original remains... - thanks, Rob.

    		        The contents of this file is based on code originally written by
                    Rob Cole, robcole.com, 2010-10-24.

                    Rob Cole is a software developer available for hire.
                    For details please visit www.robcole.com
------------------------------------------------------------------------------------
For Hire:       I am. - Please contact me at http://www.robcole.com.
For Hire:       I am. - Please contact me at http://www.robcole.com.
For Hire:       I am. - Please contact me at http://www.robcole.com.
------------------------------------------------------------------------------------

Edit History:       2010-10-24: Created by Rob Cole

------------------------------------------------------------------------------------

Notes:				Version 2 of RcXml is written to support round-trip read/modify/write workflow
                    For cases where distinction between namespace and name is not important.
                    i.e. it lumps the namespace specifier in with the element and attribute names.
                    It would be possible to parse the namespace declarations as well but I don't
                    anticipate this being necessary for the initial application, which is to support
                    xmp-based plugins.
                    
                    Hopefully, re-writing a freshly read table will create exactly the same string as original.
                    
Limitations:        This module might not support CDATA.

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


local RcXml2 = {}

assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Lightroom API - could be loaded by rc-module-loader, and should be if ever this module changed to be employed outside lightroom.
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrXml = import 'LrXml' -- this module depends on lr-xml for converting table to xml string, but not for parsing xml string into table.


-- My Modules
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )


local indentLevel = 0
local indentSpaces = 1
local spaces = ''




-- debugging support
local _debugMode = false
local _debugTrace = function( id, info )
    if not _debugMode then return end
    RcUtils.debugTrace( "RcXml2 - " .. id, info, false ) -- use true to include id as message prefix.
end





--[[---------------------------------------------------------------------------------------
        The following is based on code stolen from http://lua-users.org/wiki/LuaXml
-------------------------------------------------------------------------------------------]]


--[[
        Synopsis:           Parse a table of attributes from an attribute string.
        
        Table Format:       array of items whose format is:
        
                                - name
                                - text
                                
--]]
function RcXml2._parseAttrs(s)
  local args = {}
  string.gsub(s, "([%w:]+)=([\"'])(.-)%2", function (w, _, a)
    -- _debugTrace( "pa", w )
    local arg = {}
    arg.name = w
    arg.text = a
    args[#args + 1] = arg
  end)
  return args
end



--[[
        Synopsis:               Parse an xml string into a table of nested element tables.
        
        Table Element Format:   - ns
                                - name
                                - label (=ns:name)
                                - xarg (see fmt above) - presently array of "name,text" table entries.
                                - empty = 1, or text.
--]]                               
function RcXml2.tabularize(s)
  local stack = {}
  local top = {}
  table.insert(stack, top)
  local ni,c,label,xarg, empty
  local i, j = 1, 1
  while true do
    ni,j,c,label,xarg, empty = string.find(s, "<(%/?)([%w:%-_]+)(.-)(%/?)>", i)
    if not ni then break end
    local text = string.sub(s, i, ni-1)
    if not string.find(text, "^%s*$") then
      -- _debugTrace( "xml inserting text ", text )
      table.insert(top, text)
    end
    if empty == "/" then  -- empty element tag
      -- _debugTrace( "xml inserting empty" )
      local a = RcString.split( label, ':' )
      local ns, nm
      if #a == 2 then
        ns = a[1]
        nm = a[2]
      else
        ns=''
        nm=''
      end   
      table.insert(top, {ns=ns, name=nm, label=label, xarg=RcXml2._parseAttrs(xarg), empty=1})
    elseif c == "" then   -- start tag
      local a = RcString.split( label, ':' )
      local ns, nm
      if #a == 2 then
        ns = a[1]
        nm = a[2]
      else
        ns=''
        nm=''
      end   
      top = {ns=ns,name=nm,label=label, xarg=RcXml2._parseAttrs(xarg)}
      -- _debugTrace( "xml inserting ", top.label )
      table.insert(stack, top)   -- new level
    else  -- end tag
      local toclose = table.remove(stack)  -- remove top
      top = stack[#stack]
      if #stack < 1 then
        error("nothing to close with "..label)
      end
      if toclose.label ~= label then
        error("trying to close "..toclose.label.." with "..label)
      end
      table.insert(top, toclose)
    end
    i = j+1
  end
  local text = string.sub(s, i)
  if not string.find(text, "^%s*$") then
    table.insert(stack[#stack], text)
  end
  if #stack > 1 then
    error("unclosed "..stack[stack.n].label)
  end
  return stack[1]
end




--[[
		Synopsis:			load xml string into rc-xml table.

		Returns:			tree-structured table with one entry per corresponding xml node.

		Table Entry Format: - type, name, attrs, text.

		Notes:				returned table can be modified, then re-written.
--]]
function RcXml2.parseXml( xmlString )
	local xmlTable = RcXml2.tabularize( xmlString )
	return xmlTable
end



--[[
        Synopsis:               Convert array of attributes to xml string.
        
        Array Item Format:      xarg.name -- attribute ns:name.
                                xarg.text -- attribute value string.
                                
        Note:                   If spaces are being used for indenting, then arguments are put one per line (indented) - just like in an XMP file.
--]]
function RcXml2.serializeAttributes( xarg )
    local args = ''
    for i,v in ipairs( xarg ) do
        args = args .. ' ' .. v.name .. '="' .. v.text .. '"'
        if RcString.is(spaces) and (i ~= #xarg) then
            args = args .. '\n' .. spaces .. ' '
        end
    end
    return args
end



--[[
		Synopsis:           converts xml table to string, typically for writing to a file upon return.
		
		Notes:              - multi-line format, like xmp files.
		                    - '_' prefixed version recurses itself.
--]]
function RcXml2._serialize( xmlTable, omitDecl, dflt, excpts )
    local s = ''
    local name = nil
    -- top level elem
    spaces = ''
    if indentLevel > 0 then
        spaces = RcString.makeSpace( ( indentLevel - 1 ) * indentSpaces )
    end
    if type( xmlTable ) == 'table' then
        if xmlTable.label then
            s = s .. spaces .. "<" .. xmlTable.label
            name = xmlTable.label
        end
        if xmlTable.xarg then
            s = s .. RcXml2.serializeAttributes( xmlTable.xarg )
        end
        if xmlTable.empty then
            s = s .. "/>\n"
            return s
        elseif RcString.is( s ) then
            s = s .. ">"
            if type( xmlTable[1] ) ~= 'string' then
                s = s .. '\n'
            end
        end
    elseif type( xmlTable ) == 'string' then
        s = s .. xmlTable
    end
    if type( xmlTable ) == 'table' then
        indentLevel = indentLevel + 1
        for i,v in ipairs( xmlTable ) do
            s = s .. RcXml2._serialize( v )
        end
        indentLevel = indentLevel - 1
    end
    if indentLevel < 0 then
        error( "ill-formed document, else bug in parser or serializer" ) -- call in protected mode to trap this error.
    end
    if name then
        if type( xmlTable[1] ) ~= 'string' then
            s = s .. spaces:sub( 1, indentLevel - 1 )
        end
        s = s .. '</' .. name .. '>\n'
    end
    return s
end



--[[
		Synopsis:           converts xml table to string, typically for writing to a file upon return.
		
		Notes:              - multi-line format, like xmp files.
		                    - '_' prefixed version recurses itself.
--]]
function RcXml2.serialize( xmlTable, omitDecl, dflt, excpts )
    indentLevel = 0
    return RcXml2._serialize( xmlTable, omitDecl, dflt, excpts )
end
    


return RcXml2
