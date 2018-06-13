--[[================================================================================

Filename:           RcUtils.lua

Synopsis:           Defines things common across multiple applications, and lightroom specific.

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

Edit History:       2009-02-13: Created by Rob Cole.

                    2010-02-26:
                        - Re-coded to use lr-logger instead of rc-logger. lr-logger handles function contexts properly
                          and includes timestamps and message types.

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


-- define this module:
local RcUtils = { exportNotManaged = nil }


-- Evaluate pre-requisites:
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Lightroom API
local LrApplication = RcModuleLoader.import( 'LrApplication' )
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )
local LrFileUtils = RcModuleLoader.import( 'LrFileUtils' )
local LrErrors = RcModuleLoader.import( 'LrErrors' )
local LrDialogs = RcModuleLoader.import( 'LrDialogs' )
local LrLogger = RcModuleLoader.import( 'LrLogger' )
local LrDate = RcModuleLoader.import( 'LrDate' )
local LrHttp = RcModuleLoader.import( 'LrHttp' )
local LrTasks = RcModuleLoader.import( 'LrTasks' )
local LrFunctionContext = RcModuleLoader.import( 'LrFunctionContext' )
local LrPrefs = RcModuleLoader.import( 'LrPrefs' )
local LrShell = RcModuleLoader.import( 'LrShell' )

-- My Modules (do not try to load any modules that depend on rc-utils or it causes an infinie loop)
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcTable = RcModuleLoader.loadRcModule( 'RcTable' )
-- local RcLogger = RcModuleLoader.loadRcModule( 'RcLogger' ) - uses lr-logger now.
local RcDateTimeUtils = RcModuleLoader.loadRcModule( 'RcDateTimeUtils' )


-- 3rd Party Modules
-- None.


-- Constants:
RcUtils.VERBOSE = true -- for readability


-- Public variables:
RcUtils.testMode = false -- lots of rc-modules depend on this being initialized here, not export-params - initialize by call to init-export, else explicitly.
-- ###2 Note: this used to be initialized to nil, but was causing occasional errors under unusual circumstances (like new catalog) - Hopefully still set to better value when needed...
RcUtils.debugMode = false -- defaults to log-verbosity in call to init-export - app-wide user debug mode.
RcUtils._debugMode = false -- do not access externally - internal module debug flag.


-- 3rd party debug/logging support
RcUtils.debugger = nil -- for routing debug info to 3rd party debugger, e.g. Microsoft Visual Studio.
RcUtils.logger = nil -- for routing user logs and debug info to local file.


-- File-based logger:
RcUtils.logger = nil
RcUtils.logFilePath = nil
RcUtils._nWarnings = 0
RcUtils._nErrors = 0


-- UI support
RcUtils.appName = "A Lightroom plugin"
RcUtils.inputMsg = "$$$/X=^1 is requesting input..."
RcUtils.isOkMsg = "$$$/X=^1 is asking if its OK..."
RcUtils.infoMsg = "$$$/X=^1 has something to say..."
RcUtils.warningMsg = "$$$/X=^1 is concerned..."
RcUtils.errorMsg = "$$$/X=^1 has encountered a problem..."
RcUtils.infoType = "info"
RcUtils.warningType = "warning"
RcUtils.errorType = "critical" -- @2008-02-13: appears same as warning (SDK version 2.0 or 2.2?) - try again after the next version of SDK is released. Maybe only different on Mac.


RcUtils.startTime = nil
RcUtils.stopTime = nil
RcUtils.exportParams = nil -- log-file-path, log-verbose, log-overwrite, test-mode must be present as export context properties.
RcUtils.logFilePath = nil
RcUtils.logVerbose = nil
RcUtils.suppressInfo = {}
RcUtils.opTitle = nil
RcUtils.abortMessage = nil
RcUtils.canceled = nil -- silent cancellation.


-- _G.infoLua = nil -- for lr2 sake.



-- *** SAVE FOR REMINDER: I HAD FUNCTION-CONTEXT ISSUES TRYING TO HANDLE PROGRESS INDICATOR IN THIS MODULE
-- Progress indication presently relegated to task modules.


function RcUtils.abort( message )
    if RcString.is( message ) then
        RcUtils.abortMessage = message
    else
        RcUtils.abortMessage = "unknown"
    end 
end



function RcUtils.isAborted()
    return RcString.is( abortMessage )
end


function RcUtils.cancel() -- no service dialog box in this case.
    RcUtils.canceled = true
end



--[[
        Synopsis:       Initialize stuff common to all lr-plugin services.

                            - opens log file.
                            - logs standard header
--]]
function RcUtils.initService( _testMode, _logFilePath, _logVerbose, _logOverwrite, _opTitle )
    RcUtils.opTitle = _opTitle
    RcUtils.abortMessage = ''
    RcUtils.canceled = false
    RcUtils.exportNotManaged = nil -- needs to be refigured for each export instantiation.

    -- Assert expectations. Note: although this module could function without these, its the intention
    -- of this module to provide a minimum level of functionality to all RC plugins that use it,
    -- and that includes test mode, logging, and verbosity.
    assert( _testMode ~= nil, "Test mode must be initialized." )
    -- assert( _logFilePath ~= nil, "Log file path must be initialized." )
    assert( _logVerbose ~= nil, "Log verbosity must be initialized." )
    assert( _logOverwrite ~= nil, "Log overwrite must be initialized." )

    RcUtils.testMode = _testMode
    -- RcUtils.logFilePath = _logFilePath - dont do this: path may be altered by logger in case of do-not-overwrite.
    RcUtils.logVerbose = _logVerbose
    RcUtils.logOverwrite = _logOverwrite
    RcUtils.debugMode = _logVerbose -- log verbosity determines debug mode.
    
    RcUtils.startTime = LrDate.currentTime()
    math.randomseed( RcUtils.startTime )
    local dateTimeFormat = '%Y-%m-%d %H:%M:%S'
    local startTimeFormatted = LrDate.timeToUserFormat( RcUtils.startTime, dateTimeFormat )

    if not RcString.is( _logFilePath ) then return end
        
	RcUtils.logOpen( _logFilePath, RcUtils.logVerbose, RcUtils.logOverwrite )
    RcUtils.logMessage( LOC( "$$$/X=^1 started ^2", RcUtils.getAppName(), startTimeFormatted ) )
    if RcUtils.testMode then
        RcUtils.logMessage( " IN TEST MODE\n- TEST MODE: Theoretically no files were actually created, modified, or deleted.\n" )
    else
        RcUtils.logMessage( " IN REAL MODE\n- REAL MODE: Theoretically, files were actually created, modified, or deleted, as indicated.\n" )
    end

    if RcUtils.logVerbose then
        RcUtils.logMessageLine( "Logging verbosely." )
        RcUtils.logMessageLine( "Lightroom Version: " .. LrApplication.versionString() )
        RcUtils.logMessageLine()

        RcUtils.logMessageLine( "Support files may be specified absolutely or relative to these places, tried in this order:" )
        RcUtils.logMessageLine( "Catalog: " .. LrApplication.activeCatalog():getPath() )
        RcUtils.logMessageLine( "Plugin parent: " .. LrPathUtils.parent( _PLUGIN.path ) )
        RcUtils.logMessageLine( "Plugin proper: " .. _PLUGIN.path )
        -- 'home', 'documents', 'appPrefs', 'desktop', 'pictures': must match order in rc-lr-utils.
        RcUtils.logMessageLine( "Home: " ..  LrPathUtils.getStandardFilePath( 'home' ) )
        RcUtils.logMessageLine( "Documents: " ..  LrPathUtils.getStandardFilePath( 'documents' ) )
        RcUtils.logMessageLine( "Application Preferences: " ..  LrPathUtils.getStandardFilePath( 'appPrefs' ) )
        RcUtils.logMessageLine( "Desktop: " ..  LrPathUtils.getStandardFilePath( 'desktop' ) )
        RcUtils.logMessageLine( "Pictures: " ..  LrPathUtils.getStandardFilePath( 'pictures' ) )
            
        -- *** My experience has been the default directory would actually be c:/windows/system32 yet the default directory is
        -- being shown as '/'. Since this is misleading, and only reluctantly supported (will return file relative to
        -- default if found but accompanied by a warning), suppress logging of default dir.
    else
        RcUtils.logMessageLine( "Logging non-verbosely." )
    end

    RcUtils.logMessageLine()
    RcUtils.logMessageLine("Plugin path: " .. _PLUGIN.path .. '\n\n' )
    
end




--[[
        Synopsis:       Initialize common stuff for kick-off phase of an export, namely:

                            - opens log file.
                            - logs standard header

        Parameters:     - function-context - not presently being used. Reserved for future.
                        - export-context - for export-param access...
--]]
function RcUtils.initExport( _functionContext, _exportContext )

	-- Make a local reference to the common export parameters.

	RcUtils.exportParams = _exportContext.propertyTable

    RcUtils.initService( RcUtils.exportParams.testMode, RcUtils.exportParams.logFilePath, RcUtils.exportParams.logVerbose, RcUtils.exportParams.logOverwrite )
    
    if RcUtils.exportParams.logVerbose then
        RcUtils.logMessageLine( "Export Params:")
        RcUtils.logPropertyTable2( RcUtils.exportParams )
        RcUtils.logMessageLine()
    end

    local count = _exportContext.exportSession:countRenditions()
    RcUtils.logMessageLine( "Exporting " .. RcString.plural( count, "selected photo" ) )
    RcUtils.logMessageLine( "Export Format: " .. RcLua.value( RcUtils.exportParams.LR_format ) )
    RcUtils.logMessageLine()

end



--[[
        Synopsis:       Perform common export wrap-up, namely:

                            - log standard footer
                            - close log file
                            - present final dialog
--]]
function RcUtils.endExport( quit, quitMessage, endBoxKey )
    if not RcUtils.startTime then
        return -- this happens sometimes due to a strange bug when multiple exports have been started concurrently. ###2
    end
    
    if quit == nil and quitMessage == nil then -- if quit not passed explicitly (legacy style), use new-style abort message var.
        quit = RcUtils.isAborted()
        quitMessage = RcUtils.abortMessage
    elseif quit and quitMessage == nil then
        quitMessage = "quit for unspecified reason"
    end
    
    RcUtils.stopTime = LrDate.currentTime()
    local elapsedTimeFormatted = RcDateTimeUtils.formatTimeDiff( RcUtils.stopTime - RcUtils.startTime )
    RcUtils.startTime = nil -- closes the service/export so end-service can be called redundently with impunity.

    local dateTimeFormat = '%Y-%m-%d %H:%M:%S'
    local stopTimeFormatted = LrDate.timeToUserFormat( RcUtils.stopTime, dateTimeFormat )

    RcUtils.logMessageLine( '\n\n\n' )
    RcUtils.logMessageLine( LOC( "$$$/X=^1 finished at ^2 (^3 seconds).\n\n\n\n\n", RcUtils.getAppName(), stopTimeFormatted, elapsedTimeFormatted ) )
	RcUtils.logClose()
	
	if RcUtils.canceled then
	    return
	end
	
    -- present final dialog box message:
    local message = nil
    local prefix = ''
    if RcString.is( RcUtils.opTitle ) then
        prefix = RcUtils.opTitle .. ' '
    else
        prefix = RcUtils.getAppName() .. ' '
    end
    if not quit then

        if RcUtils.nErrors() == 0 then
            message = prefix .. ' - all done (no errors).\n'
        else
            message = prefix .. " - done, but " .. RcUtils.nErrors() .. " Errors.\n" 
        end
    else
        -- progress scope has been cancelled.
        if RcUtils.nErrors() == 0 then
            message = prefix .. ' - quit early (but no errors). Reason: ' .. quitMessage .. '\n'
        else
            message = prefix .. " - quit early, and " .. RcUtils.nErrors() .. " Errors.\n"
        end
    end
    if RcUtils.nWarnings() > 0 then
        message = message .. RcUtils.nWarnings() .. " Warnings.\n"
    end

	if RcString.is( RcUtils.logFilePath ) then
		message = message .. LOC( "$$$/X=See log file for details: ^1", RcUtils.logFilePath )
	else
		message = message .. LOC( "$$$/X=No log file was created." )
	end

    -- present final dialog box.
    local actionPrefKey
    local buttons = nil
    if RcUtils.nErrors() == 0 and RcUtils.nWarnings() == 0 and not RcUtils.testMode then
        actionPrefKey = RcUtils.getAppName() .. " - AllDoneFinalDialogViewLog"
        if endBoxKey then
            actionPrefKey = actionPrefKey .. ' - ' .. endBoxKey
        end
        if RcUtils.logFilePath then
            buttons = { { label="Skip Log File", verb='skip' }, { label="View Log File", verb='ok' } }
        end
    else
        actionPrefKey = nil
        if RcUtils.logFilePath then
            buttons = 'View Log File'
        end
    end

    local action = RcUtils.showInfo( message, actionPrefKey, buttons ) -- no longer using error/warning specific dialog boxes for final presentation
        -- in honor of view-log-file upgrade.
    if action=='ok' then -- seems like this used to die if left hand was nil, but it doesn't die now.
        RcUtils.showLogFile()
    else
        -- RcUtils.debugTrace( "rcudafand", "ANser: " .. RcLua.toString( action ) )
    end

end



-- returns true if shown, else false if no log file to show.
function RcUtils.showLogFile()
    if RcString.is( RcUtils.logFilePath ) and LrFileUtils.exists( RcUtils.logFilePath ) then
        local ext = LrPathUtils.extension( RcUtils.logFilePath )
        RcUtils.openFileInDefaultApp( RcUtils.logFilePath ) -- should work correctly on both platforms.
        RcUtils.showInfo( "Log file should be open for viewing in default app for ." .. ext .. " files.", "LogFileShowingPrompt" )
        return true
    else
        return false
    end
end




--[[
        Synopsis:       Perform common export wrap-up, namely:

                            - log standard footer
                            - close log file
                            - present final dialog
--]]
RcUtils.endService = RcUtils.endExport -- presently there's nothing export-specific about it, but one day there might be.





--[[
        Synopsis:       Open conduit to 3rd party external debugger.
        
		Notes:          Call this once at the very beginning.
--]]
function RcUtils.debugOpen() -- works but not used - uncomment if needed.
    RcUtils.debugger = LrLogger( 'RcLrDebugger' )
    RcUtils.debugger:enable( 'print' ) -- enable "trace"
end



--[[
        Synopsis:       Close debug console - optional.

		Note:           Its not necessary to close the RcUtils.debugger, but it will free
		                resources and keep messages from going to debug console if ya do.
--]]
function RcUtils.debugClose()
	RcUtils.debugger = nil
end



--[[
        Synopsis:    Outputs debug message to external debugger, if open.

		Notes:       Call this repeatedly after debug-open.
--]]
function RcUtils.debugLog( message )
	if RcUtils.debugger then
    	RcUtils.debugger:trace( message )
	-- else open RcUtils.debugger if you dont want debug messages deep-six'd.
	end
end



--[[
        Synopsis:           Output debug message.
        
        Notes:              Goes to external debugger, if open, else log file - if open.
--]]
function RcUtils.debugTrace( id, __info, idIsPrefix )
    local _info
    local info
    if __info == nil then
        _info = '' -- this means calling context must explicitly pass "nil" to distinguish from '' (blank).
    elseif type( __info ) ~= 'string' then
        _info = RcLua.toString( __info )
    else
        _info = __info
    end
    if not RcString.is( _info ) then
        info = id
    elseif idIsPrefix then
        info = id .. _info -- pass the first (static) part of the message as id.
    else
        info = _info -- id is just a key, not part of the message.
    end
    if RcUtils.suppressInfo[ id ] == nil or RcUtils.suppressInfo[ id ] == 0 then
		local answer = RcUtils.showInfo( info, nil, "OK", "Enough", "No Log" )
		if answer == 'ok' then -- thanks, and continue with dialog box and logging.
			RcUtils.suppressInfo[ id ] = 0
		elseif answer == 'cancel' then -- enough of dialog box
		    RcUtils.suppressInfo[ id ] = 1
		elseif answer == 'other' then -- no log, no dialog box.
		    RcUtils.suppressInfo[ id ] = 2
		else
		    LrErrors.throwUserError( "Unexpected answer: " .. RcLua.toString( answer ) )
    	end
    end
    if RcUtils.suppressInfo[ id ] ~= 2 then
        -- RcUtils.logMessageLine( info, true ) -- debug traces are considered verbose.
        if RcUtils.debugger then -- debugger, if open takes precedence for debug messages.
            RcUtils.debugLog( info )
        elseif RcUtils.logger then
            RcUtils.logger:trace( info ) -- distinquish debug traces from verbose or normal logs.
        -- else ignore.
        end
    end
end



--[[
        Synopsis:           Logs a rudimentary stack trace (function name, source file, line number).
        
        Notes:              Relies on support from
        
        Returns:            X
--]]        
function RcUtils.debugStackTrace()
    -- don't waist time if there's no logger or debugger.
    if not RcUtils.logger and not RcUtils.debugger then
        return
    end
    RcUtils.logMessageLine( "Stack trace:" )
    local i = 2
    while true do
        local info = debug.getinfo (i)
        if not info then
            break
        end
        RcUtils.logMessageLine( LOC( "$$$/X=^1 [^2 ^3]", info.name, info.source, info.currentline) )
        i = i + 1
    end
end
       


--[[
        Synopsis:           Log a simple, non-array table.
        
        Notes:              Does not re-curse.
        
        Returns:            nothing
--]]        
function RcUtils.logTable( t ) -- indentation would be nice. - Presently does not support table recursion.
    -- don't waist time if there's no logger or debugger.
    if not RcUtils.logger and not RcUtils.debugger then
        return
    end
    if t == nil then
        logMessageLine( "nil" )
        return
    end    
    for k,v in pairs( t ) do
        RcUtils.logMessageLine( "key: " .. RcLua.toString( k ) .. ", value: " .. RcLua.toString( v ) )
    end
end



--[[
        Synopsis:           This is a really great tool for logging complex tables when you don't really know whats in them.
        
        Notes:              It could use a little primping, but it has served my purpose so I'm moving on.
        
                            John Ellis's version:
                            
                            --------------------------------------------------------------------
                            function dump (label, x)
                                local function dump1 (x, indent, visited)
                                    if type (x) ~= "table" then
                                        log:trace (string.rep (" ", indent) .. tostring (x))
                                        return
                                        end
                            
                                    visited [x] = true
                                    if indent == 0 then
                                        log:trace (string.rep (" ", indent) .. tostring (x))
                                        end
                                    for k, v in pairs (x) do   
                                        log:trace (string.rep (" ", indent + 4) .. tostring (k) .. " = " ..
                                                   tostring (v))
                                        if type (v) == "table" and not visited [v] then
                                            dump1 (v, indent + 4, visited)
                                            end
                                        end
                                    end
                                   
                                log:trace (label .. ":")
                                dump1 (x, 0, {})
                                end                            
                            --------------------------------------------------------------------
                            
        Arguments:          t           - object (may be table, function, or scaler...)
                            level       - hierarchical level determines indentation.
                            visited     - keeps infinite loops from happening when there are cyclic references.
                            
        Returns:            nothing.
--]]        
function RcUtils._logObject( t, level, visited )

    -- LrTasks.yield() - doen't help for some reason.

    if visited == nil then visited = {} end
    if t == nil then return end
    
    if visited [t] then return end
    visited [t] = true
    
    if level == nil or level < 0 then
        level = 0
    end

    local space = RcString.makeSpace( level * 4 )
    if type( t ) ~= 'table' then
        RcUtils.logMessageLine( space .. RcLua.toString( t ) ) -- eol output in calling context.
    else
        for k,v in pairs( t ) do
            RcUtils.logMessage( space .. "key: " )
            if type( k ) == 'table' then
                RcUtils._logObject( k, level + 1, visited )
                RcUtils.logMessageLine()
                RcUtils.logMessage( space .. 'value: ' )
            else
                RcUtils.logMessage( RcLua.toString( k ) )
                RcUtils.logMessage( ', value: ' )
            end
            if type( v ) == 'table' then
                RcUtils.logMessageLine()
                RcUtils._logObject( v, level + 1, visited ) -- , type( v ) ~= 'table' )
                RcUtils.logMessageLine()
            else
                RcUtils.logMessage( RcLua.toString( v ) )
                RcUtils.logMessageLine()
            end
        end 
        for i,v in ipairs( t ) do
            if type( v ) == 'table' then
                RcUtils.logMessageLine( space .. "index: " .. tostring( i ) .. ", value: " )
                RcUtils._logObject( v, level + 1, visited )
                RcUtils.logMessageLine()
            else
                RcUtils.logMessageLine( space .. "index: " .. tostring( i ) .. ", value: " .. RcLua.toString( v ) )
            end
        end 
    end
end



--[[
        Synopsis:           This is a really great tool for logging complex tables when you don't really know whats in them.
        
        Notes:              It could use a little primping, but it has served my purpose so I'm moving on.
                            
                            Example: RcUtils.logObject( someTable )
        
        Returns:            nothing.
--]]        
function RcUtils.logObject( t )
    -- don't waist time if there's no logger or debugger.
    if not RcUtils.logger and not RcUtils.debugger then
        return
    end
    RcUtils._logObject( t, 0 )
end


-- obsolete since there's property-table-pairs function - leave in until all are converted.
function RcUtils.logPropertyTable2( t )
    -- don't waist time if there's no logger or debugger.
    if not RcUtils.logger and not RcUtils.debugger then
        return
    end
    if t ~= nil then
    	for k,v in t:pairs() do
            RcUtils.logMessageLine( k .. ": " .. RcLua.toString( v2 ) )
    	end
    else
        RcUtils.logMessageLine( "No property table." )
    end
    RcUtils.logInfo()
end



-- obsolete since there's property-table-pairs function - leave in until all are converted.
function RcUtils.logPropertyTable( t )
    -- don't waist time if there's no logger or debugger.
    if not RcUtils.logger and not RcUtils.debugger then
        return
    end
    if t ~= nil then
    	for k,v in pairs( t ) do
    		for k2, v2 in pairs( v ) do
    			RcUtils.logMessage( k2 )
                if type( v2 ) == 'string' then
                    local v3
                    local len = string.len( v2 )
                    if len > 80 then
                        v3 = string.sub( v2, 1, 80 ) .. "........."
                    else
                        v3 = v2
                    end
                    RcUtils.logMessage( ": " .. v3 )
                --elseif type( v2 ) == 'number' then
                --    writer:write( ": " .. RcLua.value( v2 ) )
                else
                    -- writer:write( ": type of value: " .. type( v2 ) )
                    RcUtils.logMessage( ": " .. RcLua.toString( v2 ) )
                end
    			RcUtils.logMessageLine() -- complete a log line.
    		end
    	end
    else
        RcUtils.logMessageLine( "No property table." )
    end
end



------------------------------------
-- File-based logging functions:
------------------------------------



--[[
        Call to open a new log-file/enable logging to file.
        If not called or fails, log functions are no-ops.

        Zeros error/warning counters.

        Error thrown by log module, if log-file specified but cant be opened for writing.
--]]
function RcUtils.logOpen( _logFilePath, _verbose, _overwrite )
    RcUtils._nWarnings = 0
    RcUtils._nErrors = 0
    if RcString.is( _logFilePath ) then
        local logFileName = LrPathUtils.leafName( _logFilePath )
        local loggerName = LrPathUtils.removeExtension( logFileName )
        local loggerDir = LrPathUtils.getStandardFilePath( 'documents' )
        local loggerFile = LrPathUtils.addExtension( loggerName, "log" )
        RcUtils.logFilePath = LrPathUtils.child( loggerDir, loggerFile )
        if RcUtils.logFilePath and LrFileUtils.exists( RcUtils.logFilePath ) and _overwrite then
            LrFileUtils.delete( RcUtils.logFilePath ) -- delete unconditionally - ignore return code.
        end
        local newPath = LrPathUtils.replaceExtension( RcUtils.logFilePath, "txt" )
        if LrFileUtils.exists( newPath ) then
            LrFileUtils.delete( newPath )
        end
        RcUtils.logger = LrLogger( loggerName )
        if _verbose then
            RcUtils.logger:enable( 'logfile' ) -- enable everything to log file.
        else -- deep-six debug & trace messages.
            local actions = {}
            actions.info = 'logfile'
            actions.warn = 'logfile'
            actions.error = 'logfile'
            actions.fatal = 'logfile' -- presently not used, but might be in the future.
            RcUtils.logger:enable( actions ) -- suppress trace & debug.
        end
    else
        RcUtils.logFilePath = nil
    end
end
--[[function RcUtils.blogOpen( _logFilePath, _verbose, _overwrite )
    RcUtils._nWarnings = 0
    RcUtils._nErrors = 0
    if RcString.is( _logFilePath ) then
    	RcUtils.rcLogger = RcLogger:new() -
        RcUtils.rcLogger:init( LrPathUtils.parent, LrFileUtils.exists, LrFileUtils.createAllDirectories )
        local path = LrPathUtils.standardizePath( _logFilePath )
        RcUtils.rcLogger:open( path, _verbose, _overwrite ) -- actual path may have -N appended to base name - be aware.
        RcUtils.logFilePath = RcUtils.rcLogger.logFilePath -- save actual path for display after closing.
    else
        RcUtils.rcLogger = nil
        RcUtils.logFilePath = nil
    end
end--]]


local _message = ''
--[[
        Logs a message segment, no EOL output.
        No-op if logger not open.
--]]
function RcUtils.logMessage( message, verbose )
    if RcUtils.logger == nil then return end
    _message = _message .. message -- probably should use a string buffer, although I think this is used mostly conservatively.
end
--[[function RcUtils.logMessagee( message, verbose )
    if RcUtils.rcLogger then
        RcUtils.rcLogger:log( message, verbose )
    end
end--]]
RcUtils.logInfoStart = RcUtils.logMessage



--[[
        Logs a message line, or end-of-line - EOL output after message.
        No-op if logger not open.
--]]
function RcUtils.logMessageLine( message, verbose )
    if RcUtils.logger == nil then return end
    if not message then
        message = ''
    end
    _message = _message .. message
    if verbose then
        RcUtils.logger:debug( _message )
    else
        RcUtils.logger:info( _message )
    end
    _message = ''
end
--[[function RcUtils.logMessageRine( message, verbose )
    if RcUtils.rcLogger then
        RcUtils.rcLogger:logLine( message, verbose )
    end
end--]]
RcUtils.logInfo = RcUtils.logMessageLine



--[[
        Logs a warning line with a warning prefix that includes index number, and counts it.
        No-op if logger not open.

        Note: warnings are never considered verbose.
--]]
function RcUtils.logWarningLine( _msg )
    RcUtils._nWarnings = RcUtils._nWarnings + 1
    if RcUtils.logger == nil then return end
    local msg
    local endPos = RcString.startsWith( _msg, "*** WARNING: " )
    if endPos > 0 then
        msg = string.sub( _msg, endPos )
    else
        msg = _msg
    end
    RcUtils.logger:warn( LOC( "$$$/X=****** WARNING #^1: ^2", RcUtils._nWarnings, msg ) ) -- good idea to include error & warning numbers.
    -- RcUtils.logMessageLine( LOC( "$$$/X=****** WARNING #^1: ^2", RcUtils._nWarnings, message ) ) -- good idea to include error & warning numbers.
end
RcUtils.logWarning = RcUtils.logWarningLine -- deprecated - use function above.



--[[
        Logs an error line with an error prefix that includes index number, and counts it.
        No-op if logger not open.
--]]
function RcUtils.logErrorLine( _message )
    RcUtils._nErrors = RcUtils._nErrors + 1
    if RcUtils.logger == nil then return end
    local message
    local endPos = RcString.startsWith( _message, "****** ERROR: " )
    if  endPos > 0 then
        message = string.sub( _message, endPos )
    else
        message = _message
    end
    RcUtils.logger:error( LOC( "$$$/X=****** ERROR #^1: ^2", RcUtils._nErrors, message ) ) -- good idea to include error & warning numbers.
    -- RcUtils.logMessageLine( LOC( "$$$/X=****** ERROR #^1: ^2", RcUtils._nErrors, message ) ) -- good idea to include error & warning numbers.
end
RcUtils.logError = RcUtils.logErrorLine -- deprecated - use function above.



--[[
        Closes the log file - no more logs will be accepted after this is called.
--]]
function RcUtils.logClose()
    if RcUtils.logFilePath and LrFileUtils.exists( RcUtils.logFilePath ) then
        local newPath = LrPathUtils.replaceExtension( RcUtils.logFilePath, "txt" )
        if LrFileUtils.exists( newPath ) then
            LrFileUtils.delete( newPath ) -- move-to-trash may cause error on some systems(?) rc-utils can not depend on rc-file-utils.
        end
        -- i'm assuming it was deleted if necessary.
        if RcUtils.logOverwrite then
            LrFileUtils.move( RcUtils.logFilePath, newPath )
        else
            LrFileUtils.copy( RcUtils.logFilePath, newPath )
        end
        RcUtils.logFilePath = newPath -- I'm assuming the move or copy succeeded.
    end
    if RcUtils.logger then
        RcUtils.logger = nil
    end
end
--[[function RcUtils.logCrose()
    if RcUtils.rcLogger then
	    RcUtils.rcLogger:close()
        RcUtils.rcLogger = nil
    end
end--]]



--[[
        Closes the log file "temporarily" for viewing, to be continued...
--]]
function RcUtils.logPause()
    return -- no-op when using lr-logger.
end
--[[function RcUtils.logClause()
    if RcUtils.rcLogger then
        RcUtils.rcLogger:pause()
    end
end--]]



--[[
        Re-opens a log file previously paused for viewing.
--]]
function RcUtils.logContinue()
    return -- no-op when using lr-logger.
end    
--[[function RcUtils.logContinyou()
    if RcUtils.rcLogger then
        RcUtils.rcLogger:continue()
    end
end--]]   



--[[
        Return number of errors logged.
--]]
function RcUtils.nErrors()
    return RcUtils._nErrors
end    



--[[
        Return number of warnings logged.
--]]
function RcUtils.nWarnings()
    return RcUtils._nWarnings
end    





-- UI support:



--[[
        *** DEPRECATED: USE INIT-PLAIN INSTEAD.

        Instructions:
            - call this in service provider module.
        

		Initialize static elements for common UI functions.
		Presently takes a table with named elementS:
			- appName - name of application for UI display.
			- (see below for more)
--]]
function RcUtils.initUI( t )
    if t == nil then
        return -- have to struggle with generics or whatever.
    end
	if t.appName then
		RcUtils.appName = t.appName
    elseif _G.appName then
        RcUtils.appName = _G.appName
	end
    RcUtils.verMajor = t.verMajor
    RcUtils.verMinor = t.verMinor
    RcUtils.verRevision = t.verRevision
    RcUtils.author = t.author
    RcUtils.authorsWebsite = t.authorsWebsite
    RcUtils.pluginUrl = t.pluginUrl
end



--[[
        Synopsis:           Initialize app-wide vars...
        
        Notes:              - I wish I had relied on functions instead of public vars for some of these things,
                              so the figuring could be done on the way out, instead of on the way in - oh well...
                            - Designed to be called multiple times with impunity.
        
        Returns:            X - errors thrown are not trapped.
--]]        
function RcUtils.init()
    if _G.infoLua == nil then
        return
    end
    RcUtils.appName = infoLua.appName or infoLua.LrPluginName -- lr plugin name will never be nil.
    RcUtils.author = infoLua.author or 'Unknown'
    RcUtils.authorsWebsite = infoLua.authorsWebsite or 'Unknown'
    RcUtils.pluginUrl = infoLua.LrPluginInfoUrl or RcUtils.authorsWebsite
end



--[[
        *** DEPRECATED - VERSION NUMBER IS REDUNDENT. ***

        Synopsis:       Get plugin version as string.
        
        Note:           Version initialized in init-ui function.
--]]
function RcUtils.getVersionString()
    local ver = {}
    ver[1] = RcUtils.verMajor or _G.verMajor or ''
    ver[2] = RcUtils.verMinor or _G.verMinor or ''
    ver[3] = RcUtils.verRevision or _G.verRevision or ''
    return table.concat( ver, "." )
end



function RcUtils.getAppName()
    if _G.infoLua then
        return infoLua.appName or "A Lightroom plugin" -- default would happen if user did not enter app-name (correctly) in info.lua.
    else
        return "Unknown" -- should never happen unless rc-utils has never been initialized.
    end
end 


function RcUtils.getPluginName()
    if _G.infoLua then
        return infoLua.LrPluginName
    else
        return "Unknown" -- should never happen unless rc-utils has never been initialized.
    end
end 



function RcUtils.getPlatformString()
    if _G.infoLua then
        if RcString.is( infoLua.platformDisp ) then
            return infoLua.platformDisp
        elseif not RcTable.isEmpty( infoLua.platforms ) then
            return table.concat( infoLua.platforms, "+" )
        else
            return ""
        end
    else
        return "Unknown " -- should never happen unless rc-utils has not been initialized.
    end
end 



function RcUtils.getCompatibilityString()

    local compatTbl = {}
    local platforms = RcUtils.getPlatformString()
    if RcString.is( platforms ) then
        compatTbl[#compatTbl + 1] = platforms
    end
    compatTbl[#compatTbl + 1] = RcUtils.getLrCompatibilityString() -- always includes standard stuff
    local compatStr = table.concat( compatTbl, ", " )
    return compatStr

end



--[[
        Synopsis:           Get friendly Lr compatibility display string.
        
        Notes:              - This will need to be updated each major version of lightroom.
                            - If Adobe ever updated the SDK between major vers it could even be updated then.
                            - Typical use: plugin manager info at top.
                            - Update when Lr4 released.
                            - Depends on calling init function.
        
        Returns:            e.g. Lr2+Lr3
--]]        
function RcUtils.getLrCompatibilityString()
    
    if infoLua == nil then
        return "Unknown"
    end
    
    local lrCompat = "Lr" .. infoLua.LrSdkMinimumVersion
    if infoLua.LrSdkVersion ~= infoLua.LrSdkMinimumVersion then
        lrCompat = lrCompat .. " to Lr" .. infoLua.LrSdkVersion
    else
        -- lrCompat = lrCompat .. " only" -- trying to say too much - may make user think it won't work with dot versions.
        -- Note: an older version of Lightroom won't load it if min ver too high, so the "only" would never show in that case anyway.
        -- Only value then would be on more advanced version of Lightroom. So, its up to the plugin developer to bump that number
        -- once tested on the higher version of Lightroom. Users of higher Lr versions should rightly be concerned until then.
    end
    
    return lrCompat
    
end



function RcUtils.getAuthor()
    if _G.infoLua ~= nil then
        return infoLua.author or "Unknown" -- new way: set author in info.lua.
    else
        return RcUtils.author or _G.author or 'Unknown' -- legacy(s)
    end
end

function RcUtils.getAuthorsWebsite()
    if _G.infoLua ~= nil then
        return infoLua.authorsWebsite or "Unknown"
    else
        return RcUtils.authorsWebsite or _G.authorsWebsite or 'Unknown'
    end
end

function RcUtils.getPluginUrl()
    if _G.infoLua ~= nil then
        return infoLua.LrPluginInfoUrl or "Unknown"
    else
        return RcUtils.pluginUrl or _G.pluginUrl or RcUtils.getAuthorsWebsite()
    end
end



--[[function RcUtils.showBriefly( msg, secs ) - save for possible future resurrection: can't get it to disappear afterward.
    LrFunctionContext.callWithContext( "ShowBriefly", function(context)
          local args = {}
            args.title = RcUtils.getAppName()
            args.caption = msg
            args.cannotCancel = true
            args.functionContext = context
    
          local progressScope = LrDialogs.showModalProgressDialog( args ) -- the dialog is modal UI-wise, but the tasks keeps executing.
        LrTasks.sleep( secs ) -- hang while Lightroom initializes during startup, or so user can see something after manual re-start or re-load.
            -- Beware: sometimes a second or two gets shaved off the time specified.
        progressScope:cancel() -- should be good.
        -- progressScope = nil
    end )
end--]]



--[[
		Show what may be important information to the user.
		To make it optional, pass an action pref key.		
        
        buttons - table of button specs for prompt-for-action-with-do-not-show
                    - action-pref-key required.
                    - table element format: label, verb (cancel comes free, so just need action and optionally other).
                    - cancel & other button parameters ignored.
                OR
                - ok-button-label
                
                OR
                - nil for message with do not show & default buttons.
                
        cancelButton - string - goes with ok-button-label
        otherButton - string - optional: requires with ok and cancel buttons.
        
--]]
function RcUtils.showInfo( msg, actionPrefKey, buttons, cancelButton, otherButton )
    RcUtils.logPause()

    local message = LOC( RcUtils.infoMsg, RcUtils.getAppName() )
    local info = msg

	if actionPrefKey then
        if buttons then
            assert( type( buttons ) == 'table', "Buttons should be table." )
            local args = {}
            args.message = message
            args.info = info
            args.actionPrefKey = actionPrefKey
            args.verbBtns = buttons
		    return LrDialogs.promptForActionWithDoNotShow( args )
        else
		    LrDialogs.messageWithDoNotShow( { message=message, info=info, actionPrefKey=actionPrefKey } )
        end
	else
        if buttons then -- button string
            assert( type( buttons ) == 'string', "Buttons should be string." )
            return LrDialogs.confirm( message, info, buttons, cancelButton, otherButton )
        else
    	    LrDialogs.message( message, info, RcUtils.infoType )
        end
	end

    RcUtils.logContinue()
end



--[[
		Synopsis:           Show warnings to user, display of which is not optional - use info if its an optional warning.
		
		Notes:              This does not increment warning count. - Generally used in conjunction with log-warning.
--]]
function RcUtils.showWarning( msg, b1, b2, b3 )
    RcUtils.logPause()
    local message = LOC( RcUtils.warningMsg, RcUtils.getAppName() )
    local warning = msg
    local retVal = nil
    if b1 or b2 or b3 then
        retVal = LrDialogs.confirm( message, warning, b1, b2, b3 )
    else
  	    LrDialogs.message( message, warning, RcUtils.warningType )
  	end
    RcUtils.logContinue()
    return retVal
end



--[[
		Showing of errors is never optional.
--]]
function RcUtils.showError( msg, b1, b2, b3 )
    RcUtils.logPause()
    local message = LOC( RcUtils.errorMsg, RcUtils.getAppName() )
    local _error = msg
    local retVal = nil
    if b1 or b2 or b3 then
        retVal = LrDialogs.confirm( message, _error, b1, b2, b3 )
    else
  	    LrDialogs.message( message, _error, RcUtils.errorType )
  	end
    RcUtils.logContinue()
    return retVal
end



--[[
		Asking if OK to do something, or not.
		For more complex prompts, use confirm box directly.
--]]
function RcUtils.isOk( msg )
    RcUtils.logPause()
    local answer = LrDialogs.confirm( LOC( RcUtils.isOkMsg, RcUtils.getAppName() ), msg )
    RcUtils.logContinue()
    return answer == 'ok'
end



--[[
        Synopsis:       Prompt user to continue or not, with option to remember decision.
--]]
function RcUtils.isOkOrDontAsk( msg, id )
    RcUtils.logPause()
    local t = {}
    t[1] = { label="OK", verb="ok" }
    local args = {}
    args.message = LOC( RcUtils.isOkMsg, RcUtils.getAppName() )
    args.info = msg
    args.actionPrefKey = id
    args.verbBtns = t
    local answer = LrDialogs.promptForActionWithDoNotShow( args )
    RcUtils.logContinue()
    return answer == 'ok'
end    



--[[
        Supports loading of lua file via dofile.
        File may be specified with the lua extension, or without
        and may be specified absolutely or relative to plugin
        or relative to catalog.

		From the best I can tell, at least in Lightroom context (which does not support
		loading 'C' modules), dofile is the same as require
		except the user can specify the complete path instead of requiring it to be
		in the same directory as the plugin. (Also, do-file does not store table reference
        in global variables). This function takes advantage of that
		since it is desirable for some of us to store config files in a directory
		with other project files, not the plugin proper.
--]]
function RcUtils.dofilePaths( fileSpec )
    assert( RcString.is( fileSpec ), "File specifier can not be nil or blank." )
	local tryNumber = 0
	return function()
        tryNumber = tryNumber + 1
	    local filename = LrPathUtils.leafName( fileSpec )
	    local extension = LrPathUtils.extension( filename )
	    if not RcString.is( extension ) or extension ~= "lua" then
	        filename = filename .. ".lua"
	    else
	        -- extension already is lua.
	    end
	    if tryNumber < 3 then
	        local basepath
	        local parentpath = LrPathUtils.parent( fileSpec )
	        if tryNumber == 1 then
	            basepath = _PLUGIN.path
	        elseif tryNumber == 2 then
	            basepath = LrApplication.activeCatalog():getPath()
	        else
	            error( "Program failure doing file, spec: " .. fileSpec )
	        end
	        if RcString.is( parentpath ) then
	            basepath = LrPathUtils.child( basepath, parentpath )
	        end
	        return LrPathUtils.child( basepath, filename )
	    elseif tryNumber == 3 then
	        return filename
        else
            return nil
        end
	end
end



--[[
        Gets a path to a hopefully existing support file (or folder), given an already perfect absolute path,
        or a partial relative path, which will be considered to be relative to catalog, plugin,
        "standard" directory, or default directory, whichever comes first.

        returns string path to first existing, else table of paths not existing - never returns nil.

        Reminder: windows default dir is C:\Windows\System32, so rarely should one specify a path relative
        to that - it should be absolute, or relative to one of the standard dirs.

        *** Files found in default dir will result in a warning log.

        Reminder: call standardize-path first to support standard path "shortcuts".
--]]
function RcUtils.getSupportPath( supportSpec )
    local path
    local supportDir
    local notIt = {}
    local exists
    if supportSpec then
        if LrPathUtils.isAbsolute( supportSpec ) then
            exists = LrFileUtils.exists( supportSpec )
            if exists then -- conditional asserted if 'file' or 'directory', but not if nil or false.
                return supportSpec
            else
                return { supportSpec }
            end
        end
        -- fall-through => not absolute - try relative to catalog.
        supportDir = LrPathUtils.parent( LrApplication.activeCatalog():getPath() )
        path = LrPathUtils.child( supportDir, supportSpec )
        exists = LrFileUtils.exists( path )
        if exists then
            return path
        else
            notIt[#notIt + 1] = path
        end
        -- fall-through => not in catalog folder either.
        
        -- try plugin parent.
        supportDir = LrPathUtils.parent( _PLUGIN.path )
        path = LrPathUtils.child( supportDir, supportSpec )
        exists = LrFileUtils.exists( path )
        if exists then
            return path
        else
            notIt[#notIt + 1] = path
        end
        
        -- try plugin proper.
        supportDir = _PLUGIN.path
        path = LrPathUtils.child( supportDir, supportSpec )
        exists = LrFileUtils.exists( path )
        if exists then
            return path
        else
            notIt[#notIt + 1] = path
        end
 
        -- fall-through => not in plugin folder either.

        local defaultTable = { 'home', 'documents', 'appPrefs', 'desktop', 'pictures' }
        for supportIndex, supportName in ipairs( defaultTable ) do
            supportDir = LrPathUtils.getStandardFilePath( supportName )
            assert( supportDir ~= nil, "can not get standard file path for: " .. RcLua.toString( supportName ) )
            path = LrPathUtils.child( supportDir, supportSpec )
            exists = LrFileUtils.exists( path )
            if exists then
                return path
            else
                notIt[#notIt + 1] = path
            end 
        end

        -- fall-through => not relative to one of the standard dirs either.

        exists = LrFileUtils.exists( supportSpec )
        if exists then -- conditional asserted if 'file' or 'directory', but not if nil or false.
            RcUtils.logWarning( "File found in default directory - should be elsewhere: " .. supportSpec )
            return supportSpec
        else
            notIt[#notIt + 1] = supportSpec
        end

        return notIt
    else
        return { "path not specified" }
    end
end



--[[
        Synopsis:           Loads a table supporting a plugin.
        
        Notes:              - Initial application supports config file.
                            - presumably table is user-editable. If not, then there's no point, since there is no:
                              sister "store-support-table" function.
        
        Returns:            Support table, else nil and error message.
--]]        
function RcUtils.loadSupportTable( fileSpec )

    local path = RcUtils.getSupportPath( fileSpec )
    if type( path ) == 'string' then -- it exists
        local sts, retVal = pcall( dofile, path )
        if sts then
            if retVal ~= nil then
                return retVal, path
            else
                return nil, "Nil returned from: " .. path
            end
        else
            return nil, "Unable to load file due to: " .. RcLua.toString( retVal ) -- ret-val includes file-path
        end
    else
        return nil, "File not found at:\n" .. table.concat( path, "\n" )
    end    

end



--[[
        Synopsis:           Catalog access wrapper that distinquishes catalog contention errors from target function errors.
        
        Notes:              - Returns immediately upon target function error. 
       
                            - The purpose of this function is so multiple concurrent tasks can access the catalog in succession without error.
                            
                            func is catalog with-do function
                            cat is the catalog object.
                            p1 is first parameter which may be a function, an action name, or a param table.
                            p2 is second parameter which will be a function or nil.
        
        Returns:            itsAGoOrNot, andWhatever.
--]]        
function RcUtils.withCatalogDo( tryCount, func, cat, p1, p2 )
    while( true ) do
        for i = 1, tryCount do
            local sts, qual = LrTasks.pcall( func, cat, p1, p2 )
            if sts then
                return true, qual
            elseif RcString.is( qual ) then
                local found = qual:find( "LrCatalog:with", 1, true ) or 0 -- return position or zero, instead of position or nil.
                if found == 1 then -- problem reported by with-catalog-do method.
                    local found2 = qual:find( "already inside", 15, true )
                    if found2 == nil then
                        found2 = qual:find( "was blocked", 15, true ) -- Lr4b
                    end
                    if found2 then
                        -- problem is due to catalog access contention.
                        if RcUtils._debugMode then -- module development debug.
                            LrDialogs.message( 'cat contention: ' .. RcLua.toString( qual ) )
                        elseif RcUtils.debugMode then -- log verbose - user app-wide debug mode
                            RcUtils.logWarning( 'cat contention: ' .. RcLua.toString( qual ) )
                            LrTasks.sleep( math.random( .1, 1 ) ) -- sleep for a half-second or so, then try again.
                        else
                            LrTasks.sleep( math.random( .1, 1 ) ) -- sleep for a half-second or so, then try again.
                        end
                    else
                        -- LrDialogs.message( 'not already inside cat: ' .. RcLua.toString( qual ) )
                        return false, qual
                    end
                else
                    -- LrDialogs.message( 'not a cat with msg: ' .. RcLua.toString( qual ) )
                    return false, qual
                end
            else
                -- LrDialogs.message( 'bad cat sts, but no msg.' )
                return false, 'Unknown error occurred accessing catalog.'
            end
        end
    	local action = RcUtils.showWarning( "Unable to access catalog.", "Keep Trying", "Give Up" )
    	if action == 'ok' then
    		-- keep trying
            -- LrDialogs.message( "Will try again." )
    	else
    		-- assert( action == 'cancel', "unexpected error action: " .. RcLua.toString( action )  )
            -- LrDialogs.message( "Gave up trying to access catalog." )
    		return false, "Gave up trying to access catalog."
    	end
    end
    -- RcUtils.logError( "Unable to access catalog." ) - let this be done in calling context.
    -- LrDialogs.message( LOC( "$$$/X=Unable to access catalog after ^1 tries.", tryCount ) )
    return false, LOC( "$$$/X=Unable to access catalog." )
end



-- Deprecated: Probably this should be done right or not at all...
local _opTimer -- debug timer support - take care not to overwrite by nesting timed operations.
function RcUtils.startOpTimer()
    _opTimer = LrDate.currentTime()
end
function RcUtils.logOpTime()
    local timer = LrDate.currentTime()
    local time = timer - _opTimer
    RcUtils.logMessageLine( "Elapsed Time: " .. time ) -- formatting would help.
    _opTimer = timer
end



--[[
        Synopsis:           Failure handler which can be used if nothing better springs to mind.
        
        Background:         How Lightroom handles errors in plugins:
        
                            - if error occurs, then check if there is a registered handler,
                              if so, then call it, if not - do nothing.
                              
                            - button handlers operate in contexts that do not have error handlers
                              registered.
        
        Notes:              - first parameter is always false.
        
                            - This default failure handler, should be used "instead" of a pcall, in cases
                              where you you just want to display an error message, instead of croaking
                              with the default lightroom error message (e.g. normal plugin functions),
                              or dieing siliently (e.g. button handlers).
        
        Returns:            Nothing.
--]]        
function RcUtils.defaultFailureHandler( _false, errMsg )
    local msg = RcLua.toString( errMsg ) .. ".\n\nPlease report this problem - thank you in advance..."
    LrDialogs.message( ( RcUtils.getAppName() or RcLua.toString( _PLUGIN.id ) ) .. " has encountered a problem, error message:", msg )
end



--[[
        Synopsis:           Calls a target function wrapped in context with an optional cleanup handler and either the default or specified failure handler.
        
        Notes:              - As a task, or not.
                            - Optional cleanup func.
                            - Primary purpose is to wrap main functions, and button handlers.
                              Subroutines should use pcall for parameter passing and custom error handling.
                            - if cleanup handler specified without failure handler, then there will be no failure handler default, since the cleanup handler might as well do the job.
                            - if no cleanup nor failure func specified, the default failure handler will be added.
                            - Recursion guards need to be implemented in calling context.
                              - Use simple flag for vocal or silent guards.
                              - Note: there is no reason to use lr-recursion-guard, since it essentially acts as a wrapper clearing the guard flag as a cleanup item,
                                - just rememember to clear your simple guard flag in the cleanup handler.
                            - wrapped functions can be nested.
                            
                            - All of this can be handled using a simple pcall. It is really a convenience function. an alternative would be:
                            local mainFunc = function( p1 )
                                -- do my thing
                            end
                            local sts, other = LrTasks.pcall( mainFunc, "p" )
                            if sts then
                                -- log operation success
                            else
                                -- log operation failure
                                -- perform cleanup
                                rc-utils.defaultFailureHandler( false, other )
                            end
                            - And in fact, this technique is required if main-func has parameters.
                            - I continue to use this technique for lower level functions, but wrap
                            - main functions and button handlers, validate functions... for convenience.
                            
        Examples:           if _G.mythingbusy then -- recursion guard
                                output( "cant now..." ) -- vocal: comment out for silent.
                                return
                            end
                            _G.mythingbusy = true
                            rc-utils-wrap( "my thing", true, function( context ) -- run my thing as task with context.
                                -- do something asynchronously.
                            end, function( status, message ) -- cleanup / failure handler.
                                _G.mythingbusy = false -- clear busy flag whether bombed due to error or normal completion.
                                if status then
                                    -- completed without uncaught errors.
                                else
                                    -- deal with error / message.
                                end
                            end ) -- no explicit (redundent) failure handler
                            
                            ----------------------------------------------    

                            -- no recursion guard.                            
                            rc-utils-wrap( "my thing", false, function( context ) -- do my thing synchronously (and wait for return), with context.
                                -- do something synchronously.
                            end, nil, function( _false, message ) -- no cleanup
                                -- deal with error in a special non-default way...
                            end )
                            
                            ---------------------------------------------
                                
                            -- no recursion guard.                            
                            rc-utils-wrap( "my thing", false, function( context ) -- do my thing synchronously (and wait for return), with context.
                                -- do something synchronously.
                            end ) -- no cleanup handler - but use default error handler.
                            
                            ---------------------------------------------
                                
        Returns:            Nothing.
--]]        
function RcUtils.wrap( name, asTask, mainFunc, cleanupFunc, failureFunc )
    local failureHandler
    if failureFunc == nil then
        if cleanupFunc then
            failureHandler = nil
        else
            failureHandler = RcUtils.defaultFailureHandler
        end
    else
        failureHandler = failureFunc
    end
    if asTask then
        LrFunctionContext.postAsyncTaskWithContext( name, function( context )
            if failureHandler then
                context:addFailureHandler( failureHandler )
            end
            if cleanupFunc then
                context:addCleanupHandler( cleanupFunc )
            end
            mainFunc( context )
        end )
    else
        LrFunctionContext.callWithContext( name, function( context )
            if failureHandler then
                context:addFailureHandler( failureHandler )
            end
            if cleanupFunc then
                context:addCleanupHandler( cleanupFunc )
            end
            mainFunc( context )
        end )
    end        

end



--[[
        Synopsis:           Perform an operation protected by vocal recursion guard, as-task (or not), protected by failure handler, optionally by cleanup handler.
        
        *** IMPORTANT NOTE: This function REQUIRES external cleanup-func which calls rc-utils-end-wrap with the same name to clear the guard.
        
        Returns:            X - status of operation and maybe error message passed to cleanup-func.
--]]        
function RcUtils.wrapGuarded( name, asTask, mainFunc, cleanupFunc, failureFunc )
    if _G.guarden == nil then
        _G.guarden = {}
    elseif _G.guarden[name] then
        RcUtils.showWarning( name .. " is already active." )
        return
    end
    guarden[name] = true
    RcUtils.wrap( name, asTask, mainFunc, cleanupFunc, failureFunc )
end



--[[
        Synopsis:           Call to end a wrapped operation - especially a guarded wrap.
        
        *** IMPORTANT NOTE: Works for guarded or non-guarded wraps, but REQUIRED for guarded wraps.
        
        Note:               A simple abort message can be passed instead of the quit/quit-message pair.
        
        Returns:            X - and must be self-protected for errors, since its called as part of a (possibly due to error) cleanup handler.
--]]        
function RcUtils.endWrap( name, status, message, _quit, _quitMessage )
    if _G.guarden ~= nil then
        guarden[name] = nil
    end
    -- check for translation of abort-message to quit/quit-message combo for end-service.
    local quit, quitMessage
    if _quit ~= nil and ( type( _quit ) == 'string' ) then
        if _quit:len() > 0 then
            quit = true
            quitMessage = _quit
        else
            quit = false
            quitMessage = ''
        end
    else
        quit = _quit -- or false
        quitMessage = _quitMessage -- or ''
    end
    local boxName = name .. " - EndBox"
    if status then
        RcUtils.logInfo( name .. " finished." )
        RcUtils.endService( quit, quitMessage, boxName )
    else -- error
        RcUtils.logError( name .. " aborted due to error: " .. RcLua.toString( message ) )
        quit = true
        quitMessage = "Aborted due to error."
        RcUtils.endService( quit, quitMessage, boxName )
    end
end



--[[function RcUtils.endNamedService( name, status, message )

    RcUtils.endWrap( name, status, message, nil, nil )

end--]]
    
        

--[[
        Synopsis:           Executes the specified command via the OS command shell.
        
        Notes:              - command is a string generally consisting of a target app, parameters, and object files.
                            - call from task.
        
        Returns:            returns true, command string executed if exit-code = 0.
                            returns false, error-message if no-go.
--]]        
function RcUtils.execute( command, expectExitCode )
    local sts, other = LrTasks.pcall( LrTasks.execute, command )
    if sts then
        if expectExitCode == nil then
            expectExitCode = 0
        end
        if other ~= nil and other == expectExitCode then 
            return true, command
        else
            return false, "Non-zero exit code returned by command: " .. command .. ", exit-code: " .. RcLua.toString( other )
        end
    else
        return false, "Error executing command: " .. command
    end
end



--- Executes the specified command via the windows or mac command shell - stolen from elare framework.
--
--  @param      exeFile name or path of executable.
--  @param      _params command parameter string, e.g. '-p -o "/Programs for lunch"' (without the apostrophes).
--  @param      _targets array of command targets, usually one or more paths.
--  @param      outPipe: filename or path - used for capturing output. if nil, but outHandling is 1 or 2, then a temp file will be used (same dir as plugin).
--  @param      outHandling: nil or '' => do nothing with output, 'get' => retrieve output as string, 'del' => retrieve output as string and delete output file.
--
--  @usage      Normally called indirectly by way of app object - see it for more info.
--
--  @return     status (boolean):       true iff successful.
--  @return     command-or-error-message(string):     command if success, error otherwise.
--  @return     content (string):       content of output file, if out-handling > 0.
--
function RcUtils.executeCommand2( exeFile, _params, _targets, outPipe, outHandling, expectExitCode )
    if exeFile == nil then
        return false, "executable file spec is nil"
    end
    local params
    if _params == nil then
        params = ''
    else
        params = ' ' .. _params
    end
    local targets
    if RcTable.isEmpty( _targets )  then
        targets = {}
    else
        targets = _targets
    end
    local cmd
    if WIN_ENV then
        cmd = '"' -- windows seems to be happiest with an extras set of quotes around the whole thing(?), or at least does not mind them. Mac does not like them.
    else
        cmd = ''
    end
    cmd = cmd .. '"' .. exeFile .. '"'.. params
    for i,v in ipairs( targets ) do
        cmd = cmd .. ' "' .. v .. '"'
    end
    if RcString.is( outHandling ) then
        if not outPipe then
            outPipe = LrFileUtils.chooseUniqueFileName( LrPathUtils.child( _PLUGIN.path, '__tempOutPipe.txt' ) )
        end
    end
    if outPipe then
        cmd = cmd .. ' > "' .. outPipe .. '"'
    end 
    if WIN_ENV then
        cmd = cmd .. '"'
    end
    
    if LrPathUtils.isRelative( exeFile ) or LrFileUtils.exists( exeFile ) then -- reminder: do not use rc-file-utils here.
    
        --   E X E C U T E   C O M M A N D
        local s, m = RcUtils.execute( cmd, expectExitCode )
        if not s or not RcString.is( outHandling ) then
            return s, m
        end
        
        -- fall-through => executed and need to handle output.
        if LrFileUtils.exists( outPipe ) then
            local sts, msg, content, orNot
            sts, orNot = LrTasks.pcall( LrFileUtils.readFile, outPipe )
            if sts then
                content = orNot
                if RcString.is( content ) then
                    sts, msg = true, m
                else
                    sts, msg = false, "Output pipe file (" .. outPipe .. ") contained no content, command: " .. cmd
                end
            else
               sts, msg = false, "Unable to read content of output file, error message: " .. (orNot or 'nil') .. ", command: " .. cmd -- errm includes path.
            end
            if outHandling == 'del' then
                -- local s, m = fso:deleteFolderOrFile( outPipe )
                local s, m = LrFileUtils.delete( outPipe ) -- ignores lr-delete return code and just checks checks for deleted file a few times.
                if s then
                    return sts, msg, content
                else
                    return false, "Unable to delete output file: " .. RcLua.toString( m ) .. ", command: " .. cmd -- error message includes path.
                end
            elseif outHandling == 'get' then
                return sts, msg, content
            else
                return false, "invalid output handling specified: " .. RcLua.toString( outHandling )
            end
            
        else
            return false, "There was no output from command: " .. cmd .. ", was hoping for file to exist: " .. outPipe
        end
        
    else
        return false, "Command file is missing: " .. exeFile
    end
    
    
end






--[[
        Synopsis:           Executes the specified command via the windows or mac command shell.
        
        Notes:              - format is typically a path to an executable, with parms, properly quoted.
                            - exe-file is path to executable.
                            - params is string of the form: '-x -y ...' i.e. space separated string (may be nil).
                            - targets is array of paths (may be nil or empty).
                            
                            - Call from task.
        
        Returns:            returns true, command if executed and exit-code = 0.
                            returns false, error-message if no-go.
--]]        
function RcUtils.executeCommand( exeFile, _params, _targets, outPipe )
    if exeFile == nil then
        return false, "executable file spec is nil"
    end
    local params
    if _params == nil then
        params = ''
    else
        params = ' ' .. _params
    end
    local targets
    if RcTable.isEmpty( _targets )  then
        targets = {}
    else
        targets = _targets
    end
    local cmd
    if WIN_ENV then
        cmd = '"' -- windows seems to be happiest with an extras set of quotes around the whole thing(?), or at least does not mind them. Mac does not like them.
    elseif MAC_ENV then
        cmd = ''
    else
        error ("no env" )
    end
    cmd = cmd .. '"' .. exeFile .. '"'.. params
    for i,v in ipairs( targets ) do
        cmd = cmd .. ' "' .. v .. '"'
    end
    if outPipe then
        cmd = cmd .. ' > "' .. outPipe .. '"'
    end 
    if WIN_ENV then
        cmd = cmd .. '"'
    end
    
    if LrPathUtils.isRelative( exeFile ) or LrFileUtils.exists( exeFile ) then -- reminder: do not use rc-file-utils here.
        return RcUtils.execute( cmd )
    else
        return false, "Command file is missing: " .. exeFile
    end
end



--[[
        Synopsis:       Determines if plugin can support Lr3 functionality.
        
        Notes:          Returns false in Lr1 & Lr2, true in Lr3, will still return true in Lr4 (assuming deprecated items persist for one & only one version), false in Lr5.
--]]
function RcUtils.isLr3()
    if LrApplication.versionTable ~= nil then
        return LrApplication.versionTable().major >= 3
    else
        return false
    end
end



--[[
        Synopsis:           Substitute for non-working Lightroom version, until fixed.
        
        Notes:              - This will be removed or replaced with the equivalent lightroom version once difficulties are resolved.
                            - Writes a table into file plugin-id.properties.lua with the specified property.
        
        Returns:            Nothing. throws error if bad property file.
--]]        
function RcUtils._readPropertyFile( pth )

    if not _G.catalog then
        _G.catalog = LrApplication.activeCatalog()
    end
    local sts, props
    if LrFileUtils.exists( pth ) then
        sts, props = pcall( dofile, pth )
        if sts then
            -- RcUtils.debugTrace( "got contents: ", props )
            if props and type( props ) == 'table' then
                -- good
            else
                error( "Bad property file (no return table): " .. pth )
            end

        else
            -- RcUtils.debugTrace( "no contents" )
            error( "Bad property file (syntax error?): " .. pth )
        end
    else
        props = {}
    end
    return props

end



--[[
        Synopsis:           Substitute for non-working Lightroom version, until fixed.
        
        Notes:              - This will be removed or replaced with the equivalent lightroom version once difficulties are resolved.
                            - Writes a table into file plugin-id.properties.lua with the specified property.
        
        Returns:            Nothing. throws error if can't set property.
--]]        
function RcUtils._savePropertyFile( pth, props )

    if not _G.catalog then
        _G.catalog = LrApplication.activeCatalog()
    end
    local sts, msg
    local overwrite = LrFileUtils.exists( pth )
    local c = {}
    c[#c + 1] = '_t={}'
    for k,v in pairs( props ) do
        local valStr
        if v == nil then
            valStr = 'nil'
        elseif type( v ) == 'string' then
            valStr = '"' .. v .. '"'
        else
            valStr = RcLua.toString( v )
        end
        c[#c + 1] = '_t["' .. k .. '"]=' .. valStr
    end
    c[#c + 1] = 'return _t'
    
    local contents = table.concat( c, '\n' )
    
    -- RcUtils.debugTrace( "contents: ", contents )
    
    --sts, msg = RcFileUtils.writeFile( pth, contents ) -- overwrite is default behavior.
    local ok, fileOrMsg = pcall( io.open, pth, "wb" )
    local msg = nil
    if ok then
        local orMsg
        ok, orMsg = pcall( fileOrMsg.write, fileOrMsg, contents )
        if ok then
            -- good
        else
            msg = LOC( "$$$/X=Cant write file, path: ^1, additional info: ^2", pth, RcLua.toString( orMsg ) )
        end
        -- ok = RcFileUtils.closeFile( fileOrMsg )
        fileOrMsg:close()
        if not ok then
            msg = LOC( "$$$/X=Unable to close file that was open for writing, path: ^1", pth )
        end
    else
        msg = LOC( "$$$/X=Cant open file for writing, path: ^1, additional info: ^2", pth, RcLua.toString( fileOrMsg ) )
    end
    if msg then
        error( msg )
    end

end



--[[
        Synopsis:           Set property value specified by name associated with catalog.
        
        Notes:              - Substitute for non-working Lightroom version, until fixed.
                            - This will be removed or replaced with the equivalent lightroom version once difficulties are resolved.
                            - Writes a table into file plugin-id.properties.lua with the specified property.
                            - name should be string, and value should be number or string or nil.
        
        Returns:            Nothing. throws error if can't set property.
--]]        
function RcUtils.setPropertyForPlugin( _plugin, name, value )

    if catalog == nil then
        _G.catalog = LrApplication.activeCatalog()
    end

    local pluginId
    if _plugin == nil then
        pluginId = _PLUGIN.id
    elseif type( _plugin ) == 'string' then
        pluginId = _plugin
    else
        pluginId = _plugin.id
    end
    assert( pluginId ~= nil, "bad plugin id" )

    local fn = pluginId .. ".Properties.lua"
    local pth = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), fn )

    if name == nil then
        error( "set catalog property name can not be nil." )
    end

    if not _G.propsForPlugin then
        _G.propsForPlugin = {}
    end
    
    if not _G.propsForPlugin[pluginId] then
        _G.propsForPlugin[pluginId] = RcUtils._readPropertyFile( pth )
    end
    if _G.propsForPlugin[pluginId] then
        _G.propsForPlugin[pluginId][name] = value
        RcUtils._savePropertyFile( pth, _G.propsForPlugin[pluginId] ) -- throws error if failure.
    else
        error( "Program failure - no catalog properties for plugin." )
    end

end



--[[
        Synopsis:           Reads named property value associated with catalog.
        
        Notes:              - Substitute for non-working Lightroom version, until fixed.
                            - This will be removed or replaced with the equivalent lightroom version once difficulties are resolved.
                            - Reads from loaded table or loads then reads.
                            - Name must be a string. Value re
        
        Returns:            Value as set. throws error if problem reading properties. may be nil.
--]]        
function RcUtils.getPropertyForPlugin( _plugin, name, forceRead )

    if catalog == nil then
        _G.catalog = LrApplication.activeCatalog()
    end

    local pluginId
    if _plugin == nil then
        pluginId = _PLUGIN.id
    elseif type( _plugin ) == 'string' then
        pluginId = _plugin
    else
        pluginId = _plugin.id
    end
    assert( pluginId ~= nil, "bad plugin id" )

    local fn = pluginId .. ".Properties.lua"
    local pth = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), fn )

    if name == nil then
        error( "get catalog property name can not be nil." )
    end

    if not _G.propsForPlugin then
        _G.propsForPlugin = {}
    end
    
    if not _G.propsForPlugin[pluginId] or forceRead then
        _G.propsForPlugin[pluginId] = RcUtils._readPropertyFile( pth )
    end
    if _G.propsForPlugin[pluginId] then
        -- RcUtils.logInfo( LOC( "$$$/X=Property for ^1 named ^2 read value ^3 from ^4", pluginId, name, _G.propsForPlugin[pluginId][name], pth ), true )
        return _G.propsForPlugin[pluginId][name] -- may be nil.
    else
        error( "Program failure - no catalog properties to get." )
    end

end



--[[
        Synopsis:           Gets property tied to plugin, but not to specific catalog.
        
        Notes:              - Initial application: Importer master sequence number, so an index used for import file naming into different catalogs
                              would not create conflicts in common backup bucket, or when catalogs merged...
        
        Returns:            simple value (original type not table).
--]]        
function RcUtils.getPropertyForPluginSpanningCatalogs( _PLUGIN, name )

    local fn = _PLUGIN.id .. ".Properties.lua"
    local pth = LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), fn )

    if name == nil then
        error( "get catalog spanning property name can not be nil." )
    end

    if not _G.propsForPluginSpanningCatalogs then
        _G.propsForPluginSpanningCatalogs = RcUtils._readPropertyFile( pth )
    end
    if _G.propsForPluginSpanningCatalogs then
        return _G.propsForPluginSpanningCatalogs[name] -- may be nil.
    else
        error( "Program failure - no catalog spanning properties to get." )
    end

end



--[[
        Synopsis:           Set plugin property that is catalog independent.
        
        Notes:              see 'get' function
        
        Returns:            X - throws error if trouble.
--]]        
function RcUtils.setPropertyForPluginSpanningCatalogs( _PLUGIN, name, value )

    local fn = _PLUGIN.id .. ".Properties.lua"
    local pth = LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), fn )
    
    if name == nil then
        error( "set catalog spanning property name can not be nil." )
    end

    if not _G.propsForPluginSpanningCatalogs then
        _G.propsForPluginSpanningCatalogs = RcUtils._readPropertyFile( pth )
    end
    if _G.propsForPluginSpanningCatalogs then
        _G.propsForPluginSpanningCatalogs[name] = value
        RcUtils._savePropertyFile( pth, _G.propsForPluginSpanningCatalogs ) -- throws error if failure.
    else
        error( "Program failure - no catalog spanning properties for plugin." )
    end

end



--[[
        Synopsis:           Gets shared value associated with specified name.
        
        Notes:              - Shared meaning all-plugins, all-catalogs, all-users, ...
                            - Initial application: user-name.
                            - Properties are stored in plugin parent, so they will only be shared by child plugins.
        
        Returns:            - simple value (string, number, boolean - not table).
                            - nil if non-existing.
                            - Throws error if name not supplied or existing properties unobtainable.
--]]        
function RcUtils.getSharedProperty( name )

    local fn = "com.robcole.lightroom.plugin.Shared.Properties.lua"
    local pth = LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), fn )
    _G.sharedPropertiesFile = pth

    if name == nil then
        error( "get shared property name can not be nil." )
    end

    if not _G.sharedProperties then
        _G.sharedProperties = RcUtils._readPropertyFile( pth )
    end
    if _G.sharedProperties then
        return _G.sharedProperties[name] -- may be nil.
    else
        error( "Program failure - no shared properties to get." )
    end

end



--[[
        Synopsis:           Sets property readable by sister function.
        
        Notes:              see 'get' function.
        
        Returns:            X - throws error if trouble.
--]]        
function RcUtils.setSharedProperty( name, value )

    local fn = "com.robcole.lightroom.plugin.Shared.Properties.lua"
    local pth = LrPathUtils.child( LrPathUtils.parent( _PLUGIN.path ), fn )
    
    if name == nil then
        error( "set shared property name can not be nil." )
    end

    if not _G.sharedProperties then
        _G.sharedProperties = RcUtils._readPropertyFile( pth )
    end
    if _G.sharedProperties then
        _G.sharedProperties[name] = value
        RcUtils._savePropertyFile( pth, _G.sharedProperties ) -- throws error if failure.
    else
        error( "Program failure - no shared properties to set." )
    end

end



-- supports managed exports (via catalog property) and unmanaged exports (scope).
--[[ this needs more thought - problems with managed exports could keep unmanaged exports from running.
function RcUtils.isExportCanceled( scope )
    if scope and scope:isCanceled() then
        return true
    end
    return false
    local exportCanceled = RcUtils.getPropertyForPlugin( 'com.robcole.lightroom.export.ExportManager', 'exportCanceled', true ) -- re-reading nearly always required when reading a propterty to be set by a different plugin.
    if exportCanceled == nil then
        if RcUtils.exportNotManaged == nil then
            RcUtils.exportNotManaged = true
            RcUtils.logInfo( "Export appears not to be executing in managed environment." )
        end
        return false
    end
    if exportCanceled == 'yes' then
        return true
    elseif exportCanceled == 'no' then
        return false
    else
        RcUtils.logError( "bad cancel property value: " .. RcLua.toString( exportCanceled ) )
        return false
    end
end
--]]



--[[
        Synopsis:           Initializes user name and global configuration based on user name found in catalog properties.
        
        Notes:              Globals initialized:
        
                                - prefs
                                - user
                                - configPath
                                - configFile
                                - config
                                - catalog
        
        Returns:            X - throws error if config is essential and cant be loaded.
--]]        
function RcUtils.initUserConfig( configFileIsEssential )
    _G.prefs = LrPrefs.prefsForPlugin()
    if not _G.catalog then
        _G.catalog = LrApplication.activeCatalog() -- global catalog is no longer needed since switch to shared properties, but its kinda nice to have...
    end
    _G.user = RcUtils.getSharedProperty( "user" )
    _G.configFile = '"config file not loaded"'
    if RcString.is( user ) then
        if user == 'Rob Cole' then
            configFile = '_' .. _PLUGIN.id .. '.RobsPrivateConfig.lua'
        else
            local squeeze = RcString.squeeze( user ) -- squeezes out spaces.
            configFile = _PLUGIN.id .. '.' .. squeeze .. '.Config.lua'
        end
        RcUtils.logMessageLine( "Pictures: " ..  LrPathUtils.getStandardFilePath( 'pictures' ) )
        RcUtils.logMessageLine( "Plugin user: " .. RcLua.toString( user ) )
        if _G.sharedPropertiesFile then
            RcUtils.logMessageLine( "Shared properties file: " .. RcLua.toString( _G.sharedPropertiesFile ) )
        end
    else
        _G.user = "_Anonymous_"
        configFile = _PLUGIN.id .. '.Config.lua'
        RcUtils.logMessageLine( "Plugin user: " .. RcLua.toString( user ), RcUtils.VERBOSE )
    end
    local status, _config, pathOrMessage = pcall( RcUtils.loadSupportTable, configFile )
    if status and _config and type( _config ) == 'table' then
        RcUtils.logMessageLine( "Using configuration ala file: " .. pathOrMessage )
        _G.config = _config
        _G.configPath = pathOrMessage
    elseif configFileIsEssential then
        error( "Unable to load config file, error message: " .. RcLua.toString( pathOrMessage ) ) -- error message includes path.
    else
        RcUtils.logMessageLine( "No config loaded from " .. configFile, RcUtils.VERBOSE )
    end
end        



--[[
        Synopsis:           Opens one file in its O.S.-registered default app.
        
        Notes:              - I assume this is non-blocking.
                            - Good choice for opening local help files, since lr-http-open-url-in-browser does not work
                              properly on Mac in that case.
        
        Returns:            X
--]]        
function RcUtils.openFileInDefaultApp( file )
    if WIN_ENV then
        LrShell.openFilesInApp( { "" }, file) -- open file like an app, windows knows what to do.
    else -- mac
        LrShell.openFilesInApp( { file }, "open") -- macs like to feed the file to the "open" command.
    end
end



--[[
        Use in tight loop instead of lr-tasks-yield.
        
        big hint: pass returned value back in.
--]]
function RcUtils.yield( count, max )
    count = count + 1
    if not max then max = 20 end
    if count >= max then
        LrTasks.yield()
        return 0
    else
        return count
    end
end

 

return RcUtils