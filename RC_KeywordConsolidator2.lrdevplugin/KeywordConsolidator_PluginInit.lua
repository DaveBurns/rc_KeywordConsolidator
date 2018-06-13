--[[================================================================================

Filename:           RC_KwC_ServiceProvider.lua

Synopsis:           Implements KwC - File Menu Plug-in Extra.

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

Edit History:       2010-07-03: Created by Rob Cole...
      
------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]



-- Lightroom Modules
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'


-- My Modules
RcModuleLoader = dofile( LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), "RC_CommonModules/RcModuleLoader.lua" ) )
RcModuleLoader.init()

local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )

-- consider using init-user-config instead ###2
_G.config, _G.initMsg = RcUtils.loadSupportTable( _PLUGIN.id .. ".Config.lua" ) -- can be with plugin, plugin-parent, catalog, or in one of the standard dirs.
if _G.config then -- init msg is path.
    _G.initMsg = "Configuration loaded from " .. RcLua.toString( _G.initMsg )
else -- init-msg is generic error message.
    _G.initMsg = "Unable to load configuration, error message: " .. RcLua.toString( _G.initMsg )
end

local KwC = RcModuleLoader.loadModule( 'KeywordConsolidator_ServiceProvider' )

local prefs = LrPrefs.prefsForPlugin()

if prefs.enableAutoInit then
    KwC.initStart()
end
