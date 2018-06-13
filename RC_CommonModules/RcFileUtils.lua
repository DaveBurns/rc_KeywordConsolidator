--[[
        Filename:           RcFileUtils.lua
        
        Synopsis:           wraps lr-file-utils into test-mode aware equivalents,
                            plus handles overwriting and target dir creation more specifically.

        Proxied static functions (identical to lr versions):
            - exists                - reserved for case when there are no expectations about target type.
            - file-attributes
            - delete                - reserved for case when file needs to be permanently deleted regardless of mode.
            - directory-entries
            - files
            - is-empty-directory
            - is-deletable
            - moveFolderOrFile
            - resolveAllAliases
            - recursiveDirectoryEntries
            - recursiveFiles
            - chooseUniqueFileName

        Un-proxied static functions:
            - create-all-directories    - use assure-all-directories instead.

        New Static Functions:
            - exists-as      - determines if path represents existing item of specified type.
            - move-to-trash   - same as lr version, except test-mode aware.
            - assure-all-directories - Like create-all-directories, only better.
            - copy-file      - copies source file to destination, as specified.
            - move-file      - moves source file to destination, as specified.

        Constants:
            - throw-error-if-wrong-type: pass to exists-as, in case it exists as the other kind.

        Return values:  I'm trying to standardize return values for functions to:
            1:  completion-status: true or false - did the function call complete successfully, or were there issues.
            2:  qualification: - string - description of issues.
            3+: boolean flags and any other tidbits the function may deem informative.
        
        Examples:
            completionStatus, qualification, tidbit1, tidbit2 = doSomething( withSomething )
            if completionStatus then -- call completed successfully
                if qualification then -- only qualification for successful completion is test mode log string
                    logMessageLine( qualification )
                    -- maybe handle any differences that might arise from qualified success - usually none.
                else
                    logMessageLine( "Something done..." )
                end
            else
                -- handle error or warning
            end
--]]


local RcFileUtils = {}


assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )
assert( RcUtils ~= nil, "Global rc-utils must be pre-loaded and initialized." )


local LrFileUtils = RcModuleLoader.import( 'LrFileUtils' )
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )
local LrTasks = RcModuleLoader.import( 'LrTasks' )
local LrStringUtils = RcModuleLoader.import( 'LrStringUtils' )

local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )


-- Lightroom equivalents, so modules do not need to depend on lr-file-utils, which ensures test-mode conformance.
RcFileUtils.exists = LrFileUtils.exists
RcFileUtils.fileAttributes = LrFileUtils.fileAttributes
RcFileUtils.delete = LrFileUtils.delete -- use move-to-trash for normal circumstances - delete is not test-mode aware.
RcFileUtils.directoryEntries = LrFileUtils.directoryEntries
RcFileUtils.files = LrFileUtils.files
RcFileUtils.isEmptyDirectory = LrFileUtils.isEmptyDirectory
RcFileUtils.resolveAllAliases = LrFileUtils.resolveAllAliases
RcFileUtils.isReadable = LrFileUtils.isReadable
RcFileUtils.isWritable = LrFileUtils.isWritable
RcFileUtils.isDeletable = LrFileUtils.isDeletable
RcFileUtils.recursiveDirectoryEntries = LrFileUtils.recursiveDirectoryEntries
RcFileUtils.recursiveFiles = LrFileUtils.recursiveFiles
RcFileUtils.chooseUniqueFileName = LrFileUtils.chooseUniqueFileName



-- Public Constants:
RcFileUtils.THROW_ERROR_IF_WRONG_TYPE = true -- convenience constant - for calling context readability.
    -- deprecated: use dedicated exists-as-type function instead.
RcFileUtils.OVERWRITE = true -- convenience constant - for calling context readability.
RcFileUtils.CREATE_DIRS = true -- convenience constant - for calling context readability.
RcFileUtils.AVOID_UNNECESSARY_UPDATE = true -- convenience constant - for calling context readability.




-- debugging support
local _debugMode = false -- ### set false before releasing
local function _debugTrace( id, info )
    if not _debugMode then return end
    RcUtils.debugTrace( 'RcFileUtils - ' .. id, info, true ) -- include ID as message prefix.
end



--[[
        Synopsis:       Move or rename a file.
        
        Motivation:     - Handles case of silent failure of Lr version.
                        - Test mode aware.
                        
        Returns:        - true, nil:        moved, no comment.
                        - true, comment:    pretended to move - test mode.
                        - false, comment:   failed.
                        
        Notes:          Lr doc says its just for files, but experience dictates it works on folders as well.
                        
                        *** SOURCE EXISTENCE NOT PRE-CHECKED, NOR IS TARGET PRE-EXISTENCE - SO CHECK BEFORE CALLING IF DESIRED.
--]]
function RcFileUtils.moveFolderOrFile( oldPath, newPath )
    if not RcUtils.testMode then
        local pcallStatus, more = LrTasks.pcall( LrFileUtils.move, oldPath, newPath )
        if pcallStatus then
            local exists = LrFileUtils.exists( newPath )
            if exists then
                return true
            else
                return false, LOC( "$$$/X=UNABLE TO MOVE ^1 TO ^2 - NOT SURE WHY.", oldPath, newPath )
            end
        else
            return false, LOC( "$$$/X=UNABLE TO MOVE ^1 TO ^2 - MORE: ", oldPath, newPath, more )
        end
    else
        return true, LOC( "$$$/X=^1 WOULD BE MOVED TO ^2", oldPath, newPath )
    end
end



--[[
        Synopsis:       Determines if path exists as a specified type.

        Motivation:     Sometimes its not good enough to know if a path exists or not, but what type it exists as.
                        Adobe realized this, which is why their exists method returns a type string.
                        Problem is, one can not compare it directly to an expected type because if it does not
                        exist, a "boolean being compared to string" error is thrown. Thus, a nested conditional
                        is required: 1. does it exist, 2. What type. This method allows calling context to use a
                        single conditional.

        Side Benefit:   Forces calling context to deal with the possibility that a folder may exist where a file is expected,
                        or vice versa, which if un-detected, may cause strange and difficult to diagnose behavior / errors.

        Returns:        - true, nil:        exists as specified type; 'nuf said.
                        - false, nil:       does not exist.
                        - IF NOT THROWING ERROR UPON WRONG TYPE: false, type: exists as the other type; returns that type.

        Examples:

            path = "/asdf"
            existsAsFile, isDir = RcFileUtils.existsAs( path, 'file' ) -- return opposite type else not found if not type.
            if existsAsFile then
                -- process file
            elseif isDir then
                assert( dirType == 'directory', "Path is to directory: " .. path )
                -- process path is to directory, not file.
            else
                -- process file not found.
            end

            existsAsDir = RcFileUtils.existsAs( path, 'directory', true ) -- returns true or false, bombs if path is to file.
            if existsAsDir then
                -- process directory
            else
                -- process dir not found.
            end


--]]
function RcFileUtils.existsAs( path, type, throwErrorIfWrongType )
    assert( RcUtils ~= nil, "rc-file-utils requires rc-utils to be initialized." )
    assert( RcUtils.testMode ~= nil, "rc-file-utils requires rc-utils-test-mode to be initialized." )
        -- this function does not actually depend on test-mode, but best to nip it in the bud...
    local exists = LrFileUtils.exists( path )
    if exists then
        if exists == type then
            return true -- 2nd return value nil - implied.
        elseif type == 'file' then
            if throwErrorIfWrongType then
                error( "Path specifies directory, should be file: " .. path )
            end
            return false, true
        elseif type == 'directory' then
            if throwErrorIfWrongType then
                error( "Path specifies file, should be directory: " .. path )
            end
            return false, true
        else
            error( "Program failure - invalid type argument to rc-file-utils-exists-as: " .. RcLua.toString( type ) )
        end
    else
        return false, false
    end
end



--[[
        Synopsis:       Determine if path is to a directory.

        Notes:          The directory entry must either not exist, or be a directory, else an error is thrown.
--]]
function RcFileUtils.existsAsDirectory( path )
    return RcFileUtils.existsAs( path, 'directory', true ) -- if you don't want default error behavior, call the generic exists-as directly.
end



--[[
        Synopsis:       Determine if path is to a file.

        Notes:          The directory entry must either not exist, or be a file, else an error is thrown.
--]]
function RcFileUtils.existsAsFile( path )
    return RcFileUtils.existsAs( path, 'file', true ) -- if you don't want default error behavior, call the generic exists-as directly.
end



--[[
        Synopsis:               Deletes a file and confirms deletion instead of relying on status code returned from delete.
        
        *** IMPORTANT NOTE:     - NOT test mode aware.
        
        Note:                   - MUST be called from a task.
                                - Born from a case I had where a recently deleted file was not able to be immediately written,
                                  or something like that.
--]]
function RcFileUtils.deleteFileConfirm( path )
    if RcFileUtils.existsAsFile( path ) then
        LrFileUtils.delete( path )
        count = 0
        repeat
            LrTasks.sleep( .1 )
            count = count + 1
        until not RcFileUtils.existsAsFile( path ) or count == 100 -- ten seconds max.
        if RcFileUtils.existsAsFile( path ) then
            error( "Unable to delete " .. path )
        end
    end
end



--[[
        Synopsis:           Delete file unless test mode.
        
        Notes:              - Really should have modified the generic one to be test mode aware, then
                              had a delete-unconditionally method for bypassing test mode - oh well.
        
        Returns:            status, message
--]]        
function RcFileUtils.deleteIfNotTestMode( path )
    local status, message
    if not RcUtils.testMode then
        status, message = LrFileUtils.delete( path )
    else
        status = true -- pretend it worked.
        message = "WOULD delete " .. RcLua.toString( path )
    end
    return status, message
end




--[[
        Synopsis:       Moves specified folder or file to trash/recycle bin.

        Motivation:     Test mode aware.

        Notes:          Not sure what happens if specified item does not exist - same as lr version.

        Returns:        status, explanation
                        - true, nil => item deleted; no comment.
                        - true, expl => test mode, pretending like it did it.
                        - false, error-message => item not moved; reason.
--]]
function RcFileUtils.moveToTrash( path )
    assert( RcUtils.testMode ~= nil, "rc-file-utils requires rc-utils-test-mode to be initialized." )
    if not RcUtils.testMode then
        -- local status, reason = LrFileUtils.moveToTrash( path ) -- Probably protected mode not required, since status returned reflects failure, but I feel safer
            -- using it, since Network mounted volumes on Mac do not support trash - they crash.
        local pcallStatus, status, reason = LrTasks.pcall( LrFileUtils.moveToTrash, path )
        if pcallStatus and status then -- pcall & move-to-trash worked.
            return true -- no comment.
        else
            RcUtils.logMessageLine( LOC( "$$$/X=Move to trash, failed with reason: " .. RcLua.toString( reason ) .. " - trying delete, path: ^1", path ), RcUtils.VERBOSE ) -- remove this line if its bugging you.
            pcallStatus, status, reason = LrTasks.pcall( LrFileUtils.delete, path )
            if pcallStatus and status then
                return true -- alls well that ends well.
            else
                return false, "UNABLE TO DELETE " .. path .. ", MORE: " .. RcLua.toString( reason )
            end
        end
    else
        return true, "WOULD MOVE " .. path .. " TO TRASH." -- pretend like it did.
    end
end



--[[
        Synopsis:       Deletes specified folder or file.

        Motivation:     - protected.
                        - test mode aware.

        Notes:          Not sure what happens if specified item does not exist - same as lr version.

        Returns:        status, explanation
                        - true, nil => item deleted; no comment.
                        - true, expl => test mode, pretending like it did it.
                        - false, error-message => item not moved; reason.
--]]
function RcFileUtils.deleteFolderOrFile( path )
    assert( RcUtils.testMode ~= nil, "rc-file-utils requires rc-utils-test-mode to be initialized." )
    if not RcUtils.testMode then
        local status, reason = LrFileUtils.delete( path ) -- Assume protected mode not required, since values returned reflects success or failure.
        if status then
            return true -- no comment.
        else
            return false, "UNABLE TO MOVE " .. path .. " TO TRASH, REASON: " .. RcLua.toString( reason )
        end
    else
        return true, "WOULD MOVE " .. path .. " TO TRASH." -- pretend like it did.
    end
end



--[[
        Synopsis:       Attempts to assure sub-directory tree will exist upon return.

        Returns:        - completion-status, qualification, dirs-created:
                          - true, nil, false:       worked; no qualification; dir already existed.
                          - true, nil, true:        worked; no qualification; dirs created.
                          - false, expl, false:     failed; error message; dirs not created.
                          - true, expl, true:       worked; test-mode message; pretending dirs created.
        Examples:
            success, qual, created = RcFileUtils.assureAllDirectories( target )
            if success then
                if created then
                    nCreated = nCreated + 1
                    if qual then
                        logMessageLine( qual )
                    else
                        logMessageLine( "Directories created: " .. target )
                    end
                else
                    nAlready = nAlready + 1
                end
                -- do things to target...
            else
                assert( created == false )
                assert( RcString.is( qual ) )
                logError( "Unable to assure destination directory - " .. qual )
                -- abort function...
            end
            
--]]
function RcFileUtils.assureAllDirectories( targetDir )
    assert( RcUtils.testMode ~= nil, "rc-file-utils requires rc-utils-test-mode to be initialized." )
    local existsAsDir = RcFileUtils.existsAs( targetDir, 'directory', true )
    if existsAsDir then
        return true, nil, false
    -- else proceed
    end
    -- fall-through => dest dir not pre-existing.
    if not RcUtils.testMode then
        local created = LrFileUtils.createAllDirectories( targetDir ) -- supposedly false means dir already exists, but I dont believe it.
        if created then
            return true, nil, true
        else
            assert( not RcFileUtils.existsAsDirectory( targetDir ), "Program failure." ) -- if not existing, error already thrown.
            return false, "Failure creating directories: " .. targetDir, false
        end
    else
        return true, "WOULD CREATE DIRECTORY: " .. targetDir, true
    end
end



local __copyBigFile = function( sourcePath, destPath, progressScope )

    local fileSize = LrFileUtils.fileAttributes( sourcePath ).fileSize

    local g
    local s
    local t
    -- local blkSize = 32768 -- typical cluster size on large system or primary data drive.
    local blkSize = 10000000 -- 10MB at a time - lua is fine with big chunks.
    local nBlks = math.ceil( fileSize / blkSize )
    local b
    local x
    g, s = pcall( io.open, sourcePath, 'rb' )
    if not g then return false, s end
    g, t = pcall( io.open, destPath, 'wb' )
    if not g then
        pcall( io.close, s )
        return false, t
    end
    local done = false
    local m = 'unknown error'
    local i = 0
    local yc = 0
    repeat -- forever - until break
        g, b = pcall( s.read, s, blkSize )
        if not g then
            m = b
            break
        end
        if b then
            g, x = pcall( t.write, t, b )
            if not g then
                m = x
                break
            end
            i = i + 1
            if progressScope then
                progressScope:setPortionComplete( i, nBlks )
            end
            yc = RcUtils.yield( yc )
        else
            g, x = pcall( t.flush, t ) -- close also flushes, but I feel more comfortable pre-flushing and checking -
                -- that way I know if any error is due to writing or closing after written / flushed.
            if not g then
                m = x
                break
            end
            m = '' -- completed sans incident.
            done = true
            break
        end
    until false
    pcall( s.close, s )
    pcall( t.close, t )
    if done then
        return true
    else
        return false, m
    end
        
end


--[[
        Synopsis:       Copy or move file from source to destination.

        Assumes:        All pre-requisites have been pre-checked, or caller is willing to accept the consequences of not checking.

        Notes:          NOT test-mode aware.
        Notes:          NOT test-mode aware.
        Notes:          NOT test-mode aware.

        Returns:        - true, test-mode-expl - test mode: pretended to work.
                        - true, nil  - file actually transferred without incident; no comment.
                        - false, comment - trouble in paradise; here's why.
--]]
local __transferFileUnconditionally = function( transferFunc, sourcePath, destPath, progressScope )

    -- *** SAVE AS REMINDER: I COULD HAVE SWORN THIS WAS WORKING, YET IT NOW APPEARS NOT TO BE, ERROR MESSAGE: YIELD ACROSS C-CALL BOUNDARY OR SOMETHING LIKE THAT.
    -- IT SEEMS LIKE LIGHTROOM CHANGED THE GUTS SOMEHOW - MY PRESENT THEORY IS LIGHTROOM CHANGED IT TO RUN IN PROTECTED MODE INTERTERNALLY
    -- AND RETURN A BOOLEAN, INSTEAD OF CRASHING UNPROTECTEDLY, AND FORGOT TO DOCUMENT IT.
    -- RcUtils.logMessageLine( "Copying " .. sourcePath .. " to " .. destPath )
    -- local success, worked = LrTasks.pcall( transferFunc, sourcePath, destPath ) -- doc says nothing returned by copy/move, but my experience is a boolean is returned.###4
    -- RcUtils.logMessageLine( LOC( "$$$/X=Pcall/Copy returned ^1, ^2", RcLua.toString( success ), RcLua.toString( worked ) ) )
    
    local worked
    local orNot
    if transferFunc then -- lr-copy or lr-move
        worked = transferFunc( sourcePath, destPath )
    else
        worked, orNot = __copyBigFile( sourcePath, destPath, progressScope ) -- actually, this might be necessary for a move too if moving from one drive to another. ###4
    end

    if worked then
        return true
    elseif orNot then
        return false, "File transfer failed, source: " .. sourcePath .. ", destination: " .. destPath .. ", more: " .. RcLua.toString( orNot )
    else
        return false, "File transfer failed, source: " .. sourcePath .. ", destination: " .. destPath -- have to assume IO failure I guess - everything else pre-checked in calling context, no?
    end
    
end
        


--[[
        Synopsis:       Copies source file to destination, checking for and responding to potential blockages as specified by calling context.

        Notes:          - if dest-dir-check and overwrite-check are omitted, function performs
                          just like lr version, except test-mode aware.

        Parameters:     - create-dest-dirs-if-necessary:
                          - nil:    dest-dir-tree not checked for, just does whatever lr version would in that respect.
                          - false:  checks for dest-dirs, and if not there, returns failure and explanation.
                          - true:  checks for dest-dirs, and if not there, creates them.
                        - overwrite-dest-file-if-necessary:
                          - nil:    dest-file not checked for, just does whatever lr version would in that respect.
                          - false:  checks for dest-file, and if there, returns failure and explanation.
                          - true:  checks for dest-dirs, and if there, deletes it before copying.

        Returns:        status, explanation, overwritten, dirs-created, justTouched
--]]
function _transferFile( transferFunc, sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate, progressScope )
    local destDir
    local overwritten = false
    local dirsCreated = false
    -- local qualification = nil
    -- deal with pre-existing target, if requested.
    local justTouched = false
    if overwriteDestFileIfNecessary then
        local existsAsFile = RcFileUtils.existsAsFile( destPath )
        if existsAsFile then

            if avoidUnnecessaryUpdate then
                
                local same, problem = RcFileUtils.isFileSame( sourcePath, destPath )
                if not problem then
                    if same then
                        justTouched = true -- must still overwrite target to get date updated.
                            -- calling context must see this and avoid processing as changed if it matters.
                    -- else proceed
                    end
                else
                    return false, "Unable to compare files - " .. problem, false, false
                end
            -- else proceed
            end

            local completed, qualification = RcFileUtils.deleteFolderOrFile( destPath ) -- if you use move-to-trash you get a rapidly filling trashcan just by things being updated.
            if completed then -- function call completed successfully.
                -- nothing special done here upon qualification - calling context can look at overwrite flag...
                overwritten = true
            else
                return false, LOC( "$$$/X=Unable to delete pre-existing target for overwrite, path: ^1", destPath )
            end
        else
            -- not necessary
        end
    -- else just try it.
    end
    -- fall-through => dest-file does not exist or dont care if it does.
    -- deal with creating target sub-tree, if requested.
    if createDestDirsIfNecessary and not overwritten then
        destDir = LrPathUtils.parent( destPath )
        local existsAsDir, orNot = RcFileUtils.existsAs( destDir, 'directory', true ) -- bomb if dest-dir represents an existing file, although this is theoretically impossible.
        if existsAsDir then
            -- good to go
        else -- dest-dir does not exist, so necessary to create it.
            local assured, expl, created = RcFileUtils.assureAllDirectories( destDir )
            if assured then
                if created then -- dirs created, or would be.
                    dirsCreated = true
                else -- already exists?
                    error( "Program failure - assure-all-directories." )
                end
            else
                return false, "File transfer failed, explanation: " .. expl, false, false
            end

        end
    -- else not necessary
    end
    -- fall-through => target dirs prepared, or dont care if they are.
    local status, expl
    if not RcUtils.testMode then
        status, expl = __transferFileUnconditionally( transferFunc, sourcePath, destPath, progressScope )
    else
        status = true
        if justTouched then
            expl = "WOULD TOUCH " .. destPath .. " - SAME AS SOURCE AT: " .. sourcePath -- touching file implicit - be more specific if touching dir.
        else
            expl = "WOULD COPY " .. sourcePath .. " TO " .. destPath -- copying file should be implicit. directory copy should be more specific.
        end
    end
    return status, expl, overwritten, dirsCreated, justTouched
end



--[[
        Synopsis:       Copies source file to destination, as specified.

        Assumes:        - Source file exists - bombs if not.

        Parameters:     - create-dest-dirs-if-necessary:
                          - nil:    dest-dir-tree not checked for, just does whatever lr version would in that respect.
                          - false:  checks for dest-dirs, and if not there, returns failure and explanation.
                          - true:  checks for dest-dirs, and if not there, creates them.
                        - overwrite-dest-file-if-necessary:
                          - nil:    dest-file not checked for, just does whatever lr version would in that respect.
                          - false:  checks for dest-file, and if there, returns failure and explanation.
                          - true:  checks for dest-dirs, and if there, deletes it before copying.

        Returns:        status, expl, ov, dirs.

        Example #1:     sts, expl, ov, dirs, touched = RcUtils.copyFile( source, dest, true, true )
                        if sts then
                            if expl then
                                logMessage( expl ) -- test mode log
                            else
                                logMessage( "File copied. " ) -- normal mode log.
                            end
                            if ov then
                                logMessage( "Target file overwritten. " )
                            elseif dirs then
                                logMessage( "Target dirs created. " )
                            end
                            logMessageLine()
                        else
                            logError( "File copy failed: " .. expl )
                        end

        Example #2:     sts, expl = RcUtils.copyFile( source, dest )
                        if sts then
                            if expl then
                                logMessageLine( expl ) -- test mode log
                            else
                                logMessageLine( "File copied. " ) -- normal mode log.
                            end
                        else
                            logError( "File copy failed: " .. expl )
                        end
            
--]]
function RcFileUtils.copyFile( sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate )
    assert( RcFileUtils.existsAsFile( sourcePath ), "Source file does not exist: " .. sourcePath )
    return _transferFile( LrFileUtils.copy, sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate )
end
function RcFileUtils.copyBigFile( sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate, progressScope )
    assert( RcFileUtils.existsAsFile( sourcePath ), "Source file does not exist: " .. sourcePath )
    return _transferFile( nil, sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate, progressScope )
end



--[[
        Synopsis:       Moves source file to destination, as specified.

        Assumes:        - Source file exists - bombs if not.

        Notes:          See copy-file for additional info.
--]]
function RcFileUtils.moveFile( sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate )
    assert( RcFileUtils.existsAsFile( sourcePath ), "Source file does not exist: " .. sourcePath )
    -- I'm assuming since lightroom gave us the same-volume api and suggested caller could use it to tell whether a copy or move
    -- is warranted, its because they did not do the right thing, and are passing the buck. I hereby accept...
    if LrFileUtils.pathsAreOnSameVolume( sourcePath, destPath ) then
        return _transferFile( LrFileUtils.move, sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary )
    else
        local status, expl, ov, dirs, justTouched = _transferFile( LrFileUtils.copy, sourcePath, destPath, createDestDirsIfNecessary, overwriteDestFileIfNecessary, avoidUnnecessaryUpdate )
        if status then
            if not RcUtils.testMode then
                local deleted, reason = LrFileUtils.delete( sourcePath ) -- Better to use delete instead of move to trash, so it doesn't fill up with stuff thats not really been deleted.
                    -- no need for test mode aware-ness either, since that is pre-checked. lr-file-utils runs in protected mode, I think - at a minimum it pre-checks file existence before proceeding.
                if deleted then
                    -- alls well.
                else
                    status = false
                    expl = "Unable to delete source file (" .. sourcePath .. ") after copying to destination (" .. destPath .. "), reason: " .. RcLua.toString( reason )
                end
            else
                -- expl returned by transfer-file should be sufficient.
            end
        else
            status = false
            expl = "Could not copy source file to destination: " .. expl
        end
        return status, expl, ov, dirs, justTouched
    end
end



--[[
        Synopsis:       Determine if target file content is different than source file content.

        Motivation:     Keeps unchanged targets from being updated if not necessary.

        Notes:          Works in protected mode to avoid bombing upon io failure.

                        Tests a relatively small block first, then does larger ones from there on out.
                        
        Returns:
            true, nil        - file are same content-wise.
            false, nil       - files are different - no error.
            nil, string      - indeterminable - error message returned.

        Examples:
            local same, problem = RcFileUtils.isFileSame( path1, path2 )
            if not problem then
                if same
                    -- dont update
                else
                    -- update target
                end
            else
                -- process error message
            end
--]]
function RcFileUtils.isFileSame( path1, path2 )

    if RcUtils.debugMode then -- keep lean if not trying to debug.
        assert( RcFileUtils.existsAsFile( path1 ), "File1 not found: " .. path1 )
        assert( RcFileUtils.existsAsFile( path2 ), "File2 not found: " .. path2 )
    end

    -- first check file sizes
    local size1 = LrFileUtils.fileAttributes( path1 ).fileSize
    local size2 = LrFileUtils.fileAttributes( path2 ).fileSize
    if size1 ~= size2 then return false end

    local success, file1, file2, errorMessage
    success, file1, errorMessage = LrTasks.pcall( io.open, path1, "rb" ) -- read-binary
    if success then
        if file1 then -- io-open returned a happy file handle
            success, file2, errorMessage = LrTasks.pcall( io.open, path2, "rb" ) -- read-binary
            if success then
                if file2 then
                    -- good
                else
                    file1:close()
                    return nil, "io-open error: " .. RcLua.toString( errorMessage ) .. ", path2: " .. path2
                end
            else
                file1:close()
                return nil, "Protected call to io-open failed, path2: " .. path2
            end
        else
            return nil, "io-open error: " .. RcLua.toString( errorMessage ) .. ", path1: " .. path1
        end
    else
        return nil, "Protected call to io-open failed, path1: " .. path1
    end
    -- fall-through => pcall success, and both files opened for reading.
    local blockSize = 32000 -- read a relatively small chunk first (about same size as default cluster for big disks on windows),
        -- in case difference is there (more efficient).
    local block1, block2

    local same = true
    assert( errorMessage == nil, "Program failure - got unexpected error message." )
    
    repeat -- until break
        success, block1 = LrTasks.pcall( file1.read, file1, blockSize )
        if success then -- call completed
            success, block2 = LrTasks.pcall( file2.read, file2, blockSize )
            if success then -- call completed
                if block1 then -- data read
                    if block2 then -- data read
                        if block1 == block2 then -- data same - I'm guessing modern hardware performs this comparison pretty fast, no?
                            -- continue
                        else
                            same = false
                            break
                        end
                    else
                        same = false
                        break
                    end
                elseif not block2 then
                    break -- out of data in both files, and no discrepancies so far.
                else
                    same = nil
                    errorMessage = "IO error reading file2: " .. path2
                    break
                end
            else
                -- same = false
                break
            end
        else
            same = nil
            errorMessage = "IO error reading file1: " .. path1
            break
        end
        blockSize = 1000000 -- ~1MB at a time hereafter. Hope this not too big...
    until true -- break to exit loop

    local ok1 = RcFileUtils.closeFile( file1 )
    local ok2 = RcFileUtils.closeFile( file2 )
    
    return same, errorMessage -- ignoring file closure errors.
end



--[[    *** SAVE FOR POSSIBLE FUTURE RESURRECTION.

        Synopsis:       Change last modified date to current date-time.

        Motivation:     Support for Photooey, which renders a file without knowing whether
                        it really needs to be done. If it doesn't then it opts to touch
                        the target, so its less likely to be rendered again next time.

        Notes:          - dependent libraries lack support for touching, so file is read, deleted,
                          then re-written instead.
    
        Returns:        true, nil:          worked, no comment.
                        true, comment:      pretending it worked - test mode message.
                        false, comment:     failed, error message.
--] ]
function RcFileUtils.touch( filePath )
    local sts, contents, qual
    contents, qual = RcFileUtils.readFile( filePath )
    if contents and not qual then -- read file works even in test mode.
        LrFileUtils.delete( filePath ) -- ### robusten/protect.
        sts, qual = RcFileUtils.writeFile( filePath - contents )
        return sts, qual
    else
        return false, LOC( "$$$/X=Unable to touch file: ^1, more: ^2", filePath, RcLua.toString( qual ) )
    end
end
--]]



--[[
        Synopsis:       closes a file protectedly.

        Returns:        - true:             good
                        - false:            bad
--]]
function RcFileUtils.closeFile( fileHandle )
    local ok = pcall( fileHandle.close, fileHandle )
    return ok
end



--[[
        Synopsis:       Returns entire contents of file.

        Motivation:     Runs in protected mode so export does not die upon first io failure.

        Returns:        - contents, nil:        read - no comment.
                        - nil, comment:         failed.
--]]
function RcFileUtils.readFile( filePath )
    local msg = nil
    local contents = nil
    local ok, fileOrMsg = pcall( io.open, filePath, "rb" )
    if ok and fileOrMsg then
        local contentsOrMsg
        ok, contentsOrMsg = pcall( fileOrMsg.read, fileOrMsg, "*all" )
        if ok then
            contents = contentsOrMsg
        else
            msg = LOC( "$$$/X=Read file failed, path: ^1, additional info: ^2", filePath, RcLua.toString( contentsOrMsg ) )
        end
        RcFileUtils.closeFile( fileOrMsg ) -- ignore return values.
    else
        msg = LOC( "$$$/X=Unable to open file for reading, path: ^1, additional info: ^2", filePath, RcLua.toString( fileOrMsg ) )
    end
    return contents, msg
end



--[[
        Synopsis:       Write entire contents of file.

        Motivation:     - Runs in protected mode so export does not die upon first io failure.
                        - test mode aware.

        Returns:        - true, nil:        written - no comment.
                        - true, comment:    pretend written - test mode comment.
                        - nil/false, comment:     failed.
--]]
function RcFileUtils.writeFile( filePath, contents )
    local msg = nil
    local ok
    if not RcUtils.testMode then
        local fileOrMsg
        ok, fileOrMsg = pcall( io.open, filePath, "wb" )
        if ok then
            local orMsg
            ok, orMsg = pcall( fileOrMsg.write, fileOrMsg, contents )
            if ok then
                -- good
            else
                msg = LOC( "$$$/X=Cant write file, path: ^1, additional info: ^2", filePath, RcLua.toString( orMsg ) )
            end
            ok = RcFileUtils.closeFile( fileOrMsg )
            if not ok then
                msg = LOC( "$$$/X=Unable to close file that was open for writing, path: ^1", filePath )
            end
        else
            msg = LOC( "$$$/X=Cant open file for writing, path: ^1, additional info: ^2", filePath, RcLua.toString( fileOrMsg ) )
        end
        return ok, msg
    else
        return true, "WOULD write file, path: " .. filePath
    end
end



--[[
        Synopsis:       Write entire contents of file.

        Motivation:     - Runs in protected mode so export does not die upon first io failure.
                        - test mode aware.

        Returns:        - true, nil:        written - no comment.
                        - true, comment:    pretend written - test mode comment.
                        - nil/false, comment:     failed.
--]]
function RcFileUtils.writeFile( filePath, contents )
    local msg = nil
    local ok
    if not RcUtils.testMode then
        local fileOrMsg
        ok, fileOrMsg = pcall( io.open, filePath, "wb" )
        if ok and fileOrMsg then
            local orMsg
            ok, orMsg = pcall( fileOrMsg.write, fileOrMsg, contents )
            if ok then
                -- good
            else
                msg = LOC( "$$$/X=Cant write file, path: ^1, additional info: ^2", filePath, RcLua.toString( orMsg ) )
            end
            ok = RcFileUtils.closeFile( fileOrMsg )
            if not ok then
                msg = LOC( "$$$/X=Unable to close file that was open for writing, path: ^1", filePath )
            end
        else
            ok = false
            msg = LOC( "$$$/X=Cant open file for writing, path: ^1, additional info: ^2", filePath, RcLua.toString( fileOrMsg ) )
        end
        return ok, msg
    else
        return true, "WOULD write file, path: " .. filePath
    end
end



--[[
        Synopsis:           Counts directory entries.
        
        Notes:              - In case preparation needs be done before loop processing dir entries, I guess.
                            - Assumes specified directory is known to exist: does not check.
        
        Returns:            number
--]]        
function RcFileUtils.numOfDirEntries( path )

    local c = 0
    for dirEnt in RcFileUtils.directoryEntries( path ) do
        c = c + 1
    end
    return c
    
end



--[[
        Synopsis:           Handles case when exact case of file on disk is important.
        
        Notes:              - First use case is for looking up in catalog afterward.
                            - Very inefficient for large directories- best confined to small dirs if possible.
        
        Returns:            path or nil.
--]]        
function RcFileUtils.getExactPath( _path )
    local dir = LrPathUtils.parent( _path )
    local path = LrStringUtils.lower( _path )
    for filePath in LrFileUtils.files( dir ) do
        local path2 = LrStringUtils.lower( filePath )
        if path == path2 then
            return filePath
        end
    end
    return nil
end 



return RcFileUtils
