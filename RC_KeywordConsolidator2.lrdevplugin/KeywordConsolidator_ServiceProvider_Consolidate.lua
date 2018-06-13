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

-- My Modules
assert( RcModuleLoader, "no module loader in svcc provider" ) 
assert( RcUtils, "no rc-utils in svcc provider" ) 

local KwC = RcModuleLoader.loadModule( 'KeywordConsolidator_ServiceProvider' )
KwC.consolidate()
