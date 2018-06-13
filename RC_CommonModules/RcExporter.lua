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
-------------------------------------------------------------------------------------

Edit History:       2010-06-25: Enhanced by Rob Cole...

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


-- Define this module.
Exporter = {}


-- Lightroom Modules
local LrApplication = import 'LrApplication'
local LrPathUtils = import 'LrPathUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrLogger = import 'LrLogger'
local LrErrors = import 'LrErrors'
local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'
local LrStringUtils = import 'LrStringUtils'


-- My Modules
if _G.RcModuleLoader == nil then
    RcModuleLoader = dofile( LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), "RC_CommonModules/RcModuleLoader.lua" ) )
    RcModuleLoader.init() -- loads rc-utils.
end
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )



--[[
        Synopsis:           Create a new exporter - out of thin air, or another object (e.g. exporter).
--]]        
function Exporter:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end    



--[[
        Synopsis:           Initialize the exporter, to make ready for processing rendered photos.
        
        Notes:              Theoretically this could be done in the constructor (new) function, but for some reason I like keeping them separate.
--]]        
function Exporter:init( functionContext, exportContext )
    self.functionContext = functionContext
    self.exportContext = exportContext
    -- self.stats = {}
    self.env = RcEnv:new() -- includes error and warning stats to be added onto.
end
