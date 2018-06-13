--[[================================================================================

Filename:           RcFtpUtils.lua

Synopsis:           Utilities that supplement Lightroom FTP functionality.

Dependencies:       - Lua 5.1
                    - Lightroom 2, or emulation of modules imported in code below.

Public Functions:   - RcFtpUtils.queryForPasswordIfNeeded
                    - RcFtpUtils.existsAsDir
                    - RcFtpUtils.existsAsFile
                    - RcFtpUtils.makeDirPath
                    - RcFtpUtils.makeFilePath
                    - RcFtpUtils.removeFile
                    - RcFtpUtils.removeEmptyDir
                    - RcFtpUtils.removeDirTree
                    - RcFtpUtils.assureAllRemoteDirectories
                    - RcFtpUtils.makeDir
                    - RcFtpUtils.putFile
                    - RcFtpUtils.getDirContents
                    - RcFtpUtils.calibrateClock

Notes:              ###2 - upgrade to be test-mode aware, like rc-file-utils
                           - include change to standard returns too.
                    
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

Edit History:       2009-09-16: Enhanced by Rob Cole.

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )
local LrStringUtils = RcModuleLoader.import( 'LrStringUtils' )
local LrDate = RcModuleLoader.import( 'LrDate' )
local LrFtp = RcModuleLoader.import( 'LrFtp' )
local LrDialogs = RcModuleLoader.import( 'LrDialogs' )
local LrTasks = RcModuleLoader.import( 'LrTasks' )
local LrFunctionContext = RcModuleLoader.import( 'LrFunctionContext' )
local LrBinding = RcModuleLoader.import( 'LrBinding' )
local LrView = RcModuleLoader.import( 'LrView' )


local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcNumber = RcModuleLoader.loadRcModule( 'RcNumber' )
local RcDateTimeUtils = RcModuleLoader.loadRcModule( 'RcDateTimeUtils' )
local RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )


local RcFtpUtils = {}



---------------------
-- Private variables:
---------------------


local _thisYear = LrDate.timestampToComponents( LrDate.currentTime() ) -- year is first return value. Used when year not present in dir-entry timestamp.
local monthTable = nil -- initialization deferred until first use.



--------------------
-- Public variables:
--------------------

RcFtpUtils.remoteClockOffset = {} -- set this value externally for each server if desired (which will circumvent clock calibration), this will be subtracted from time parsed from remote file directory entries.



---------------------
-- Private functions:
---------------------



-- debugging support
local _moduleName = "RcFtpUtils"
local function _debugTrace( id, info )
    assert( RcString.is (_moduleName), "Module name must be defined." )
    RcUtils.debugTrace( _moduleName .. ":" .. id, info )
end




--------------------------------------------------------------------------------
--      The following functions were invented to aid debugging.
--      Although they are theoretically no longer necessary,
--      they provide a debugging focal point and protect against
--      adobe oopsing on the path like they did in ftp-conn-exists.
--
--      PS - My experience has been that some of the FTP functions can take
--      many minutes to return if there is trouble with the connection and/or server.
--      This led me to believe they were hung, but it now appears they will eventually return.
--
--      local _{name} functions that only take a name and not a path must have the path set
--      before calling, and path is "guaranteed" to be same upon return.
--------------------------------------------------------------------------------



--[[
        Synopsis:       Determines if an entity of any type exists at the set path with the specified name.

        Motivation:     - ftp-conn-exists started changing the path and goofing things up - this routine detects
                          the condition, responds appropriately, and restores the original path to the ftp connection.
                        - operates in protected mode, although I'm not sure its necessary, since ftp-conn-exists
                          returns nil, err-msg - it may be operating in protected mode without being documented as such.
                          Still, the other functions explicitly state protect mode and ftp-conn-exists does not.
                          This function provides cheap protected-mode insurance.

        Returns:        - 'file', nil:          exists as file, no comment.
                        - 'directory', nil:     exists as directory, no comment.
                        - false, nil:           does not exist, no comment.
                        - nil, comment:         who knows?
--]]
local function _exists( ftpConn, name )
    local existsAs, qualification
    local t = ftpConn.path
    local s, r1, r2 = LrTasks.pcall( ftpConn.exists, ftpConn, name ) -- ftp-conn path changed by this call - this was the culprit
        -- in past difficulties, now remedied by restoring the path at the end of this function.
    if s then -- pcall completed without fatal exception.
        -- r1 (required) & r2 (optional) are values returned by ftp-conn-exists method.
        if r1 ~= nil then -- ftp existence function completed without ftp error.
            if type( r1 ) == 'string' then -- 'file' or 'directory' exists.
                assert( r1 == 'file' or r1 == 'directory', LOC( "$$$/X=Illegal string returned by ftp-conn-exists method: ^1", r1 ) )
                existsAs = r1
            elseif type( r1 ) == 'boolean' then
                assert( r1 == false, LOC( "$$$/X=1st value returned by ftp-conn-exists is true - not expected." ) )
                existsAs = false
            else
                error( LOC( "$$$/X=1st value returned by ftp-conn-exists has unexpected type: ^1", type( r1 ) ) )
            end
        else -- ftp error
            assert( r2 ~= nil and type( r2 ) == 'string', LOC( "$$$/X=2nd value returned by ftp-conn-exists is supposed to be an error message, its: ^1", r2 ) )
            existsAs = nil
            qualification = LOC( "$$$/X=FTP error checking for existence of file named (^1) in directory (^2), message: ^3", name, t, r2 )
        end
    else
        assert( r1 ~= nil and type( r1 ) == 'string', LOC( "$$$/X=2nd value returned by pcall is supposed to be an error message, its: ^1", r1 ) )
        existsAs = nil
        qualification = LOC( "$$$/X=Unable to determine if remote file exists, more: ^1", r1 ) -- r1 is pcall error message.
    end
    if ftpConn.path ~= t then -- it appears that exists method has walked back the path until something does exist
        -- although that is useful, and is essentially what I'm doing in assure-remote-directories,
        -- it isn't how it used to work, nor is it how its documented to work. ###4 remove this comment if does not happen by 2011.
        -- maybe it was due to bug thats fixed now.
        if existsAs then
            -- RcUtils.logWarning( LOC( "$$$/X=ftp-conn-exists method return value being overridden to false based on path change." ) ) - warning not warranted: its the right thing to do.
                -- I could conceivably recode to take advantage of exists method to determine where I need to start creating directories, but if it ain't broke... (and if it ain't documented...)
            existsAs = false -- override the possibly bogus return value that results when a parent exists but not the target.
        end
    -- else
    end
    ftpConn.path = t
    return existsAs, qualification
end



--[[
        Synopsis:           Remove a file.

        Returns:            - true, nil:        worked, no-comment.
                            - true, comment:    reserved for future test-mode awareness. ###2
                            - false, comment:   failed, and here's why...

        Notes:              *** WARNING: Based on some of my previous comments about ftp-conn-p-remove-file, the second
                            return value seems unreliable.

                            I dont think this function is called unless the file is known to exist.
                            Not sure what happens if it does not.

                            This function checks ftp-conn-p-remove-file return values very thoroughly but does not
                            confirm removal. Do this confirmation in calling context if confirmation desired.
--]]
local function _pRemoveFile( ftpConn, name )
    local status, qualification
    local t = ftpConn.path
    local r, dummy = ftpConn:pRemoveFile( name ) -- the guts.
    assert( ftpConn.path == t, "ftp-conn:p-remove-file changed paths" )
    if r ~= nil then
        if type( r ) == 'boolean' then
            if r == true then -- call completed without exception.

                status = true -- for the purposes of this program, assume if call completed, the file was removed,
                    -- even if confirmation was not attained. If there's a problem putting a file in its place
                    -- let the error be handled there. Also, calling context can look at qualifier to see if 
                    -- file removal truly happened and confirmed.

                -- theoretically its possible that the call completed without exception, but the file was not actually removed.
                -- in which case the second return value is suppossedly false.
                if dummy ~= nil then
                    if type( dummy ) == 'boolean' then
                        if dummy == true then
                            -- file removal confirmed.
                        else
                            -- file removal not-confirmed.
                            qualification = LOC( "$$$/X=FTP error confirming removal of file named ^1 from dir: ^2", name, t )
                        end
                    else
                        assert( type( dummy ) == 'string', LOC( "$$$/X=2nd value returned by ftp-conn-p-remove-file has bad type: ^1", type( dummy ) ) )
                    end
                else
                    -- error( "2nd value returned by ftp-conn-p-remove-file is nil" ) - lr-api doc says this is boolean or string: doc is wrong - its nil.
                end
            else
                status = false
                qualification = LOC( "$$$/X=FTP error trying to remove file named ^1 from dir: ^2, more info: ^3", name, t, RcLua.toString( dummy ) )
            end
        else
            assert( type( r ) == 'string', LOC( "$$$/X=1st value returned by ftp-conn-p-remove-file has bad type: ^1", type( r ) ) )
            status = false
            qualification = LOC( "$$$/X=FTP error trying to remove file named ^1 from dir: ^2, error message: ^3", name, t, r )
        end
    else
        error( "1st value returned by ftp-conn-p-remove-file is nil" )
    end
    ftpConn.path = t
    return status, qualification
end



--[[
        Synopsis:           Remove a directory known to exist and be empty.

        Returns:            - true, nil:        worked, no-comment.
                            - true, comment:    reserved for future test-mode awareness. ###2
                            - false, comment:   failed, and here's why...

        Notes:              *** WARNING: Based on some of my previous comments about ftp-conn-p-remove-file, the second
                            return value seems unreliable.

                            I dont think this function is called unless the directory is known to exist.
                            Not sure what happens if it does not.

                            This function checks ftp-conn-p-remove-directory return values very thoroughly but does not
                            confirm removal. Do this confirmation in calling context if confirmation desired.
--]]
local function _pRemoveEmptyDirectory( ftpConn, name )
    local status, qualification
    local t = ftpConn.path
    local r, dummy = ftpConn:pRemoveDirectory( name ) -- the guts - dir must exist, and be empty.
    assert( ftpConn.path == t, "ftp-conn:p-remove-directory changed paths" )
    if r ~= nil then
        if type( r ) == 'boolean' then
            if r == true then -- call completed without exception.

                status = true -- for the purposes of this program, assume if call completed, the directory was removed,
                    -- even if confirmation was not attained. If there's a problem putting a directory in its place
                    -- let the error be handled there. Also, calling context can look at qualifier to see if 
                    -- directory removal truly happened and confirmed.

                -- theoretically its possible that the call completed without exception, but the directory was not actually removed.
                -- in which case the second return value is suppossedly false.
                if dummy ~= nil then
                    if type( dummy ) == 'boolean' then
                        if dummy == true then
                            -- directory removal confirmed.
                        else
                            -- directory removal not-confirmed.
                            qualification = LOC( "$$$/X=FTP error confirming removal of directory named ^1 from dir: ^2", name, t )
                        end
                    else
                        assert( type( dummy ) == 'string', LOC( "$$$/X=2nd value returned by ftp-conn-p-remove-directory has bad type: ^1", type( dummy ) ) )
                    end
                else
                    -- error( "2nd value returned by ftp-conn-p-remove-directory is nil" ) - lr-api doc says this is boolean or string: doc is wrong - its nil,
                        -- or at least p-remove-file returns nil - I assume p-remove-directory does same thing.
                end
            else
                status = false
                qualification = LOC( "$$$/X=FTP error trying to remove directory named ^1 from dir: ^2, more info: ^3", name, t, RcLua.toString( dummy ) )
            end
        else
            assert( type( r ) == 'string', LOC( "$$$/X=1st value returned by ftp-conn-p-remove-directory has bad type: ^1", type( r ) ) )
            status = false
            qualification = LOC( "$$$/X=FTP error trying to remove directory named ^1 from dir: ^2, error message: ^3", name, t, r )
        end
    else
        error( "1st value returned by ftp-conn-p-remove-directory is nil" )
    end
    ftpConn.path = t
    return status, qualification
end



--[[
        Synopsis:       Get the text contents of a directory.

        Notes:          Calling context must set path in ftp-conn before calling.
--]]
local function _getDirContents( ftpConn )
    local contents, qualification
    local t = ftpConn.path
    local s, r = LrTasks.pcall( ftpConn.getContents, ftpConn, "" ) -- getting file contents of empty name means get directory contents.
    if s then
        contents = r
    else
        contents = nil
        qualification = LOC( "$$$/X=FTP error getting contents from remote directory: ^1", t )
    end
    assert( ftpConn.path == t, "ftp-conn:get-contents changed paths" )
    ftpConn.path = t
    return contents, qualification
end



--[[
        Synopsis:       Write local file to remote host.

        Returns:        - true, nil:        File put, no comment.
                        - true, comment:    reserved for test-mode.
                        - false, comment:   failed.
--]]
local function _putFile( ftpConn, localPath, name )
    local t = ftpConn.path
    local status, qualification
    local s, r = LrTasks.pcall( ftpConn.putFile, ftpConn, localPath, name ) -- put-file throws error upon failure.
        -- no return value specified, although my experience has been that it sometimes returns "OK".
    if s then
        status = true
    else
        status = false
        qualification = LOC( "$$$/X=FTP error putting local file (^1) to remote dir (^2), more: ^3", localPath, t, RcLua.toString( r ) )
    end
    assert( ftpConn.path == t, "ftp-conn:put-file changed paths" ) -- reminder that this method doesn't change the path.
    ftpConn.path = t -- emphasis/cheap-insurance? - I'm afraid to take it out.
    return status, qualification
end



--[[
        Synopsis:       Create remote directory.

        Returns:        - true, nil:        Directory created, no comment.
                        - true, comment:    Pretend directory created - may not actually have been, due to test-mode*, or lack of confirmation.
                        - false, comment:   failed.

        * Test mode not yet implemented.
--]]
local function _makeDirectory( ftpConn, name )
    local status, qualification
    local t = ftpConn.path
    local s, r = LrTasks.pcall( ftpConn.makeDirectory, ftpConn, name )
    if s then
        if r then
            status = true
        else
            status = true -- ###2 in order to keep the wheel turning, calling context may assume
                -- that the directory was created, even though not confirmed. When it subsequently tries to put files into the directory,
                -- it may have problems and log errors. It can always look at qualification to see if it was confirmed.
            qualification = LOC( "$$$/X=FTP unable to confirm creation of remote directory named ^1, in parent dir: ^2", name, t )
        end
    else
        status = false
        qualification = LOC( "$$$/X=FTP error creating remote directory named ^1, in parent dir: ^2", name, t )
    end
    assert( ftpConn.path == t, "ftp-conn:make-directory changed paths" )
    ftpConn.path = t
    return status, qualification
end



--[[
        Synopsis:       Determines if directory SEEMS to exist.

        Notes:          My experience has been that answer is not always correct, thus its worth
                        double checking and waiting if it is expected, in calling context.

        Returns:        true, nil:      directory exists, no comment.
                        false, nil:     directory does not exist, no comment.
                        nil, comment:   who knows.
--]]
local function _existsAsDir( ftpConn, name )
    local existsAs, message = _exists( ftpConn, name )
    if existsAs then
        assert( type( existsAs ) == 'string', LOC( "$$$/X=1st value returned by -exists function has unexpected type: ^1", type( existsAs ) ) )
        if existsAs == 'directory' then
            return true
        elseif existsAs == 'file' then
            -- return false, "directory is a file"
            error( LOC( "$$$/X=Directory entry named (^1) in (^2) should either not exist, or be a directory, but its a file.", name, ftpConn.path ) )
        else
            error( LOC( "$$$/X=1st value (string) returned by -existsAs function not expected: ^1", existsAs ) )
        end
    else -- may be false or nil, message.
        if existsAs == nil then
            assert( RcString.is( message ), "Expected error message to be returned by -exists function." )
            return nil, LOC( "$$$/X=Unable to ascertain if directory existsAs, error message: ^1", message )
        else
            assert( (type( existsAs ) == 'boolean') and (existsAs == false), LOC( "$$$/X=1st value returned by -existsAs function unexpected: ^1", RcLua.toString( existsAs ) ) )
            return false
        end
    end
end



--[[
        Synopsis:       Determine if specified file SEEMS to exist.

        History:        In the beginning, I assumed lr-ftp-exists function returned 'file', 'directory', or false/nil if neither.
                        Code like "if exists and is 'file'" ... was normally enough, but I've had such strange errors, with this
                        function returning inconsistent results that it seemed to warrant a wrapper. It really just makes sure
                        assumptions about return values are correct, and reinforces the distinction between existence check failure
                        and item determined not to exist. It also reinforces the fact that more needs to be done to reliably detect
                        remote file/dir.

        Notes:          My experience has been that ftp-conn-exists method answer is not always correct, thus its worth
                        double checking and waiting if it if expected, in calling context.
--]]
local function _existsAsFile( ftpConn, name )
    local existsAs, message = _exists( ftpConn, name )
    if existsAs then
        assert( type( existsAs ) == 'string', LOC( "$$$/X=1st value returned by -exists function has unexpected type: ^1", type( existsAs ) ) )
        if existsAs == 'file' then
            return true
        elseif existsAs == 'directory' then
            -- return false, "file is a directory"
            error( LOC( "$$$/X=Directory entry named (^1) in (^2) should either not exist, or be a file, but its a directory.", name, ftpConn.path ) )
        else
            error( LOC( "$$$/X=1st value (string) returned by -existsAs function not expected: ^1", existsAs ) )
        end
    else -- may be false or nil, message.
        if existsAs == nil then
            assert( RcString.is( message ), "Expected error message to be returned by -exists function." )
            return nil, LOC( "$$$/X=Unable to ascertain if directory existsAs, error message: ^1", message )
        else
            assert( ( type( existsAs ) == 'boolean') and (existsAs == false), LOC( "$$$/X=1st value returned by -existsAs function unexpected: ^1", RcLua.toString( existsAs ) ) )
            return false
        end
    end
end



--[[
        Synopsis:       Waits for a directory to positively exist.

        Notes:          - Called when a directory is expected to exist, but confirmation suggests it does not.
                        - Trys each second for 10 seconds, then gives up.

        Returns:        true, nil:      directory exists, no comment.
                        false, nil:     directory does not exist, no comment.
                        nil, comment:   who knows.
--]]
local function _waitForDirectory( ftpConn, name )
    local retryCount = 10
    local retryDelay = 1
    local sts, msg = _existsAsDir( ftpConn, name ) -- true => exists-as-dir, false means doesn't, but nil means dunno, and is accompanied by msg.
    while( not RcLua.isTrue( sts ) and ( retryCount > 0 ) ) do
        RcUtils.logWarning( "Waiting for directory, name: " .. name .. ", location: " .. ftpConn.path )
        LrTasks.sleep( retryDelay )
        sts, msg = _existsAsDir( ftpConn, name )
        retryCount = retryCount - 1
    end
    return sts, msg
end



--[[
        Synopsis:       Waits for a file to positively exist.

        Notes:          - Called when a file is expected to exist, but confirmation suggests it does not.
                        - Trys each second for 10 seconds, then gives up.

        Returns:        true, nil:      file exists, no comment.
                        false, nil:     file does not exist, no comment.
                        nil, comment:   who knows.
--]]
local function _waitForFile( ftpConn, name )
    local retryCount = 10
    local retryDelay = 1
    local sts, msg = _existsAsFile( ftpConn, name ) -- true => is file, false => is not, nil => dunno, and is accompanied by msg.
    while( not RcLua.isTrue( sts ) and ( retryCount > 0 ) ) do
        RcUtils.logWarning( "Waiting for file, name: " .. name .. ", location: " .. ftpConn.path )
        LrTasks.sleep( retryDelay )
        sts, msg = _existsAsFile( ftpConn, name )
        retryCount = retryCount - 1
    end
    return sts, msg
end



--[[
        Synopsis:       Waits for a directory to positively not exist.

        Motivation:     There is room for some error in directory-deletion/existence checking.
                        This function waits for the dust to settle so calling context doesn't
                        make any rash decisions.

        Notes:          - Typically called when a directory has been deleted, supposedly successfully - this confirms its deletion.
                        - Its possible(?) that if I just called lr-ftp functions more blindly they would take care of themselves,
                          however now that I've got into the game of pre-checking/post-checking, there's no turning back...

        Returns:        - true, nil:                directory certainly gone, no comment.
                        - false, error message:     can't be certain.
--]]
local function _waitForDirToDisappear( ftpConn, name )
    local retryCount = 10
    local retryDelay = 1
    local ret1 = nil
    local ret2 = nil
    repeat
        ret1, ret2 = _existsAsDir( ftpConn,  name )
        if ret1 ~= nil and type( ret1 ) == 'boolean' and ret1 == false then -- existence determined, existence negative.
            return true -- item disappeared.
        end
        LrTasks.sleep( retryDelay )
        retryCount = retryCount - 1
    until retryCount == 0
    return false, "item wont go away, trouble: " .. RcLua.toString( ret2 )
end



--[[
        Synopsis:       Waits for a file to positively not exist.

        Motivation:     There is room for some error in file-deletion/existence checking.
                        This function waits for the dust to settle so calling context doesn't
                        make any rash decisions.

        Notes:          - Typically called when a file has been deleted, supposedly successfully - this confirms its deletion.
                        - Its possible(?) that if I just called lr-ftp functions more blindly they would take care of themselves,
                          however now that I've got into the game of pre-checking/post-checking, there's no turning back...

        Returns:        - true, nil:                file certainly gone, no comment.
                        - false, error message:     can't be certain.
--]]
local function _waitForFileToDisappear( ftpConn, name )
    local retryCount = 10
    local retryDelay = 1
    local ret1 = nil
    local ret2 = nil
    repeat
        ret1, ret2 = _existsAsFile( ftpConn,  name )
        if ret1 ~= nil and type( ret1 ) == 'boolean' and ret1 == false then -- existence determined, existence negative.
            return true -- item disappeared.
        end
        LrTasks.sleep( retryDelay )
        retryCount = retryCount - 1
    until retryCount == 0
    return false, "item wont go away, trouble: " .. RcLua.toString( ret2 )
end



--[[
        Synopsis:       Sets ftp-conn path to PARENT of full-path,
                        and returns leaf-name.

        Motivation:     lr-ftp utils take a name, and operate on the set path.
                        This function sets it.

        Notes:          At this point, I think I would prefer if an ftp root path
                        were set in an ftp object, then all methods were passed
                        a sub-path, then each gut wrapper method sets the full path before
                        each call to lr-ftp gut methods - this would circumvent the problem
                        if setting the path one to few times... maybe some day - see elare-framework.
==]]
local function _setPath( ftpConn, fullPath )
    if type( fullPath ) == 'string' then
        local path = LrPathUtils.parent( fullPath )
        local name = LrPathUtils.leafName( fullPath )
        ftpConn.path = path
        -- RcUtils . hogMessageLine( "Path set to: " .. ftpConn.path .. ", returning name: " .. name, RcUtils.VERBOSE )
        return name
    else
        error( "set-path not getting a string for full-path: " .. RcLua.toString( fullPath ) )
    end
end



--[[
        Synopsis:       Remove a directory - whether empty or not. - If directory has subdirectories or files, they will be removed also.
                        Called recursively to do so.

        Notes:          - You can not remove the root dir.
                        - This function WILL change the path in ftp-conn (like all functions that are passed a path).
                        - This function logs deleted directories in verbose mode. - This is a departure from the
                          "leave logging to calling context" convention. ###4 - Could create a table of removed sub-directories
                          and files instead.

        Returns:        - true, nil:                directory removed or didn't exist in the first place.
                        - false, error-message:     failed.

--]]
local function _removeDirTree( ftpConn, remotePath )
    local name = _setPath( ftpConn, remotePath )
    RcUtils.logMessageLine( "Removing remote directory: " .. remotePath, RcUtils.VERBOSE ) -- I guess this is sometimes not considered verbose in calling context(?) ###4
    local sts1, sts2
    local folderTable, fileTable = RcFtpUtils.getDirContents( ftpConn, remotePath ) -- changes path setting.
    if folderTable == nil then
        return false, fileTable -- ft is qual/err-msg.
    end
    local fname
    for i,v in ipairs( fileTable ) do
        fname = v.leafName
        sts1, sts2 = RcFtpUtils.removeFile( ftpConn, RcFtpUtils.makeFilePath( remotePath, fname ) )
        if sts1 == true then -- file removed
            RcUtils.logMessageLine( "Remote file deleted: " .. fname, RcUtils.VERBOSE )
        else
            return false, sts2
        end
    end
    for i,v in ipairs( folderTable ) do
        fname = v.leafName
        sts1, sts2 = _removeDirTree( ftpConn, RcFtpUtils.makeDirPath( remotePath, fname ) )
        if sts1 == true then
            RcUtils.logMessageLine( "Remote directory deleted: " .. fname, RcUtils.VERBOSE )
        else
            return false, sts2
        end
    end
    return RcFtpUtils.removeEmptyDir( ftpConn, remotePath )
end



--[[
        Synopsis:       Get time as number from *odd components.

        Notes:          - *month component is a string, the rest are numbers.
                        - ###4 could translate month in calling context and call
                          lr-date function from there as well.
--]]
local function _getTime( year, _month, day, hour, minute, second )
    if monthTable == nil then
        monthTable = {}
        monthTable["Jan"] = 1
        monthTable["Feb"] = 2
        monthTable["Mar"] = 3
        monthTable["Apr"] = 4
        monthTable["May"] = 5
        monthTable["Jun"] = 6
        monthTable["Jul"] = 7
        monthTable["Aug"] = 8
        monthTable["Sep"] = 9
        monthTable["Oct"] = 10
        monthTable["Nov"] = 11
        monthTable["Dec"] = 12
    end
    local month = monthTable[_month]
    -- return RcDateTimeUtils.getTime( year, month, day, hour, minute, second ) - works
    return LrDate.timeFromComponents( year, month, day, hour, minute, second, 0 ) -- does exactly same thing.
end



--[[
		Synopsis:			Parse a directory entry that is assumed to be in windows format, for example:

									02-12-10  04:13AM       <DIR>          1980s (4 tokens)

		Notes: 				See calling context header for more info.
--]]
local function _parseWindowsDirEntry( dirEntry )
    local tokens = RcString.tokenize( dirEntry, 4 ) -- returns tokens 1-4, where 4th token is the remainder.
	local dateStr = tokens[1]
    local timeStr = tokens[2]
	local typeStr = tokens[3]
	local nameStr = tokens[4]
	local sizeStr
	if typeStr == "<DIR>" then
		typeVal = 'D'
		sizeStr = nil
	else
		-- app:logInfo( "assuming file: " .. typeStr ) -- will be a number.
		typeVal = 'f'
		sizeStr = typeStr
	end

	local year, month, day = RcDateTimeUtils.parseMmDdYyDate( dateStr )
	if type( year ) == 'string' then
		return nil
	end

	local hour, minute = RcDateTimeUtils.parseHhMmAmPmTime( timeStr )
	if type( hour ) == 'string' then
		return nil
	end

	local leafName = tokens[4]

	-- RcUtils.logMessageLine( LOC( "$$$/X=parsed windows date-time: ^1-^2-^3  ^4:^5", year, month, day, hour, minute ) )

	local datetime = LrDate.timeFromComponents( year, month, day, hour, minute, 0, 0 ) -- first zero => second, second zero => UTC offset in seconds for time-zone.
		-- note: it does not matter what UTC offset is, since we don't care whether the time is right - whatever might get added when we calibrate will get subtracted
		-- when we compute difference in local versus remote timestamp.

    local size = RcNumber.numberFromString( sizeStr ) -- robustly handles nil, null, and non-numbers...

	return typeVal, datetime, leafName, size

end



--[[
        Synopsis:       Parse a directory entry as returned by get-file-contents - may be unix or windows format.

        Example dirEntries:

                        Unix:       drwxrwxr-x   3 rcole    rcole        4096 Aug 25 21:46 LrFlashGalleries (9 tokens)

                        Windows:    Once upon a time, it appeared to return same format as unix, much to my surprise!
									Now, it seems to be in this format:

									02-12-10  04:13AM       <DIR>          1980s (4 tokens)

        Returns values: 1 - type:       'D' - directory, 'f' - file, nil - ?
                        2 - date-time:  number
                        3 - leaf-name:  directory or file name, excluding path, including extension.

        Notes:          If dir entry format changes, so must this function. ###4
--]]
local function _parseDirEntry( dirEntry )

	-- RcUtils.logMessageLine ("dir entry: " .. dirEntry )

    local tokens = RcString.tokenize( dirEntry, 2 )
    local typeString = tokens[1]
    local typeVal
    if RcString.is( typeString ) then
        local firstChar = RcString.getChar( typeString, 1 )
        if firstChar == 'd' then
            typeVal = 'D'
        elseif firstChar == '-' then
            typeVal = 'f'
        else -- assume windows format
            return _parseWindowsDirEntry( dirEntry ) -- warning, last tokens need to be reconstituted into a string.
        end
    else
        typeVal = nil
    end
	-- I think the reason I didn't move this code to rc-date-time utils is that it is only likely to be seen in this format in a remote directory entry.
    tokens = RcString.tokenize( dirEntry, 9 ) -- returns tokens 1-9, where 9th token is the remainder.
    local dateString = tokens[8]
    local year, month, day, hour, minute, second
    second = 0
    local colonStarts = 0
    local colonEnds = 0
    if RcString.is( dateString ) then
        colonStarts, colonEnds = string.find( dateString, ':', 1, true )
        if colonStarts then
            year = _thisYear -- not exactly correct: means it was in the last 180 days, so to detect if that means this-year or last-year, we try this year, and if its in the future, it musta shoulda been last year!
            local hourString = string.sub( dateString, colonStarts - 2, colonStarts - 1 )
            if RcString.is( hourString ) then
                hour = tonumber( hourString )
                if hour == nil then
                    hour = 0
                end
            else
                hour = 0
            end
            local minuteString = string.sub( dateString, colonEnds + 1, colonEnds + 2 )
            if RcString.is( minuteString ) then
                minute = tonumber( minuteString )
                if minute == nil then
                    minute = 0
                end
            else
                minute = 0
            end
        else
            if RcString.is( dateString ) then
                year = tonumber( dateString )
                if year == nil then
                    year = 0
                end
            else
                year = 0
            end
            hour = 0
            minute = 0
        end
    else
        RcUtils.logWarning( "Unable to parse date string from dir contents." )
        year = 0
        -- month = "Jan"
        -- day = 1
        hour = 0
        minute = 0
    end
    month = tokens[6] -- uses string
    day = tonumber( tokens[7] )

    local timeVal = _getTime( year, month, day, hour, minute, second )
    if colonStarts then
        local rightNow = LrDate.currentTime()
        if (timeVal - 720) > rightNow then -- if file timestamp is in the future, it musta shoulda been last year - so make correction - 2 minute fudge factor just for grins :-)
            timeVal = _getTime( year - 1, month, day, hour, minute, second )
        end
    end

    local size = RcNumber.numberFromString( tokens[5] ) -- *** this so far untested, need unix server to test.

    local leafName = tokens[9]
    return typeVal, timeVal, leafName, size
            
    -- return typeVal, tokens[6] .. ' ' .. tokens[7] .. ' ' .. tokens[8], tokens[9]
end





--------------------
-- Public functions:
--------------------



--[[
        Synopsis:       Serves same purpose as Lr-FTP version - prompt user for password if not provided in the settings.

        Motivation:     Lightroom's version just says "gimme a password" without stating what the password is for.
                        This is one of my all time pet peeves in modern software - I suppose if you are the kind
                        of person that uses the same password for everything and dont care what its for when you
                        are asked for one, it doesn't much matter - I am not that kind of person.

                        Its completely unacceptable for Photooey since passwords may be needed for two different servers.

        Notes:          This function indicates the password request is for ftp on specified server.
--]]
function RcFtpUtils.queryForPasswordIfNeeded( ftpSettings )

    if RcString.is( ftpSettings.password ) then
        return true
    -- else present dialog box - if user cancels it ftp-settings password will remain empty.
    end

    LrFunctionContext.callWithContext( "queryForPasswordIfNeeded", function( context )

        props = LrBinding.makePropertyTable( context )
        props.password = ''
        local f = LrView.osFactory()

        local passwordLabel = f:static_text{
			alignment = "left",
			-- width = LrView.share "label_width",
			title = "FTP Password: ",
        }

        local passwordField = f:password_field{
            immediate = false,
            value = LrView.bind{
                key = 'password',
                bind_to_object = props,
            }
        }

        local c = f:column{
			spacing = f:dialog_spacing(),
            f:row{
                f:static_text{
        			alignment = "left",
        			-- width = LrView.share "label_width",
        			title = ftpSettings.server,
                },
            },
            f:row{
                fill_horizontal = 1,
                passwordLabel,
                passwordField,
            },
        }

        props:addObserver( 'password', function()
            ftpSettings.password = passwordField.value
            -- RcUtils . hogMessageLine( "Password set to " .. ftpSettings.password ) - dont put password in log file!
        end )

        LrDialogs.presentModalDialog{
            title = inputMsg,
            contents = c,
        }
            
    end )

end



--[[
        Synopsis:       Determines if file exists, and will double-check if no expectation,
                        waits for it to disappear if its supposed to be gone (like when it
                        was just deleted), or waits for it to be present if expected to be
                        there (like if it was just put out there, or detected via get-dir-contents...).
        

        Returns:        - true, nil: file exists, for sure.
                        - false, nil: file does not exist, for sure.
                        - nil, error-message: uncertain, see error message.
--]]    
function RcFtpUtils.existsAsFile( ftpConn, name, expected )
    if expected ~= nil then
        assert( type( expected ) == 'boolean', "expected not boolean" )
    end
    local existsAsFile, orNot = _existsAsFile( ftpConn, name )
    if existsAsFile ~= nil then -- answer definitive
        if existsAsFile == true then
            if expected ~= nil then
                if expected then
                    return true
                else
                    local sts1, sts2 = _waitForFileToDisappear( ftpConn, name )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations
                existsAsFile, orNot = _existsAsFile( ftpConn, name ) -- return second stab, since it may be more accurate than first stab.
                return existsAsFile, orNot
            end
        else -- file does not seem to exist.
            if expected ~= nil then
                if expected then
                    local sts1, sts2 = _waitForFile( ftpConn, name )
                    return sts1, sts2 -- wait
                else
                    local sts1, sts2 = _waitForFileToDisappear( ftpConn, name )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations.
                existsAsFile, orNot = _existsAsFile( ftpConn, name ) -- return second stab, since it may be more accurate than first stab.
                return existsAsFile, orNot
            end
        end
    else -- unable to ascertain files existence.
        if expected ~= nil then
            if expected then
                local sts1, sts2 = _waitForFile( ftpConn, name )
                return sts1, sts2
            else
                local sts1, sts2 = _waitForFileToDisappear( ftpConn, name )
                if sts1 then -- item gone
                    return false
                else
                    return true
                end
            end
        else -- no expectations.
            existsAsFile, orNot = _existsAsFile( ftpConn, name ) -- return second stab, since it may be more accurate than first stab.
            return existsAsFile, orNot
        end
    end
end



--[[
        Synopsis:       Determines if dir exists, and will double-check if no expectation,
                        waits for it to disappear if its supposed to be gone (like when it
                        was just deleted), or waits for it to be present if expected to be
                        there (like if it was just put out there, or detected via get-dir-contents...).

        Returns:        - true, nil: dir exists, for sure.
                        - false, nil: dir does not exist, for sure.
                        - nil, error-message: uncertain, see error message.
--]]    
function RcFtpUtils.existsAsDir( ftpConn, name, expected )
    local dirExists, orNot = _existsAsDir( ftpConn, name )
    if dirExists ~= nil then -- answer definitive
        if dirExists == true then -- directory seems to exist
            if expected ~= nil then
                assert( type( expected ) == 'boolean', "expected parameter should be boolean" )
                if expected then
                    return true
                else
                    local sts1, sts2 = _waitForDirToDisappear( ftpConn, name )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations
                dirExists, orNot = _existsAsDir( ftpConn, name ) -- return second stab, since it may be more accurate than first stab.
                return dirExists, orNot
            end
        else -- dir does not seem to exist.
            if expected ~= nil then
                assert( type( expected ) == 'boolean', "expected parameter should be boolean 2" )
                if expected then
                    local sts1, sts2 = _waitForDirectory( ftpConn, name )
                    return sts1, sts2
                else
                    local sts1, sts2 = _waitForDirToDisappear( ftpConn, name )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations.
                dirExists, orNot = _existsAsDir( ftpConn, name ) -- return second stab, since it may be more accurate than first stab.
                return dirExists, orNot
            end
        end
    else -- unable to ascertain dir existence.
        if expected ~= nil then
            assert( type( expected ) == 'boolean', "expected parameter should be boolean 3" )
            if expected then
                local sts1, sts2 = _waitForDirectory( ftpConn, name )
                return sts1, sts2
            else
                local sts1, sts2 = _waitForDirToDisappear( ftpConn, name )
                if sts1 then -- item gone
                    return false
                else
                    return true
                end
            end
        else -- no expectations.
            dirExists, orNot = _existsAsDir( ftpConn, name ) -- return second stab, since it may be more accurate than first stab.
            return dirExists, orNot
        end
    end
end



--[[
        Synopsis:       Create a full path to a remote directory from parent and child sub-paths.

        Notes:          This function takes a root-dir-path and sub-dir-path and returns
                        a full-path to a dir for ftp purposes.
        
                        Preferred over lightroom's version when you dont want to run the risk of a slash prefixed child-path
                        being interpreted as an absolute path, instead of a relative path. Also, makes sure input paths are
                        interpreted correctly regardless of source path origins (e.g. local windows dir that contains backslashes),
                        and makes sure result path is properly formatted for FTP, meaning only forward slashes, no backslashes.
                    
                        Reminder: the Lr-Ftp function only checks if child-path begins with a forward slash,
                        and if so root-path is ignored. It interprets backslash prepended child-paths as true children.
                        Also, although Lr-Ftp is
                        surprisingly tolerant of appending windows backslashed paths to traditionaly ftp forward
                        slashed paths, I prefer the asthetic of properly formatted ftp paths, and in so doing, this function may
                        even prevent a bug in the future.

        Returns:        Full path, no excuses, trailing slash. - No guarantee its to a real directory: garbage in = garbage out.
--]]
function RcFtpUtils.makeDirPath( _rootPath, _subPath )
    assert( _rootPath ~= nil, "no root-path to make-dir-path" )
    assert( _subPath ~= nil, "no sub-path to make-dir-path" )
    local childPath = RcString.replaceBackSlashesWithForwardSlashes( _subPath )
    local rootPath = RcString.replaceBackSlashesWithForwardSlashes( _rootPath )
    local firstChar = RcString.getFirstChar( childPath )
    if firstChar == '/' then
        childPath = childPath.sub( childPath, 2 ) -- bypass the starting slash, since we want this interpreted as a sub-path, not a root-path.
    -- else good
    end
    return LrFtp.appendFtpPaths( rootPath, childPath ) -- this makes sure there's a trailing slash at the end, and one separator between.
        -- Best not to muck with the front of root-path, since it may have a drive spec.
end



--[[
        Synopsis:       Creates a full path to a remote file from parent and child components.

        Notes:          Uses dir-path function to assure leading slash, one sep, and trailing slash,
                        then removes the trailing slash to turn it into a file reference.

        Returns:        Full path, no excuses, no trailing slash.  - No guarantee its to a real file: garbage in = garbage out.
--]]
function RcFtpUtils.makeFilePath( rootPath, subPath )
    local dirPath = RcFtpUtils.makeDirPath( rootPath, subPath ) -- guaranteed to end with a slash.
    return string.sub( dirPath, 1, string.len(dirPath) - 1 ) -- remove trailing slash to convert to file reference.
end    



--[[
        Synopsis:       Removes a file which is presumably (although not necessarily) existing before calling.

        Notes:          file-path - presumably already in the proper format (hint: use make-file-path).

        Returns:        - true: file removed, or was never there.
                        - false, error message: file not removed, reason.
--]]
function RcFtpUtils.removeFile( ftpConn, filePath )
    local name = _setPath( ftpConn, filePath )
    local sts, qual = _pRemoveFile( ftpConn, name )
    if sts then -- call completed
        -- qual would need to be checked if made test-mode aware, since we would not actually be removing the file. ###4
        local v1, v2 = RcFtpUtils.existsAsFile( ftpConn, name, false ) -- false => expect file not to exist.
        if v1 ~= nil then -- answer definitive
            -- v2 suppossedly nil when answer definitive.
            if v1 then -- answer afirmative
                return false, LOC( "$$$/X=Unable to confirm remote file (^1) removal.", filePath ) -- unconditional failure
            else -- answer negative
                return true -- unconditional success
            end
        else
            return false, LOC( "$$$/X=Some problem removing remote file (^1), error message: ^2", filePath, RcLua.toString( v2 ) )
        end
    else
        return false, LOC( "$$$/X=Unable to complete remote file (^1) removal, more: ^2", filePath, qual )
    end
end



--[[
        Synopsis:       Removes a directory known to exist and be empty.

        Notes:          - dir-path - presumably already in the proper format (hint: use make-dir-path).
                        - first return value will never be nil.

        Returns:        - true, nil -- worked, no issues.
                        - *true, msg -- *reserved for test mode.
                        - false, msg -- maybe didnt work, warning or error message.
--]]
function RcFtpUtils.removeEmptyDir( ftpConn, dirPath )
    local name = _setPath( ftpConn, dirPath )
    local status, qualification = _pRemoveEmptyDirectory( ftpConn, name )
    if status then -- protected function completed without an error being thrown.
        local s1, s2 = RcFtpUtils.existsAsDir( ftpConn, name, false ) -- false => expect directory to not exist.
        if s1 ~= nil then -- determination definitive
            if s1 then -- affirmative
                return false, "Unable to remove remote dir (which is supposedly empty): " .. dirPath
            else
                return true -- worked
            end
        else
            return false, LOC( "$$$/X=Unable to asertain if remote dir was removed: ^1, more: ", dirPath, RcLua.toString( s2 ) )
        end
    else
        return false, LOC( "$$$/X=Unable to complete remote dir removal (which is supposedly empty), path: ^1, more: ^2", dirPath, qualification )
    end
end



--[[
        Synopsis:       Remove a directory tree, which typically (although not necessarily) pre-exists, including sub-dir & files.

        Note:           - You can not remove the root dir.
                        - first return value is never nil.

        Returns:        - true, nil:                removed, or wasnt there to begin with, no comment, no distinction.
                        - false, error-message:     cant, and here's why...
--]]
function RcFtpUtils.removeDirTree( ftpConn, remotePath )
    local name = _setPath( ftpConn, remotePath )
    local v1, v2 = RcFtpUtils.existsAsDir( ftpConn, name ) -- unfortunately, as presently coded, dunno whether to expect it or not.
    if v1 ~= nil then -- determination definitive
        if v1 then -- affirmative
            -- keep going
        else
            return true -- nothing to remove
        end
    else -- cant determine if there's a directory to remove or not.
        -- at this point, wont hurt to give it a whack anyway.
        RcUtils.logWarning( LOC( "$$$/X=Unable to ascertain if directory (^1) exists to be removed, gonna try anyway..., more: ^2", remotePath, RcLua.toString( v2 ) ), RcUtils.VERBOSE )
    end
    local sts1, sts2
    if RcString.is( remotePath ) and (remotePath ~= '/') and (remotePath ~= '\\') then
        return _removeDirTree( ftpConn, remotePath ) -- logs files and dirs removed in verbose mode.
    else
        return false, "Cant remove root dir: " .. RcLua.toString( remotePath )
    end
end



--[[
        Synopsis:       Create directories if not already, up to and including the leaf of specified path.

        Notes:          - path must be to folder, not file.
                        - departs from the "leave logging to calling context" convention by logging
                          all dirs created or pre-existing if verbose mode. ###4 - could make a table
                          and return to caller.

        Returns:        - true, nil:              worked, no comment.
                        - true, comment:          pretend it worked, see comment.
                        - false, error-message:   failed.
--]]
function RcFtpUtils.assureAllRemoteDirectories( ftpConn, _path )
    local children = {}
    local path = _path
    local leaf
    repeat
        leaf = _setPath( ftpConn, path ) -- LrPathUtils.leafName( path )
        path = LrPathUtils.parent( path )
        if RcString.is( path ) then -- if we havent spun above the root yet.
            local v1, v2 = RcFtpUtils.existsAsDir( ftpConn, leaf )
            if v1 ~= nil then -- results are definitive
                -- v2 is nil.
                if v1 == true then -- dir exists.
                    RcUtils.logMessageLine( "Remote directory already exists: " .. leaf .. " at " .. path, RcUtils.VERBOSE )
                    break
                elseif v1 == false then -- dir does not exist.
                    RcUtils.logMessageLine( "Remote directory does not already exist: " .. leaf .. " at " .. path, RcUtils.VERBOSE )
                    children[#children + 1] = leaf
                else
                    error( "non-nil value not true nor false returned from dir-exists function." )
                end
            else
                -- v2 has more.
                return false, LOC( "$$$/X=Unable to create remote directory: ^1, more: ^2", _path, RcLua.toString( v2 ) )
            end
        else
            return false, LOC( "$$$/X=Unable to create remote directory: ^1", _path )
        end            
    until false -- until break or error/return.
    local index = #children
    path = RcFtpUtils.makeDirPath( path, leaf )
    while index > 0 do
        local leaf = children[index]
        ftpConn.path = path
        local sts, qual = _makeDirectory( ftpConn, leaf )
        if sts then -- call completed - either worked or I should pretend like it did.
            -- could check qual...
            path = RcFtpUtils.makeDirPath( path, leaf )
            index = index - 1
        else
            return false, LOC( "$$$/X=Unable to create remote directory, parent: ^1, name: ^2, more: ^3", path, leaf, qual )
        end
    end
    -- check:
    leaf = _setPath( ftpConn, _path )
    local result, errorMessage = RcFtpUtils.existsAsDir( ftpConn, leaf, true ) -- true => directory expected to exist.
    if result ~= nil then -- result definitive
        -- error-message nil.
        if result == true then -- result affirmative
            return true -- no comment.
        else
            return false, LOC( "$$$/X=Unable to assure remote directories, path: ^1", _path )
        end
    else
        -- error message explains
        return false, LOC( "$$$/X=Unable to assure remote directories, path: ^1, more: ^2", _path, RcLua.toString( errorMessage ) )
    end
end



--[[
        Synopsis:       Create a remote directory, if not already existing.

        Notes:          Creates parent directories as necessary.

        Returns:        - true, nil:            worked, no comment, no distinction.
                        - true, comment:        pretend like it worked, see comment.
                        - false, comment:       failed.
--]]
function RcFtpUtils.makeDir( ftpConn, dir )
    return RcFtpUtils.assureAllRemoteDirectories( ftpConn, dir )
end



--[[
        Synopsis:       Put (upload) a file from local disk to remote.

        Notes:          - If file pre-exists and overwrite OK, existing target will be removed first.
                        - Directory tree created if necessary to support file.
                        - Taking liberty to do a little verbose logging, plus warnings... ###4

        Returns:        - true, nil:        worked, no comment.
                        - *true, comment:   *pretended to work... - reserved for test mode.
                        - false, comment:   failed.
--]]
function RcFtpUtils.putFile( ftpConn, localPath, remotePath, overwriteOK )
    local name = _setPath( ftpConn, remotePath )
    local dir = ftpConn.path
    local r1, r2 = RcFtpUtils.existsAsFile( ftpConn, name )
    if r1 ~= nil then -- file existence determination definitive
        if r1 then -- affirmative
            if overwriteOK then
                RcUtils.logMessageLine( "Putting file and remote file already exists, removing for overwrite: " .. remotePath, RcUtils.VERBOSE )
                local x1, x2 = RcFtpUtils.removeFile( ftpConn, remotePath )
                if x1 ~= nil then -- definitive
                    if x1 then -- affirmative
                        -- good - fall through.
                    else
                        return false, "Unable to remove pre-existing file, error message: " .. RcLua.toString( x2 )
                    end
                else -- trouble
                    return false, "Unable to determine if pre-existing file was removed, error message" .. RcLua.toString( x2 )
                end
            else
                return false, LOC( "$$$/X=Remote file (^1) already exists, and overwrite not OK.", remotePath )
            end
        else -- negative
            local sts, qual = RcFtpUtils.assureAllRemoteDirectories( ftpConn, dir )
            if sts then -- call completed
                -- could check qual here.
            else
                return false, LOC( "$$$/X=Unable to assure remote directories (^1) to put file (^2) into.", dir, name )
            end
        end
    else
        return false, "unable to ascertain whether file already exists or not: " .. remotePath
    end
    name = _setPath( ftpConn, dir )
    local d1, d2 = RcFtpUtils.existsAsDir( ftpConn, name, true ) -- even if return codes are being ignored this may still be doing something worthwhile.
    if RcUtils.debugMode then
        if d1 ~= nil then -- answer definitive
            if d1 == true then -- answer affirmative
                -- good
            else
                RcUtils.logWarning( LOC("$$$/X=Target dir (^1) should exist before putting file (^2): ^3", dir, name, RcLua.toString( d2 ) ) )
            end
        else
            RcUtils.logWarning( LOC("$$$/X=Unable to ascertain if target dir (^1) exists before putting file (^2), more: ^3", dir, name, RcLua.toString( d2 ) ) )
        end
    end
    name = _setPath( ftpConn, remotePath )
    local f1, f2 = RcFtpUtils.existsAsFile( ftpConn, name, false ) -- even if return codes are being ignored this may still be doing something worthwhile.
    if RcUtils.debugMode then
        if f1 ~= nil then -- answer definitive
            if f1 == true then -- answer affirmative
                RcUtils.logWarning( LOC("$$$/X=Remote file (^1) should have been pre-removed before putting local file (^2), more: ^3", remotePath, localPath, RcLua.toString( f2 ) ) )
            else
                -- good
            end
        else
            RcUtils.logWarning( LOC("$$$/X=Unable to ascertaining if remote file (^1) exists before putting local file (^2), more: ^3", remotePath, localPath, RcLua.toString( f2 ) ) )
        end
    end
    local status, qualification = _putFile( ftpConn, localPath, name ) -- do it anyway - better to try and fail than not try - often it succeeds even if pre-checks dont - go figure.
    return status, qualification
end



--[[
        Synopsis:       Get lists of directories and files in the specified remote directory.

        Returns:        two tables of directory elements (one for directories, one for files) whose entries are tables containing:

                            - leafName: string
                            - date: last-mod date-time, expressed as a number of seconds since midnight GMT, January 1, 2001 (same as local files ala lr-file-utils).
        
                        Returns empty tables if directory empty.

                        Returns nil & error message if probs.

        Side Effects:   - Will change path in ftp-conn.

        Notes:          Usually only called when directory known to exist - not sure what happens if it doesn't.

        *** IMPORTANT NOTE: Relies on parsing text content of remote directory - may not be compatible with all servers. ###3
        *** IMPORTANT NOTE: Must not be called from calibrate-clock method or there will be an infinite loop.
--]]
function RcFtpUtils.getDirContents( ftpConn, dirPath, remoteClockOffset )
    local clockOffset
    if remoteClockOffset == nil then
        if RcFtpUtils.remoteClockOffset[ftpConn.server] ~= nil then
            -- good to go
            clockOffset = RcFtpUtils.remoteClockOffset[ftpConn.server]
        else
            return nil, LOC( "$$$/X=Unable to get directory contents - remote clock not calibrated." )
        end
    else
        clockOffset = remoteClockOffset
    end

    local dirTable = {}
    local fileTable = {}

    local dirEnt = nil
    ftpConn.path = dirPath
    local s, qual = _getDirContents( ftpConn )
    if s ~= nil and not qual then
    	for line in RcString.lines( s ) do
    		-- RcUtils . hogMessageLine(line)
            if string.len(line) > 0 then
                dirEnt = {}
                local dirType, dirDateTime, dirLeafName, dirSize = _parseDirEntry( line )
                -- _debugTrace( "rcftpugdc", "dir leaf name: " .. dirLeafName )
                if RcString.startsWith( dirLeafName, "." ) > 0 then
                    -- hidden dir or file - ignore
                else
                    dirEnt.leafName = dirLeafName
                    dirEnt.date = dirDateTime - clockOffset
                    dirEnt.size = dirSize
                    if dirType == 'D' then
                        dirTable[#dirTable + 1] = dirEnt
                    elseif dirType == 'f' then
                        fileTable[#fileTable + 1] = dirEnt
                    else
                        return nil, "Unable to parse directory entries, path: " .. dirPath  -- calling context MUST check for this, to handle unexpected directory response formats.
                    end
                end
            else
                -- ignore blank lines
            end
    	end
    else
        -- I (no longer) assume directory is empty in this case.
        return nil, qual
    end
    return dirTable, fileTable
end



--[[
        Synopsis:       Computes offset of remote clock from 2001-01-01, GMT.

        Motivation:     FTP, much to my dissatisfaction, uses the remote clock to set the timestamp of uploaded files.
                        I wish it would set it to the exact value of the local source file. This would solve a lot of
                        problems, and cause none. But, for some reason, the FTP protocol is like never improved (go figure),
                        thus we have to keep chugging along with same 'ol same 'ol for better and for worse...

                        The problem is:

                            If the clock at the remote end is slow, and you upload a file immediately after changing it,
                            it will appear to be out of date already after being uploaded. Throw in differences in time zone,
                            and daylight savings and the problem worsens - the file may appear out of date all day long, even
                            after continually uploading, then appear up-to-date the next day without having done anything except wait.
                            Likewise, and usually a worse problem - if the clock at the remote end is ahead, a recently changed
                            local file may appear up-to-date forever and never be uploaded.

                        The solution is:

                            Before beginning an ftp session, create a tiny local file and upload it. Read the remote timestamp back
                            and save the difference between it and local time. This offset can then be applied in the future to 
                            compute a normalized remote timestamp that is accurate to within a few seconds, instead of 25 hours.
                            
        Note:           This function may be called explicitly from outside, which allows logging of results before ftp session begins,
                        and allows specification of writeable directory to be used for temp filem
                        but if not - will be called automatically from within - temp file dir will be whatever.

                        My experience has been that true ftp connections are not really made until they needs to be. 
                        And since this may be the first need, it will fail if remote server is down.

        Returns:        - true, nil:            calibrated, no comment.
                        - false, error-message: failed.
--]]
function RcFtpUtils.calibrateClock( ftpConn, localDirForTempFile, remoteDirForTempFile )

    assert( remoteDirForTempFile ~= nil, "Remote clock calibration requires dir for remote temp file." )

    RcFtpUtils.remoteClockOffset[ftpConn.server] = nil -- as long as the offset is only a minute or less, there's not going to be any problems. The problems
        -- come when the time is off by several minutes, or hours (or more).

    local filename = "___tempFileForRemoteClockOffsetCalibration.txt"
    local localFilePath
    if RcString.is( localDirForTempFile ) then
        localFilePath = LrPathUtils.child( localDirForTempFile, filename )
    else
        localFilePath = RcFileUtils.resolveAllAliases( filename )
    end
    local remoteFilePath = RcFtpUtils.makeFilePath( remoteDirForTempFile, filename )
    local s = "This file should be deleted."
    local status, qualification, message
    status, qualification = RcFileUtils.writeFile( localFilePath, s ) -- test mode aware.
    if status and not qualification then -- file actually written.

        RcUtils.logMessageLine( LOC( "$$$/X=Putting local temp file (^1) to remote file (^2) for remote clock calibration.", localFilePath, remoteFilePath ) )
        status, message = RcFtpUtils.putFile( ftpConn, localFilePath, remoteFilePath, true ) -- true => overwrite-ok.

        if status and not message then -- file put correctly, which means remote server is alive...
            local fileAttrs = RcFileUtils.fileAttributes( localFilePath )
            local localTime = fileAttrs.fileModificationDate -- ###4 seems it would be better to use present/now time, no? (I believe I already considered this - correctly???)

            local contents, qual = _getDirContents( ftpConn ) -- same path as file put.

            if contents ~= nil and not qual then

            	for line in RcString.lines( contents ) do
                    if string.len(line) > 0 then
                        local dirType, dirDateTime, dirLeafName = _parseDirEntry( line )
                        if dirLeafName == filename then
                            RcFtpUtils.remoteClockOffset[ftpConn.server] = dirDateTime - localTime
                            RcUtils.logMessageLine("\nRemote Clock calibrated, server: " .. RcLua.toString( ftpConn.server ) .. ", offset: " .. RcLua.toString( RcFtpUtils.remoteClockOffset[ftpConn.server] ) )
                            break
                        end
                    else
                        -- ignore blank lines
                    end
                end
                if RcFtpUtils.remoteClockOffset[ftpConn.server] == nil then -- all errors are caught in the same net here.
                    -- this is the one error that is considered fatal, since it means we can't properly parse directory
                    -- contents of the server.
                    error( "****** Remote clock uncalibrated - remote dir content maybe not parsed correctly." )
                        -- most of the apps that use this module will not work correctly if remote clock not calibrated correctly,
                        -- and or remote dir contents can not be parsed correctly, so might as well die here.
            	end
            else
                status = false
                qualification = "Remote clock uncalibrated - bad response from server for directory request."
                RcFtpUtils.remoteClockOffset[ftpConn.server] = 0
            end

            _pRemoveFile( ftpConn, filename ) -- remove remote cal file. ###5 why are return codes being ignored?

        else -- error writing remote file, or its test mode.
            status = false
            qualification = LOC( "$$$/X=Remote clock uncalibrated - ^1", RcLua.toString( message ) ) -- could just be test mode.
            RcFtpUtils.remoteClockOffset[ftpConn.server] = 0
        end

        RcFileUtils.delete( localFilePath ) -- local file was actually written - discard. ###5 could attend to return code.

    elseif qualification then -- test mode
        RcFtpUtils.remoteClockOffset[ftpConn.server] = 0
        qualification = "CONSIDERING remote clock calibrated."
        status = true -- pretend worked.
    else -- failed.
        RcFtpUtils.remoteClockOffset[ftpConn.server] = 0 -- calling context can try to proceed,
        status = false -- or not.
        qualification = LOC( "$$$/X=Remote clock uncalibrated - local dir probably not set correctly - ^2 must be writeable. More: ", localFilePath, qualification )
    end
    return status, qualification
end



return RcFtpUtils
