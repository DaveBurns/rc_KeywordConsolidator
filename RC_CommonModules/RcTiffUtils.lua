--[[
        Filename:           RcTiffUtils.lua
        
        Synopsis:           Mostly rc-app-specific metadata support.

        Notes:              This module based on tiffdump.c which I got from Handmade Software, Inc.
                            - written by Allan N. Hessenflow. - Not sure how up-to-date it is.

        Public Functions:   - readFile
                            - reWriteFile

        Public Constants:   None.
             

--]]


local RcTiffUtils = {}


assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


local LrFileUtils = RcModuleLoader.import( 'LrFileUtils' )
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )
local LrTasks = RcModuleLoader.import( 'LrTasks' )
local LrErrors = RcModuleLoader.import( 'LrErrors' )

local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcUtils = RcModuleLoader.loadRcModule( 'RcUtils' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )

local logMessageLine = RcUtils.logMessageLine






local rcBlockType = 0xE7 -- presently writes this type - not an app1 tag.
    -- will recognize any app block type - in case future requires the written type to change.
local rcMetadataSignature = 'com.robcole.tiff.metadata' -- this will be preceded by FF E7 {len1} {len2}
    -- Note: I could use a regex for matching the prefix too, but I'm not.

local xmpBlockType = 0xE1 -- typical app1 block tag.
local xmpMetadataSignature = 'http://ns.adobe.com/xmp/extension/' .. string.char( 0 ) -- this will be preceded by FF E1 {len1} {len2}
	-- note: there may be more than one of these in the file - I'm hoping the best one is always first - if not, it will need to be fixed.


local littleEndian = false



-- debugging support
local _moduleName = "RcTiffUtils"
local function _debugTrace( id, info )
    assert( RcString.is (_moduleName), "Module name must be defined." )
    RcUtils.debugTrace( _moduleName .. " - " .. id, info, false ) -- use true to enable id as message prefix.
end



--[[
        Synopsis:           Reads one byte from a file.
        
        Returns:            Numerical value of the byte, else nil for eof.
--]]
local function _getByte( file )
    local char = file:read( 1 )
    if char ~= nil then
        return string.byte( char )
    else
        return nil
    end
end



--[[
        Synopsis:           Reads one byte from a file.
        
        Returns:            Numerical value of the byte, else nil for eof.
--]]
local function _getWord( file )
    local b1 = _getByte( file )
    if b1 == nil then return nil end
    local b2 = _getByte( file )
    if b2 == nil then return nil end
    if littleEndian then
        return b2 * 256 + b1
    else
        return b1 * 256 + b2
    end
end


--[[
--]]
local function _getDouble( file )
    local word2 = _getWord( file )
    if word2 == nil then return nil end
    local word3 = _getWord( file )
    if word3 == nil then return nil end
    return word3 * 65536 + word2 -- assuming ls-word first. not sure if this has been tested.
end



--[[
        Synopsis:           Gets specified number of bytes from a file.
        
        Returns:            String of bytes, else nil for eof.
        
        Notes:              throws an error if specified number of bytes are not available.
--]]
local function _getBytes( file, howMany )
    local chars = file:read( howMany )
    if chars ~= nil then
        local charLength = string.len( chars )
        if charLength == howMany then
            -- good
        else
            error( "file read underflow" )
        end
        return chars
    else
        return nil
    end
end



function RcTiffUtils.getIfdTableOffset( file )

    local byte0 = _getByte( file )
    local byte1 = _getByte( file )
    if byte0 and byte1 then
        -- good
    else
        return nil
    end
    if byte0 == 0x49 and byte1 == 0x49 then
        littleEndian = true
    elseif byte0 == 0x4D and byte1 == 0x4D then
        littleEndian = false
    else
        return "No endian"
    end
    local word1 = _getWord( file )
    if word1 == nil then return nil end
    if word1 == 42 then
        local word2 = _getWord( file )
        if word2 == nil then return nil end
        local word3 = _getWord( file )
        if word3 == nil then return nil end
        return word3 * 65536 + word2 -- assuming ls-word first. this is tested?
    else
        return "Not tif."
    end
    
end


function RcTiffUtils.getIfdTable( file )

    local ofs = RcTiffUtils.getIfdTableOffset( file )
    if ofs == nil then return nil end
    if type( ofs ) == 'number' then
        --
    elseif type( ofs ) == 'string' then
        return nil, ofs
    else
        error( "Program failure - invalid response from get-ifd-offset." )
    end
    
    local sts, erm = file:seek("set", ofs ) -- set file pointer to ifd table.
    if sts ~= nil then
        -- good
    else
        return nil, erm
    end
    
    local num = _getWord( file )
    if num == nil then return nil end
    if num > 1 then
        -- good
        if num < 1000 then
            return num
        else
            return nil, "too many ifd"
        end
    else
        return nil, "invalid ifd table"
    end
    
end




function RcTiffUtils.getIfd( file )
    local ifd = {}
    ifd.tag = _getWord( file )
    if ifd.tag == nil then return nil end
    ifd.type = _getWord( file )
    if ifd.type == nil then return nil end
    ifd.count = _getDouble( file )
    if ifd.count == nil then return nil end
    ifd.valueOffset = _getDouble( file )
    if ifd.valueOffset == nil then return nil end
    return ifd
end

--[[function _dumpRemainingBytes( file )
    local s = file:read( "*a" )
    _debugTrace( "len: ", RcLua.toString( s:len() ) )
    _debugTrace( "str: ", RcLua.toString( s ) )
end--]]
    

function _dumpRemainingBytes( file )
    local char
    local i = 1
    repeat
       char = _getByte( file )
       if char == nil then return end
       _debugTrace( "byte ", RcLua.toString( i ) .. ": " .. char )
       i = i + 1
    until false
end



function RcTiffUtils.findMainRGBImage( file )
    local num, msg = RcTiffUtils.getIfdTable( file )
    if num == nil and not RcString.is( msg ) then return nil end
    if num then
        -- good
        _debugTrace ( "number of ifds: ", RcLua.toString( num ) )
    else
        return nil, "ifd table trouble: " .. RcLua.toString( msg )
    end
    
    local ifd = nil
    
    for i = 0, num - 1 do
        ifd = RcTiffUtils.getIfd( file ) -- 12 bytes returned as table
        if ifd == nil then return nil, "ifd underflow" end
        local m = LOC( "$$$/X=index: ^1, tag: ^2, type: ^3, count: ^4, value-offset: ^5", i, ifd.tag, ifd.type, ifd.count, ifd.valueOffset )
        _debugTrace( "ifd table entry - ", m )
        if ifd.count > 1000000 then -- presently, if block is greater than 10MB its assumed to be the main image!
            if ifd.count < 10000000 then -- and less than 100MB
                break
            else
                -- return nil, "invalid ifd count: " .. RcLua.toString( ifd.count )
                ifd = nil
            end
        else
            ifd = nil
        end
    end
    
    if ifd ~= nil then
        return ifd
    else
        return nil, "no main image"
    end
    
end


function RcTiffUtils.getMainRGBImage( file )
    local ifd, msg = RcTiffUtils.findMainRGBImage( file )
    local ofs = nil
    if ifd ~= nil then
        ofs = ifd.valueOffset
    else
        return nil, "no main image: " .. RcLua.toString( msg )
    end
    
    return "image at " .. RcLua.toString( ofs )
    
end



--[[
        Synopsis:       Reads a tif file and returns a string for printing only.
--]]        
function RcTiffUtils.replaceMainRGBImage( file, image )

    local adj

    local ofs = getIFDOffest( file )
    if type( ofs ) == 'number' then
        --
    elseif type( ofs ) == 'string' then
        return nil, ofs
    else
        error( "Program failure - invalid response from get-ifd-offset." )
    end
    
    local sts, erm = file:seek("set", ofs ) -- set file pointer to ifd table.
    if sts ~= nil then
        -- good
    else
        return nil, erm
    end
    
    local num = _getWord( file )
    if num == nil then return nil end
    if num > 1 then
        -- good
        if num < 1000 then
            -- good
        else
            return nil, "too many ifd"
        end
    else
        return nil, "invalid ifd table"
    end
    
    local ifd
    for i = 0, num - 1 do
        ifd = RcTiffUtils.getIfd( file ) -- 12 bytes returned as table
        if ifd then
            if ifd.count > 10000000 then -- presently, if block is greater than 10MB its assumed to be the main image!
                break
            else
                ifd = nil
            end
        else
            return nil, "ifd table underflow"
        end
    end
    
    if ifd then
        return ifd
    else
        return nil, "no main image"
    end
        
    
    
end





return RcTiffUtils
