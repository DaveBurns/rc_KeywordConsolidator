--[[----------------------------------------------------------------------------

Filename:       RcDebug.lua

Synopsis:       Provides lua script debugging support.

Dependencies:   Lua 5.1, not Lightroom.

Limitations:    - Oriented toward dialog-box/log-file based debugging,
                  not oriented to working with 3rd party debugging platforms.

------------------------------------------------------------------------------------
Origin:         Please do not delete these origin lines, unless this file has been
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

Edit History:   2009-02-13: Enhanced by Rob Cole...

--------------------------------------------------------------------------------

To Do:          - See ### & ??? spots.

------------------------------------------------------------------------------]]
--[[================================================================================

Filename:           RcDateTimeUtils.lua

Synopsis:           Provides additional date-time support in the form of utility functions.

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
-------------------------------------------------------------------------------------

Edit History:       2009-02-13: Enhanced by Rob Cole...

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


-- define this module
local RcDebug = {}


--------------------
-- load dependencies
--------------------
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )

-- no lightroom dependencies

-- rc-dependencies:
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )


-- debugging support has migrated to rc-utils.

return RcDebug
