--[[----------------------------------------------------------------------------

Filename:		CustomMetadata_ServiceProvider.lua

Synopsis:		Export service provider description for RC Photooey - CustomMetadata export plugin.

Reminder:       This is the module that loads the rc-module-loader,
                as well as other modules that are used both by task and dialog sections.
                its job is to return a table of things that lightroom can use to boot-strap
                the plugin functionality, for example:

                    - Which dialog sections to show/hide.
                    - Which export formats to include.
                    - Entry points for export processing.

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



-- Lightroom API - could be loaded by rc-module-loader, but no reason to, since this module will never be employed outside lightroom.
local LrPathUtils = import 'LrPathUtils'
local LrView = import 'LrView'


-- My Modules
-- this should no longer be necessary, since plugin-init module is being specified, but I'm afraid to take it out at this point. ###2
if RcModuleLoader == nil then -- compromise: can't hurt...
    RcModuleLoader = dofile( LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), "RC_CommonModules/RcModuleLoader.lua" ) )
        -- rc-module-loader loaded explicitly, all other modules assume global loader available, thus package-loaded need not be set.
    RcModuleLoader.init() -- init's RcUtils too.
end



--============================================================================--

--[[
        Synopsis:           Return table of metadata fields.
        
        Notes:              - id:           unique identifier for internal reference.
                            - title:        what's shown in the UI.
                            - version:      primarily used for updating schema.
                            - data-type:    nil, string, enum, or url. If absent, field behaves like a string - I wish there was a 'number' type so that ranges could be defined.
--]]
return {

    metadataFieldsForPhotos = {

        { id='lastUpdateTime', version=1 }
        
    },
    
    schemaVersion = 1,
    
    -- updateFromEarlierSchemaVersion = function( catalog, previousSchemaVersion ) ... end
    
}
