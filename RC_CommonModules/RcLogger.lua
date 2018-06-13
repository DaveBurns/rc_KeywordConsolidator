--[[================================================================================

Filename:           RcLogger.lua

Synopsis:           Provides file-based log functions via an extensible object.

Dependencies:       Lua 5.1
                    Lightroom 2 or emulations - see dependent modules in code below.

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
----------------------------------------------------------------------------------

Edit History:       2009-02-13: Enhanced by Rob Cole...

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


-- Define this module:
local Logger = {}


-- Evaluate pre-requisites:
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Import Lightroom dependencies:
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )
local LrFileUtils = RcModuleLoader.import( 'LrFileUtils' )

-- Load Rc dependencies:
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )





------------------
-- public methods:
------------------



--[[
        Synopsis:       Create a new logger.

        Notes:          No parameters => create out of thin air,
                        or pass a table with some logger fields
                        already assigned to start from.
--]]
function Logger:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end



--[[
        Initialize a newly created logger.

        Using explicit parameters is now deprecated, since smarts has been added
        to use proper functions for this, based on environment.

        funcForCreatingAllDirectories -- creates parent folder(s) - optional,
            but if omitted parent folder must exist before calling open.
--]]
function Logger:init( funcForParentPath, funcForIsExisting, funcForCreatingAllDirectories )
    if funcForParentPath ~= nil then
	    self.parentPath = funcForParentPath
    else
	    self.parentPath = LrPathUtils.parent
    end
    if funcForIsExisting ~= nil then
	    self.isExisting = funcForIsExisting
    else
	    self.isExisting = LrFileUtils.exists
    end
    if funcForCreatingAllDirectories ~= nil then
	    self.createAllDirectories = funcForCreatingAllDirectories
    else
	    self.createAllDirectories = LrFileUtils.createAllDirectories
    end
    self.verbose = false
end



--[[
        Synopsis:       Opens a log file for logging.

        Notes:          No-op if log-file-path is empty.
                        Error if log file parent directories can not be created or log file itself can not be opened.

        Parameters:     - log-file-path:        should be standardized before calling.
                        - verbose:              boolean
                        - overwrite:            true: specified file overwritten.
                                                false: log-file-name will be altered so new file.

        Reminder:       if overwrite flag is false, log file name will not be as specified - see log-file-path AFTER opening.

        Returns:        - false:    log-file-path not specified.
                        - true:     AOK.
--]]
function Logger:open( _logFilePath, _verbose, _overwrite )
	-- arg checks
	if not RcString.is( _logFilePath ) or ( string.len( _logFilePath ) < 2 ) then -- the '< 2' clause keeps the one-char path which was happening from causing problems ('\').
		-- error( "Log file path must be initialized." )
		return false
	end

    if _verbose then
        self.verbose = true
    end

    if _overwrite then
        self.logFilePath = _logFilePath
    else
        self.logFilePath = LrFileUtils.chooseUniqueFileName( _logFilePath )
    end

	local logFolderPath = self.parentPath( self.logFilePath )
    if RcString.is( logFolderPath ) then
    	local exists = self.isExisting( logFolderPath )
    	if exists then
    		-- good
    	else
            if self.createAllDirectories then
        		local created = self.createAllDirectories( logFolderPath ) -- doesn't throw errors, just returns false.
        		if created then
        			-- good
        		else
        			error( LOC( "$$$/RcLogger/ErrorMessages/Can not create log directories=Can not create log directories, path: ^1", logFolderPath ) )
        		end
            else
                error( LOC( "$$$/RcLogger/ErrorMessages/Log directory does not exist=Log directory does not exist and no function to create" ) )
            end
    	end
    end
	self.logFile, errorMessage = io.open( self.logFilePath, "w" ) -- does not throw errors, returns nil and error message upon failure.
	if self.logFile then
		-- header message logged in main func
	else
		error( LOC( "$$$/LrLogger/ErrorMessages/Unable to create log file=Unable to create log file: ^1, error message: ^2", self.logFilePath, errorMessage ) )
	end
	return true
end



--[[
        Synopsis:       Determine logger mode.

        Notes:          Presently only used by get-default-log-writer to only return one if verbosity match.
--]]
function Logger:isVerbose()
    return self.verbose
end



--[[
        Synopsis:   log a message segment, leaving the line open.

        Notes:      - no-op if logger not open.
                    - no-op if message is verbose and logger is not.
                    - flushed immediately.
--]]
function Logger:log( message, verbose )
    if verbose and not self.verbose then
        return
    end
	if self.logFile and (io.type(self.logFile) == 'file') then
		self.logFile:write( message or '' )
        self.logFile:flush()
	end
end



--[[
        Synopsis::      log a message and close out the line.
        
        Notes:          - no-op if logger not open.
                        - no-op if message is verbose and logger is not.
                        - flushed immediately.
--]]
function Logger:logLine( message, verbose )
    if verbose and not self.verbose then
        return
    end
	if self.logFile and (io.type(self.logFile) == 'file') then
		self.logFile:write( message or '' )
		self.logFile:write( '\n' )
        self.logFile:flush()
	end
end



--[[
        Synopsis:       Close log file permanently.
--]]
function Logger:close()
	if self.logFile and (io.type(self.logFile) == 'file') then
		self.logFile:close()
	end
end



--[[
        Synopsis:       Close log file temporarily.

        Notes:          Called before presenting dialog boxes so user can go
                        peruse the log file before deciding how to respond.
                        Not entirely sure this is necessary if log data is being
                        flushed every write, but it cam into being for good reason at the time.
--]]
function Logger:pause()
    self:close() -- OK as long as we're not deleting closed referenced to free them.
end



--[[
        Synopsis:       Re-open log file.

        Notes:          See logger-pause.
--]]
function Logger:continue()
    if self.logFile then -- was opened successfully previously.
    	self.logFile, errorMessage = io.open( self.logFilePath, "a" ) -- does not throw errors, returns nil and error message upon failure.
    	if self.logFile then
    		-- header message logged in main func
    	else
    		error( LOC( "$$$/LrLogger/ErrorMessages/Unable to append to log file=Unable to append to log file: ^1, error message: ^2", self.logFilePath, errorMessage ) )
    	end
    	return true
    end
end



return Logger -- return module table to requiring context.
-- The End.
