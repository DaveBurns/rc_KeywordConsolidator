--[[----------------------------------------------------------------------------

Filename: 		RcModuleLoader.lua

Synopsis:       Loads lua modules using import, require, or dofile, depending on the circumstances.

                - import: Lightroom modules in lightroom environment.
                - require: Lightroom emulations in non-lightroom environment.
                - dofile: 1st-party & 3rd party modules.

                Tracks loaded modules by complete path, instead of just module name, thus bypassing Lightroom's
                module handling anomalies, and adding the option to force a reload, which is valuable to keep
                from having to require the user to re-load plugins.

Requirements:   - Lua 5.1
                - Lightroom 2, 3, or emulation of modules imported in code below.

History:        Lightroom does not support common modules. What's worse, it does not keep modules of same
                name in separate namespaces for each plugin. Thus, its possible to have one plugin use
                a different version of the same module from another plugin. Lightroom does however support
                do-file, which can be used for a home-brewed module loader.

Notes:          Many rc-modules depend on this module being available globally.
                Thus, in plugin entry-point code - i.e. service-provider module, have this:

Instructions:   local LrPathUtils = import 'LrPathUtils'
                if RcModuleLoader == nil then
                    RcModuleLoader = dofile( LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), "/RC_CommonModules/RcModuleLoader.lua" ) -- dofile is cool with non "standardized" paths.
                    RcModuleLoader.init() -- assure fresh modules will be loaded.
                end

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

Edit History:   2009-07-27: Created by Rob Cole.

--------------------------------------------------------------------------------

To Do:          - See ### & ??? spots.

------------------------------------------------------------------------------]]


local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'



_G.RcModuleLoader = {}



--[[
        Instructions:
            Use this instead of Lightroom's global import function,
            if module may someday be used outside of Lightroom, i.e. stand-alone lua environment.

        Under the hood:
            In Lightroom environment - does same thing as global import function,
            in non-Lightroom environment, does same thing as global require function.

        Purpose:
            To be able to support the same capabilities outside a lightroom
            environment by emulating lightroom functions.
--]]
RcModuleLoader.import = function( moduleName )
    if _PLUGIN ~= nil then -- lightroom environment
        return import( moduleName )
    else -- lua standalone or other non-lightroom environment.
        return require( moduleName )
    end
end



--[[
        At earliest opportunity, i.e. in service-provider module, create a global rc-module-loader using dofile,
        and initialize it, so all subsequently loaded modules will be fresh, like so:

        RcModuleLoader = dofile( LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), "RC_CommonModules/RcModuleLoader.lua" ) )
        RcModuleLoader.init()
--]]
RcModuleLoader.init = function( appName )
    RcModuleLoader.loaded = {}
    _G.RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )
    _G.RcUtils.initUI{ appName = appName } -- legacy/deprecated ###2
    _G.infoLua = dofile( LrPathUtils.child( _PLUGIN.path, "Info.lua" ) )
    -- _G.RcUtils.init() -- preferred
end



--[[
        Instructions:
            Internal general purpose module loader, not public.

        Notes:
            force-reload - shouldn't be necessary as long as init is called by the global instance of rc-module-loader.
--]]
RcModuleLoader._loadModule = function( folderPath, moduleName, forceReload )

    local fileName = moduleName .. ".lua"
    local filePath = LrPathUtils.child( folderPath, fileName )

    if RcModuleLoader.loaded == nil then -- this instance of rc-module-loader has not been initialized.
        -- it should have been, and if it hasn't, I want to know.
        error( "Program Failure: rc-module-loader must be initialized." )
        -- RcModuleLoader.loaded = {}
    elseif RcModuleLoader.loaded[filePath] and not forceReload then
        return RcModuleLoader.loaded[filePath]
    end

    local filePath = LrPathUtils.child( folderPath, fileName )
    assert( LrFileUtils.exists( filePath ), "Module file does not exist at: " .. filePath )
    local module = dofile( filePath )
    RcModuleLoader.loaded[filePath] = module
    
    return module
end



--[[
        Instructions:
            Call this function to load a common module from a sibling folder named 'RC_CommonModules'.
            These modules typically begin with 'Rc'.

        This function does the same thing as Lightroom/lua's "require", except it uses dofile,
        which has the advantage of allowing a path to be specified, instead of just a module name.

        Module file loaded: "../RC_CommonModules/{module-name}.lua".

        Notes:
            force-reload - shouldn't be necessary as long as init is called by the global instance of rc-module-loader.
--]]
RcModuleLoader.loadRcModule = function( moduleName, forceReload )
    return RcModuleLoader.loadModule( moduleName, "RC_CommonModules", forceReload )
end



--[[
        Instructions:
            Call this function to load a primary module, meaning one that is in the same folder
            as the info, service-provider, dialog-provider, and task modules. Can also load a module
            from a specified sibling folder, or any folder actually.

        This function does the same thing as Lightroom/lua's "require", except it uses dofile,
        which has the advantage of allowing a path to be specified, instead of just a module name.

        Module file loaded if folder-spec nothing: "./{module-name}.lua"
        Module file loaded if folder-spec relative: "../{sibling}/{module-name}.lua"
        Module file loaded if folder-spec absolute: "{folder-spec}/{module-name}.lua"

        Notes:
            folder-spec - absolute path, sibling path, or nothing.
            force-reload - shouldn't be necessary as long as init is called by the global instance of rc-module-loader.
--]]
RcModuleLoader.loadModule = function( moduleName, folderSpec, forceReload )

    local pluginFolder = nil
    if folderSpec then
        if LrPathUtils.isAbsolute( folderSpec ) then
            pluginFolder = folderSpec -- verbatim
        else
            pluginFolder = LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), folderSpec ) -- relative to plugin parent.
        end
    else
        pluginFolder = _PLUGIN.path -- local dir
    end
    return RcModuleLoader._loadModule( pluginFolder, moduleName, forceReload )

end



return RcModuleLoader