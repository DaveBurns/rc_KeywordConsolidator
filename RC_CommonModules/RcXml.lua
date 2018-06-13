--[[================================================================================

Filename:           .lua

Synopsis:           Supports modular lua programs.

Dependencies:       Lua 5.1 (not Lightroom)

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
                    2020-03-05: gutted in favor of RcXml2. This module may live again if adobe does not
                        support developer settings, since more robust xml support will be needed for some
                        of my other xmp-based plugin ideas.

------------------------------------------------------------------------------------

Notes:				- This module almost nearly but not quite hardly supports xml files with ambiguous namespaces, like xmp file,
                      due to a bug in the lightroom sdk whereby the name() method returns nil instead of the proper namespace of element nodes.
                    - That said, it can only be used in a limited fashion by supplying a default namespace and namespace overrides.
					  In this fashion it can be used for documents without namespace ambiguity, or for documents/document-segments
                      where a non-default namespace may be looked up based on element name alone. all non-default namespace/elements
                      must be specified and the correct namespace for an element must not depend on context/nesting.

Original Application: for read/write of camera-raw settings for relative adjustment purposes.

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.
					- Write my own parser that ignores namespaces - i.e. treats them like just part of the
					  element or attribute name. As long as its understood that it doesn't support namespaces
					  nor CDATA, nor other problem items, it would be very easy to write.

================================================================================--]]


local RcXml = {}

assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Lightroom API - could be loaded by rc-module-loader, and should be if ever this module changed to be employed outside lightroom.
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrXml = import 'LrXml'


-- My Modules
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )





-- debugging support:
local _moduleName = "RcXml"
local function _debugTrace( id, info )
    assert( RcString.is (_moduleName), "Module name must be defined." )
    RcUtils.debugTrace( _moduleName .. ":" .. id, info )
end






return RcXml

