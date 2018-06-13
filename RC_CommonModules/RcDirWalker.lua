--[[================================================================================

Filename:           RcDirWalker.lua - *** DEPRECATED FOR LR3+ WHICH INCLUDES RECURSIVE DIR/FILE ITERATOR.
                    (Makes more sense to implement as an iterator instead of a callback anyway).
                    Presently only used in tree-sync. Once that is converted to Lr3-only,
                    maybe using publish, but definitely using collection sync, if jf don't come through,
                    with the stack support.

Synopsis:           Supports walking a directory - calls back to calling context
                    and passes each directory entry to it.

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


local DirWalker = {}


assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- LR dependencies, may come from lightroom or emulation in non-lightroom environment:
local LrErrors = RcModuleLoader.import( 'LrErrors' )
local LrFileUtils = RcModuleLoader.import( 'LrFileUtils' )
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )

-- RC dependencies:
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )





-----------------
-- public methods
-----------------



--[[
        Synopsis:       Construct a new dir-walker.
        
        Notes:          May be constructed out of thin-air or starting from the one passed in.
--]]
function DirWalker:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end



--[[
        Synopsis:       One time initialization.
        
        Notes:          Probably could have tossed into the constructor, but I'm kinda on this kick
                        where constructors are parameter-less, and init routines follow with parameters.
                        Can't remember why I started this...
--]]                        
function DirWalker:init( funcForDirEntryProcessing )
    self.callback = funcForDirEntryProcessing
end



--[[
        Synopsis:       Begin directory traversal.
        
        Notes:          Returns when finished, or aborted.
--]]   
function DirWalker:walk(dir,noFolders,noFiles,noRecurse)

    self.abortFlag = false
    self:_walkFolder(dir,noFolders,noFiles,noRecurse)

end



--[[
        Synopsis:       Abort directory traversal.
--]]
function DirWalker:abort()

    self.abortFlag = true

end





-------------------
-- private methods:
-------------------



--[[
        Synopsis:       Visit each node of target tree.
        
        Notes:          Calls back to calling context with each node visited.
        
                        Presently using breadth first algorithm, which is appropriate
                        for dealing with high level stuff first. OK to delete folders
                        or files in callback - one of the reasons its breadth first -
                        no reason to process low-level dir-entries if they're going to
                        be deleted at the higher level.
--]]
function DirWalker:_walkFolder(pathToFolder,noFolders,noFiles,noRecurse)

    local dirEntry
    local folders = {}
    local files = {}
    local index

    local nFolders = 0
    local nFiles = 0

    for dirEntry in LrFileUtils.directoryEntries( pathToFolder ) do
        local leafName = LrPathUtils.leafName( dirEntry )
        if RcString.getFirstChar( leafName ) == '.' then
            -- ignore hidden files or "parent" directories - this could be configurable, but I think for lightroom purposes we never want to see hidden files.
        else
            local exists = LrFileUtils.exists( dirEntry )
            if exists then -- file or dir, not false.
                if exists == 'file' then
                    files[nFiles] = dirEntry
                    nFiles = nFiles + 1
                elseif exists == 'directory' then
                    folders[nFolders] = dirEntry
                    nFolders = nFolders + 1
                else
                    error( "Directory entry must be either file or directory: " .. dirEntry )
                end
            else
                RcUtils.logError( LOC( "$$$/X=Directory entry disappeared: ^1", dirEntry ) )
            end
        end
    end


	if not noFiles then
	    index = 0
	    while index < nFiles do
	        if self.abortFlag then return end
	        self.callback( files[index], "f" )
	        index = index + 1
	    end
	end

	if not noFolders then 
	    index = 0
	    while index < nFolders do
	        if self.abortFlag then return end
	        self.callback( folders[index], "D" )
	        index = index + 1
	    end
	end

	if not noRecurse then
	    index = 0
	    while index < nFolders do
	        if self.abortFlag then return end
	        local exists = LrFileUtils.exists( folders[index] )
	        if exists and ( exists == 'directory' ) then
	            self:_walkFolder( folders[index] )
	        else
	            -- presumably was deleted in the callback
	        end
	        index = index + 1
	    end
	end

end


return DirWalker