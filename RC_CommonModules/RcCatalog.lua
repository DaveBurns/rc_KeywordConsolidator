--[[================================================================================

Filename:           RcCatalog.lua

Synopsis:           Supports modular lua programs.

Dependencies:       - Lr3.0+

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

Edit History:       2010-09-13: Created by Rob Cole...

------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


local LrApplication = import 'LrApplication'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrTasks = import 'LrTasks'
local LrStringUtils = import 'LrStringUtils'


local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )



local RcCatalog = {}



----------------------------------------

--    P R I V A T E   F U N C T I O N S

----------------------------------------




--------------------------------------

--    P U B L I C   F U N C T I O N S

--------------------------------------



--[[
        Synopsis:           See if photo obtained by disk path, is in the catalog, even if under different case extension.
        
        Notes:              - Use when file found initially on disk and may be in catalog under a different case.
                            - There is another technique I've used called "find photo in catalog by desparate means" which
                              iterates every photo in the catalog doing case-insensitive compare - it should be reserved
                              for case when photo really should exist but not found first try.
        
        Returns:            
--]]        
function RcCatalog.getPhotoByPathIgnoringExtCase( path )
    local photo = catalog:findPhotoByPath( path )
    if photo then
        return photo
    else
        local ext = LrPathUtils.extension( path )
        if ext == nil then return nil end
        ext = LrStringUtils.upper( ext )
        local _path = LrPathUtils.replaceExtension( path, ext  )
        photo = catalog:findPhotoByPath( _path )
        if photo then
            return photo
        else
            ext = LrStringUtils.lower( ext )
            _path = LrPathUtils.replaceExtension( path, ext  )
            photo = catalog:findPhotoByPath( _path )
            if photo then
                return photo
            end
        end
    end
    return nil
end



--[[
        Synopsis:           Add photo to stack if not already.
        
        Notes:              - Will wrap in with-write gate if dictated by calling context.
                            - Presence of stacking photo should be pre-determined on disk before calling,
                              it will be automatically added to catalog if not already.
                              
                            *** CASE MUST BE EXACT, SINCE CATALOG IS CASE SENSITIVE.
                            Actually its worse than that, find is case sensitive, but add is not.
                            So trying to assure a photo that exists in a different case will always fail.
                            
                            For the initial applicaton (nx-tooey), stack-path is always the base raw file,
                            which is case-normalized using rc-file-utils:get-exact-path.
                            
                            On the other hand the photo being added has not been normalized.
                            The main reason is for performance, and because the case should be
                            correct if its a file having been created by nx-tooey. I've
                            made a note in the doc not to rename files with different case.
        
        Returns:            X - throws errors...
--]]        
function RcCatalog.assurePhotoInStack( path, stackPath, position, wrapped )
    assert( _G.catalog ~= nil, "global catalog not init" )
    local stackPhoto
    local photo = catalog:findPhotoByPath( path )
    if photo then
        return photo
    end
    local guts = function()
        if stackPath ~= nil then
            if position and position == 'above' or position == 'below' then
                stackPhoto = catalog:findPhotoByPath( stackPath )
                if not stackPhoto then
                    stackPhoto = catalog:addPhoto( stackPath ) -- works or error.
                end
                photo = catalog:addPhoto( path, stackPhoto, position )
            else
                error( "stack photo path specified but postion is invalid: " .. RcLua.toString( position ) )
            end
        else
            photo = catalog:addPhoto( path ) -- note: there seems to be a difference between passing a nil param and not passing the param.
        end
    end
    local sts, msg
    if wrapped then
        sts, msg = LrTasks.pcall( guts )
    else
        local name = LrPathUtils.leafName( path )
        sts, msg = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Add " .. name .. " to catalog.", guts )
    end
    if sts then
        -- cant log - no rc-utils
    else
        RcUtils.logInfo( "Unable to add " .. path .. ", error message: " .. msg )
        error( "rc-catalog can't add photo: " .. RcLua.toString( path ) .. ", error message: " .. RcLua.toString( msg ) )
    end
    return photo, stackPhoto
end



--[[
        Synopsis:           Move photo not in catalog to recycle bin.
        
        Notes:              - Initial application for nx-tooey to kill a tif when a cooked edit is aborted.
        
        Returns:            X - throws error if trouble.
--]]        
function RcCatalog.trashFileIfNotInCatalog( path )
    assert( _G.catalog ~= nil, "global catalog not init" )

    local photo = catalog:findPhotoByPath( path )
    if not photo then
        local sts, msg = RcFileUtils.moveToTrash( path )
        if not sts then
            error( msg )
        end
    end

end



--[[
        Synopsis:           Gets truly selected photos.
        
        Notes:              - Purpose is to avoid target the whole filmstrip if nothing is selected, unless that is the intention.
        
        Returns:            array of photos or nil.
--]]        
function RcCatalog.getSelectedPhotos()

    if _G.catalog == nil then -- not sure why I'm not relying on global else error(?)
        _G.catalog = LrApplication.activeCatalog()
    end
    
    local test = catalog:getTargetPhoto()
    if test then -- at least one is selected
        return catalog:getTargetPhotos() -- return all selected
    else
        return nil -- do not return the entire filmstrip!
    end

end



--[[
        Synopsis:           Select a photo.
        
        Notes:              - Purpose is not to alter users selected photo set, but to just to make sure a recently worked on photo gets limelight,
                              partly to draw attention, but also to make sure thumbnail gets re-rendered.
        
        Returns:            X
--]]        
function RcCatalog.selectPhoto( photo )
    if photo == nil then
        return -- silently ignore if photo not specified - generally this is an aesthetic as opposed to a critical thing,
            -- so lets not go making big problems out of small ones, eh?
    end
    local photos
    photos = RcCatalog.getSelectedPhotos()
    if not photos then
        photos = { photo }
    end
    catalog:setSelectedPhotos( photo, photos )
end



return RcCatalog