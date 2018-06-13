--[[================================================================================

Filename:           RcUtils2.lua

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

Edit History:       2011-06-23: Created by Rob Cole.

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


-- define this module:
local RcUtils2 = {}


-- Evaluate pre-requisites:
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )
assert( RcUtils ~= nil, "RcUtils not pre-loaded???" )


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

-- My Modules
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcTable = RcModuleLoader.loadRcModule( 'RcTable' )
-- local RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )
local RcDateTimeUtils = RcModuleLoader.loadRcModule( 'RcDateTimeUtils' )


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
function RcUtils2.executeCommand( exeFile, _params, _targets, outPipe, outHandling )
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
    
    if LrPathUtils.isRelative( exeFile ) or RcFileUtils.existsAsFile( exeFile ) then
    
        --   E X E C U T E   C O M M A N D
        local s, m = RcUtils.execute( cmd )
        if not s or not RcString.is( outHandling ) then
            return s, m
        end
        
        -- fall-through => executed and need to handle output.
        if RcFileUtils.existsAsFile( outPipe ) then
            local content, orNot = RcFileUtils.readFile( outPipe )
            local sts, msg
            if RcString.is( content ) then
                sts, msg = true, m
            else
                sts, msg = false, "Unable to read content of output file, error message: " .. (orNot or 'nil') .. ", command: " .. cmd -- errm includes path.
            end
            if outHandling == 'del' then
                -- local s, m = fso:deleteFolderOrFile( outPipe )
                local s, m = true, nil
                RcFileUtils.deleteFileConfirm( outPipe ) -- ignores lr-delete return code and just checks checks for deleted file a few times.
                if s then
                    return sts, msg, content
                else
                    return false, "Unable to delete output file: " .. m .. ", command: " .. cmd -- error message includes path.
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

return RcUtils2