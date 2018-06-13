--[[================================================================================

Filename:           KeywordConsolidator_ServiceProvider.lua

Synopsis:           Implements KwC - File Menu Plug-in Extra.

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

Edit History:       2010-07-03: Created by Rob Cole...
      
------------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

================================================================================--]]


-- Define this module.
local KwC = {}


-- Lightroom Modules
local LrApplication = import 'LrApplication'
local LrPathUtils = import 'LrPathUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrBinding = import 'LrBinding'
local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrLogger = import 'LrLogger'
local LrErrors = import 'LrErrors'
local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'
local LrStringUtils = import 'LrStringUtils'
local LrSystemInfo = import 'LrSystemInfo'
local LrStringUtils = import 'LrStringUtils'

-- My Modules

assert( RcModuleLoader, "no module loader in svc provider" ) 
assert( RcUtils, "no rc-utils in svc provider" ) 

local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcNumber = RcModuleLoader.loadRcModule( 'RcNumber' )
local RcTable = RcModuleLoader.loadRcModule( 'RcTable' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )
local RcGui = RcModuleLoader.loadRcModule( 'RcGui' )


-- constants


-- module variables
local catalog
local vf -- os-view-factory.
local prefs
local selectedPhoto
local targetPhotos
local quit = false
local quitMessage = ''
local ignoreNames = {} -- name pairs to ignore
local ignorePaths = {}
local yc = 0 -- yield counter.
local consolidationQueue = {} -- list of items to consolidate, can cover multiple keywords
local nameToIds = {}
local synonymToIds = {}


-- stats
local nLogged = 0
local nNameIgnoresSkipped = 0 -- names
local nPathIgnoresSkipped = 0 -- names
local nConsolidationsSkipped = 0
local nConsolidated = 0 -- not ignored.
local nNamesIgnored = 0 -- ignored name pairs.
local nPathsIgnored = 0 -- ignored path pairs.
local nDuplicates = 0
local nParentsRemoved = 0
local nWereNotAssigned = 0


-- convenience
local logMessage = RcUtils.logMessage
local logMessageLine = RcUtils.logMessageLine
local logWarning = RcUtils.logWarning
local logError = RcUtils.logError
local VERBOSE = RcUtils.VERBOSE
local showError = RcUtils.showError
local showWarning = RcUtils.showWarning
local showInfo = RcUtils.showInfo


-- debugging support
local _debugMode = true -- ###1 set false before releasing - module level debug flag, as distinguished from rc-utils debug flag.
local function _debugTrace( id, info )
    if _debugMode then
        RcUtils.debugTrace( "KwC/SP | " .. id, info, true ) -- include ID as message prefix.
    end
end



--[[
		Synopsis:			Logs an error and shows it to the user, and offers option to abort.
--]]
local function _showError( msg )
    RcUtils.logError( msg )
	local action = RcUtils.showError( msg, "Keep Going", "Quit" )
	if action == 'ok' then
		return false -- keep going
	else
		assert( action == 'cancel', "unexpected error action: " .. RcLua.toString( action )  )
		return true -- enough
	end
end



--[[
		Synopsis:			Show user there's been a potential problem, and offer option to abort.
--]]
local function _showWarning( msg )
	RcUtils.logWarning( msg )
	local action = RcUtils.showWarning( msg, "Keep Going", "Quit" )
	if action == 'ok' then
		return false -- keep going
	else
		assert( action == 'cancel', "unexpected warning action: " .. RcLua.toString( action ) )
		return true -- enough
	end
end



--[[
        Synopsis:           Load table of name pairs to ignore.
        
        Notes:              Logs warning if not found - which will always be the case the first time its run.
        
        Returns:            Nothing.
--]]        
function KwC._loadIgnoreTable()
    ignoreNames = {}
    ignorePaths = {}
    local path
    path = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), "RcKeywordConsolidatorSupport.lua" )
    if not RcFileUtils.existsAsFile( path ) then
        path = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), "KeywordConsolidatorSupport.lua" )
    end
    if RcFileUtils.existsAsFile( path ) then
        local sts, _ignore, _ignore2 = pcall( dofile, path )
        if sts then
            assert( ignoreNames ~= nil, "bad kw-support file" )
            ignoreNames = _ignore or {}
            ignorePaths = _ignore2 or {}
            if RcUtils.logVerbose then
                logMessageLine( "Using keyword-consolidator support file: " .. path )
                logMessageLine( "Names previously considered ignored (delete lines from support file to cease ignoring (or delete the whole file)" )
                if #ignoreNames then
                    for i,v in ipairs( ignoreNames ) do
                        logMessageLine( LOC( "$$$/X=Ignoring similarity between names ^1 and ^2", ignoreNames[i][1], ignoreNames[i][2] ) )
                    end
                else
                    logMessageLine( "No names to ignore." )
                end
                logMessageLine( "Paths previously considered ignored (delete lines from support file to cease ignoring (or delete the whole file)" )
                if #ignorePaths then                
                    for i,v in ipairs( ignorePaths ) do
                        logMessageLine( LOC( "$$$/X=Ignoring similarity between paths ^1 and ^2", ignorePaths[i][1], ignorePaths[i][2] ) )
                    end
                else
                    logMessageLine( "No paths to ignore." )
                end
            end
            logMessageLine()
        else
            local enough = _showError( "Keyword consolidator support file is corrupt, doing without: " .. path )
            if enough then
                quit = true
                quitMessage = 'bad support file'
            end
        end
    else
        logWarning( "Keyword consolidator support file does not exist (expected upon first use), doing without: " .. path )
        logMessageLine()
        -- ignore tables remain empty - not nil.
    end
end



--[[
        Synopsis:           Save table of name pairs to ignore for next time.
        
        Notes:              Filename hardcoded, location same as catalog.
        
        Returns:            
--]]        
function KwC._saveIgnoreTable()
    local luaBuf = {}
    luaBuf[#luaBuf + 1] = 'local _t={}'
    luaBuf[#luaBuf + 1] = 'local _p={}'
    if ignoreNames then
        for i,v in ipairs( ignoreNames ) do
            luaBuf[#luaBuf + 1] = '_t[#_t+1]={"' ..  ignoreNames[i][1] .. '","' .. ignoreNames[i][2] .. '"}'
        end
    end
    if ignorePaths then
        for i,v in ipairs( ignorePaths ) do
            luaBuf[#luaBuf + 1] = '_p[#_p+1]={"' ..  ignorePaths[i][1] .. '","' .. ignorePaths[i][2] .. '"}'
        end
    end
    luaBuf[#luaBuf + 1] = 'return _t,_p'
    local path = LrPathUtils.child( LrPathUtils.parent( catalog:getPath() ), "RcKeywordConsolidatorSupport.lua" )
    local luaStr = table.concat( luaBuf, '\n' )
    -- logMessageLine( luaStr )
    local sts, qual = RcFileUtils.writeFile( path, luaStr )
    if sts then
        if RcString.is( qual ) then
            logMessageLine( "WOULD save ignore tables in " .. path )
        else
            logMessageLine( "Saved ignore tables in " .. path )
        end
    else
        logWarning( "Unable to write Keyword consolidator support file: " .. path .. ", more: " .. RcLua.toString( qual ) )
    end
end



--[[
        Synopsis:           Initializes for manual run.

        Notes:              - Logger initialized based on preferences.
                            - Present incarnation supports manual run only.
--]]        
function KwC._init( opTitle )

    prefs = LrPrefs.prefsForPlugin()
    
    -- _debugTrace( "Test Mode: ", RcLua.toString( prefs.testMode ) )
    
    RcUtils.initService( prefs.testMode, prefs.logFilePath, prefs.logVerbose, prefs.logOverwrite, opTitle ) -- test mode is first param. - asserts failure if any param nil.
    -- RcUtils.initService( false, "RC_KwC_LogFile", true, true ) -- test mode is first param. - asserts failure if any param nil.
    -- note: set the logfilepath to blank to kill logging.
    
    -- _debugTrace( "initing" )
    
	vf = LrView.osFactory()
	catalog = LrApplication.activeCatalog()
	
end



--[[
        Synopsis:           Determines if one string is a substring of the other.
        
        Notes:              Tests both directions but does not distinguish in return code.
--]]
function KwC._isSubstring( s1, s2 )
    if s1:find( s2, 1, true ) then
        return true
    elseif s2:find( s1, 1, true ) then
        return true
    else
        return false
    end
end



--[[
        Synopsis:       Determine if two keywords are similar.
        
        Notes:          Keyword identity has been checked prior to calling, so two equal names are similar.
--]]        
function KwC._isSimilarName( name1, name2 )

    -- same exact?
    if name1 == name2 then
        nDuplicates = nDuplicates + 1
        return true
    end
    
    -- everything else will be case independent.
    local norm1 = LrStringUtils.lower( name1 )
    local norm2 = LrStringUtils.lower( name2 )
    
    local len1
    local len2
    len1 = string.len(name1)
    len2 = string.len(name2)
    if string.sub(norm1,1,1) == "\"" and string.sub(norm1,-1) == "\"" then
        norm1 = string.sub(norm1,2,len1-1)
        len1 = norm1:len()
    end
    if string.sub(norm2,1,1) == "\"" and string.sub(norm2,-1) == "\"" then
        norm2 = string.sub(norm2,2,len2-1)
        len2 = norm2:len()
    end
    
    
    -- same except for case:
    if norm1 == norm2 then
        nDuplicates = nDuplicates + 1
        return true
    elseif prefs.duplicatesOnly then
        return false
    end
    
    -- same length but not same except for case means different
    -- (probably true but not necessarily - some plurals may be same length as singular form, I assume)
    --[[if len1 == len2 then - this clause removed 2010-08-16 (RDC).
        return false
    end--]]
    
    -- note the only way for the substring match to be true and their lengths to be equal is if they were identical - but they're not.
    
    -- this clause added 2010-08-16 (RDC).
    if len1 <= 2 or len2 <= 2 then
        return false -- 1 & 2 character keywords shall not be considered similar to anything no matter what they are.
    end

    -- substring as is?    
    if prefs.similarities and KwC._isSubstring( norm1, norm2 ) then
        return true
    end
    
    if not prefs.plurals then
        return false
    end

    local plural1
    local plural2
    local sing1
    local sing2
    
    if RcString.isPlural( norm1 ) then
        -- _debugTrace( "Plural: ", norm1 )
        sing1 = RcString.makeSingular( norm1 )
        plural1 = norm1
    else
        -- _debugTrace( "Singular: ", norm1 )
        sing1 = norm1
        plural1 = RcString.makePlural( norm1 )
    end
    if RcString.isPlural( norm2 ) then
        sing2 = RcString.makeSingular( norm2 )
        plural2 = norm2
    else
        sing2 = norm2
        plural2 = RcString.makePlural( norm2 )
    end
    
    -- _debugTrace( "Plurals: ", LOC( "$$$/X=sing1: ^1, sing2: ^2, plural1: ^3, plural2: ^4", sing1, sing2, plural1, plural2 ) )

    
    -- note: substring test will be positive if they are equal.
    if prefs.similarities then
        if KwC._isSubstring( sing1, sing2 ) then
            return true
        end
    elseif sing1 == sing2 then
        return true
    end
    if prefs.similarities then
        if KwC._isSubstring( plural1, plural2 ) then
            return true
        end
    elseif plural1 == plural2 then
        return true
    end
    if prefs.similarities then
        if KwC._isSubstring( sing1, plural2 ) then
            return true
        end
    elseif sing1 == plural2 then
        return true
    end
    if prefs.similarities then
        if KwC._isSubstring( plural1, sing2 ) then
            return true
        end
    elseif plural1 == sing2 then
        return true
    end
    
    return false
    
end



--[[
        Synopsis:           Checks if pair of names are on the ignore list.
        
        Notes:              order is unimportant.
        
        Returns:            boolean
--]]        
function KwC._isOnIgnoreNamesList( name1, name2 )
    if ignoreNames then
        for i,v in ipairs( ignoreNames ) do
            if ((ignoreNames[i][1] == name1) and (ignoreNames[i][2] == name2)) or ((ignoreNames[i][1] == name2) and (ignoreNames[i][2] == name1)) then
                return true
            end
        end
    end
    return false
end



--[[
        Synopsis:           Determine if pair of keyword names should be ignored.
        
        Notes:              - Only called if not already on the ignore list.
                            Prompts user:
                            - Puts pair on ignore list if specified.
                            - or ignores just this time.
                            - or doesn't ignore.
        
        Returns:            boolean
--]]        
function KwC._isToBeIgnored( name1, name2 )

    local answer = RcUtils.showInfo( "Consider consolidating similarity?\n\n '" .. name1 .. "' and '" .. name2 .. "'", nil, "Not this time", "Never", "Yes" )
    -- _debugTrace( answer )
    if answer == "cancel" then -- never
        ignoreNames[#ignoreNames + 1] = { name1, name2 }
        logMessageLine( "Ignoring names forever: " .. name1 .. " and " .. name2 )
        nNamesIgnored = nNamesIgnored + 1
        return true
    elseif answer == "ok" then -- not this time
        logMessageLine( "Ignoring names for now: " .. name1 .. " and " .. name2 )
        nNameIgnoresSkipped = nNameIgnoresSkipped + 1
        return true
    elseif answer == 'other' then -- yes
        return false
    else
        error( "Invalid answer: " .. RcLua.toString( answer ) )
    end

end



--[[
        Synopsis:           Determine if pair of keyword paths should be ignored.
        
        Notes:              - Only called if not already on the ignore list.
                            Prompts user:
                            - Puts pair on ignore list if specified.
                            - or ignores just this time.
                            - or doesn't ignore.
        
        Returns:            boolean
--]]        
function KwC._isToBeIgnoredPaths( path1, path2 )

    local answer = RcUtils.showInfo( "Consider consolidating paths?\n\n '" .. path1 .. "' and '" .. path2 .. "'", nil, "Not this time", "Never", "Yes" )
    -- _debugTrace( answer )
    if answer == "cancel" then -- never
        ignorePaths[#ignorePaths + 1] = { path1, path2 }
        logMessageLine( "Ignoring paths forever: " .. path1 .. " and " .. path2 )
        nPathsIgnored = nPathsIgnored + 1
        return true
    elseif answer == "ok" then -- not this time
        logMessageLine( "Ignoring paths for now: " .. path1 .. " and " .. path2 )
        nPathIgnoresSkipped = nPathIgnoresSkipped + 1
        return true
    elseif answer == 'other' then -- yes
        return false
    else
        error( "Invalid answer: " .. RcLua.toString( answer ) )
    end

end



--[[
        Synopsis:           Get similar items to support consolidation.
        
        Notes:              item is the comparison item.
                            id is of item being compared.
                            
                            This could be considered the guts of whole thing - identifying the set of items
                            that are similar to a reference item.
                            
                            Calling context can just display a list of synonyms underneath main path.
                            
                            Note: this routine now prompts for similarity ignore-ance.
                                                        
        Returns:            hash of similar items, key'd by id where each entry has the following format:
                            - path.
--]]        
function KwC._isToBeIncludedDueToSimilarity( _id, item1 )

    -- _debugTrace( "Testing for item similarity, item1: ", item1.mainPath .. ", item2: " .. kwMap[_id].mainPath ) 
    local item2 = kwMap[_id]
    local name1 = item1.name
    local name2 = item2.name
    local syn1Ix = 1
    local syn2Ix = 1
    repeat
        -- _debugTrace( "Checking for similarity, name1: ", name1 .. ", name2: " .. name2 ) 
        if KwC._isOnIgnoreNamesList( name1, name2 ) then
            -- ignore
        elseif KwC._isSimilarName( name1, name2 ) then -- duplicates are similar.
            if not prefs.duplicatesOnly and prefs.promptForIgnore and KwC._isToBeIgnored( name1, name2 ) then
                -- ignore this time for sure, maybe forever...
            else
                return true -- note: ###2 - could indicate whether similarity is due to synonym, and if so which one(s)...
            end
        else
            -- not similar
        end
        if prefs.ignoreSynonyms then
            return false
        end        
        name2 = item2.synonyms[syn2Ix]
        if name2 == nil then
            name1 = item1.synonyms[syn1Ix]
            if name1 == nil then
                break
            else
                syn1Ix = syn1Ix + 1
            end
            name2 = item2.name
            syn2Ix = 1
        else
            syn2Ix = syn2Ix + 1
        end
            
    until false
    return false
end



--[[
        Synopsis:           Determines whether one item is the same as another item.
        
        Notes:              This is called to keep photo item from being compared to same mapped item.
        
        Returns:            boolean
--]]        
function KwC._isSame( id, item )

    if item.id == id then
        return true
    else
        return false
    end
    
end



--[[
        Synopsis:           Find candidates for matching with a particular item based on the current settings.
        
        Notes:              In the most general case, this will be the entire list of unprocessed keywords, but
							if the search criteria are tighter, the set will be far smaller for increased performance.
        
        Returns:            table of {id = true}, or empty if nothing similar.
--]]        
function KwC._findCandidates( item )

	if prefs.similarities then
		return kwToDo	-- have to do a full search of all keywords, for substrings
	else
		-- no substrings, so all matches must be singular or plural forms of this item's name or its synonyms 
		local lowerName = item.name
		local rawNames = { lowerName }
		if not prefs.ignoreSynonyms then
			for _,syn in pairs( item.synonyms ) do
				rawNames[ #rawNames + 1 ] = LrStringUtils.lower( syn )
			end
		end
		
		local pluralAndSingularNames = {}
		local func
		
		if prefs.plurals then
			for _,name in pairs( rawNames ) do
				pluralAndSingularNames[ #pluralAndSingularNames + 1 ] = name
				if RcString.isPlural( name ) then
					func = RcString.makeSingular
				else
					func = RcString.makePlural
				end
				
				local otherStyleName = func( name )
				if otherStyleName ~= name then
					pluralAndSingularNames[ #pluralAndSingularNames + 1 ] = otherStyleName
				end
			end
		else
			pluralAndSingularNames = rawNames
		end

		local candidates = {}
		for _,name in pairs( pluralAndSingularNames ) do
			if nameToIds[ name ] ~= nil then
				for _,id in pairs( nameToIds[ name ] ) do
					candidates[ id ] = kwToDo[ id ]
				end
			end
			
			if ( not prefs.ignoreSynonyms ) and synonymToIds[ name ] ~= nil then
				for _,id in pairs( synonymToIds[ name ] ) do
					candidates[ id ] = kwToDo[ id ]
				end
			end
		end
		
		return candidates

	end

end


--[[
        Synopsis:           Find all keyword items similar to specified keyword item.
        
        Notes:              Has side effect of clearing the to-do item before returning - this keeps
                            from doing it more than once.
        
        Returns:            array of id, or empty if nothing similar.
--]]        
function KwC._findSimilar( item )
    if not kwToDo[item.id] == nil then return nil end
    local similar = {}
	local candidates = KwC._findCandidates( item )
    for k,v in pairs( candidates ) do -- k is id, v is true or nil.
        if v == true and not KwC._isSame( k, item ) then
			local similar2 = KwC._isToBeIncludedDueToSimilarity( k, item ) -- array of similar items
			if similar2 then
				-- _debugTrace( "similar: ", name )
				similar[#similar + 1] = k -- just return the id - calling context can generate paths and synonym list.
			end
        end
    end
    -- _debugTrace( "never again not similar: ", name )
    kwToDo[item.id] = nil
    return similar
end



--[[
        Synopsis:           Logs items and similarities for post run consideration.
        
        Notes:              
        
        Returns:            
--]]        
function KwC._doLog( item, similar )

    nLogged = nLogged + 1
    logMessageLine( LOC("$$$/X=Log #^1 (for further consideration): ^2", nLogged, item.mainPath ) )
    if #item.synonyms > 0 then
        logMessageLine ( '    Synonyms: ' .. table.concat( item.synonyms, "," ) )
    end
    for i,v in ipairs( similar ) do
        local sim = kwMap[v]
        logMessageLine( "Similar: " .. sim.mainPath )
        if #sim.synonyms > 0 then
            logMessageLine( '    Synonyms: ' .. table.concat( sim.synonyms, "," ) )
        end
    end
       
    logMessageLine()
    
end



--[[
        Synopsis:           Determine if photo has the specified keyword.
        
        Notes:              Keyword is an lr-keyword proper.
        
        Returns:            t/f.
--]]        
function KwC._isPhotoHavingKeyword( photo, keyword )
    
    local keywords = photo:getRawMetadata( "keywords" )
    for i,v in ipairs( keywords ) do
        if v == keyword then
            return true
        end
    end
    return false

end



--[[
        Synopsis:           Create a callback function to consolidate one item whose source keyword is checked.
        
        Notes:              - Called for each item in response to an affirmative response to the prompt.
                            - all photos presently assigned to the source keyword will be assigned to all target
                              keywords instead. If keyword creation were supported it would be assigned to that too or instead.
        
        Returns:            nothing (function is appended to toDo)
--]]        
function KwC._doConsolidateOne( sourceId, targetIds, toDo )

    local item = kwMap[sourceId]

    logMessageLine( item.mainPath .. " will be emptied - consider deleting." )

    for _, targetId in ipairs( targetIds ) do
        if targetId ~= sourceId then
            local item2 = kwMap[targetId]
            logMessageLine( "Photos will be consolidated to: " .. item2.mainPath )
        end
    end

    local photos
    if selectedPhoto then
        photos = targetPhotos
    else
        photos = item.kw:getPhotos()
    end
    for i, photo in ipairs( photos ) do
    
        if not selectedPhoto or KwC._isPhotoHavingKeyword( photo, item.kw ) then
            toDo[#toDo + 1] = function()
                if RcUtils.testMode then
                    logMessageLine( "Photo: " .. photo:getRawMetadata( 'path' ) .. ", WOULD remove: " .. item.mainPath, VERBOSE )
                else
                    photo:removeKeyword( item.kw )
                    kwToDo[item.id] = nil
                    logMessageLine( "Photo: " .. photo:getRawMetadata( 'path' ) .. ", removed: " .. item.mainPath, VERBOSE )
                end
                for _, targetId in ipairs( targetIds ) do
                    local item2 = kwMap[targetId]
                    if RcUtils.testMode then
                        logMessageLine( "Photo: " .. photo:getRawMetadata( 'path' ) .. ", WOULD add: " .. item2.mainPath, VERBOSE )
                    else
                        photo:addKeyword( item2.kw )
                        logMessageLine( "Photo: " .. photo:getRawMetadata( 'path' ) .. ", added: " .. item2.mainPath, VERBOSE )
                    end
                end
            end
        end
        
    end
    
end



--[[
        Synopsis:           Creates or determines if it is alright to create specified keyword hierarchy.
        
        Notes:              Hierarchy is specified by sequential form fields.
                            Shows errors as they happen, then returns nil.
        
        Returns:            If just checking: t if user approved creation, or already existing. f if user denied creation.
                            If the real thing: id of newly created or already existing keyword, nil if error.
--]]        
function KwC._createKeywordHierarchy( formFields, justCheck )

    local parentKeyword = nil
    local name
    local syns
    local synt
    local inclExport
    local path = ""
    local ix = 0
    local found = nil

    -- check/update existing keywords
    for i,formEntry in ipairs( formFields ) do
    
        name = formEntry.name
        syns = formEntry.synonyms
        inclExport = formEntry.inclExport
        
        path = path .. '/' .. name
        
        -- _debugTrace( "considering keyword path: ", path )
        local found2 = false
        for k,v in pairs( kwMap ) do
            if path == v.mainPath then
                -- _debugTrace( "found2: ", path )
                found2 = v
                break
            end
        end
        if found2 then
            found = found2 -- item
            -- local attrs = found.kw:getAttributes() -- only way to get incl-export setting: synonyms nil so far.
            -- local keywordName = attrs.keywordName -- nil so far.
            local keywordName = found.kw:getName()
            if keywordName == found.name then
                if RcString.is( syns ) then -- user entered something in the synonym field for an existing keyword.
                    synt = RcString.split( syns, ',' )
                else
                    synt = {}
                end
                -- local synonyms = attrs.synonyms - nil so far
                local synonyms = found.kw:getSynonyms()
                local includeOnExport = found.kw:getAttributes().includeOnExport
                if not RcTable.isEmpty( synt ) or includeOnExport ~= inclExport then
                    local newAttrs = {}
                    -- newAttrs.keywordName = keywordName -- same. (nil => dont change)
                    newAttrs.synonyms = RcTable.merge( synonyms, synt )
                    newAttrs.includeOnExport = inclExport -- update - may or may not be different.
                    newSynonyms = table.concat( newAttrs.synonyms, ',' )
                    if newSynonyms ~= table.concat( synonyms, ',' ) or includeOnExport ~= inclExport then
                        if justCheck then
                            if RcUtils.isOk( "OK to set synonyms of " .. path .. " to '" .. newSynonyms .. "' and set 'Include On Export' to " .. tostring( newAttrs.includeOnExport ) .. "?" ) then
                                -- good
                            else
                                return false
                            end
                        else
                            local sts, other = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Update Attributes Of Keyword " .. name, function()
                                found.kw:setAttributes( newAttrs )
                            end )
                            if sts then
                                logMessageLine( "Set synonyms of " .. path .. " to '" .. newSynonyms .. "' and set 'Include On Export' to " .. tostring( newAttrs.includeOnExport ) )
                            else
                                showError( "Unable to update keyword attributes, error message: " .. RcLua.toString( other ) )
                                return nil
                            end                                
                        end
                    else
                        if justCheck then
                            showInfo( "Keyword '" .. path .. "' already exists - nothing to update.", "ExistingKeywordNoUpdate2" )
                        end
                    end
                else
                    if justCheck then
                        showInfo( "Keyword '" .. path .. "' already exists - nothing to update...", "ExistingKeywordNoUpdate" )
                    end
                end
            else
                showError( "Recorded keyword name: " .. RcLua.toString( found.name ) .. " does not match name read from catalog: " .. RcLua.toString( keywordName ) )
                if justCheck then
                    return false
                else
                    return nil
                end
            end
            ix = i
            -- keep going
        else
            -- 
            break
        end
    
    end
    
    parentKeyword = nil
    path = nil
    name = nil
    syns = nil
    inclExport= nil
    synt = nil
    
    if found then
        -- _debugTrace( "Found: ", found.mainPath .. ", ix: " .. tostring( ix ) )
        parentKeyword = found.kw
        path = found.mainPath
    else
        path = ''
        parentKeyword = nil
    end
    
    for i = ix + 1, #formFields do
    
        name = formFields[i].name
        syns = formFields[i].synonyms
        inclExport = formFields[i].inclExport
        
        -- _debugTrace( "Considering form name: ", RcLua.toString( name ) )
        
        synt = RcString.split( syns, ',' )
        path = path .. '/' .. name
        local newKw = nil
        if justCheck then
            -- _debugTrace( "checking keyword: ", LOC( "$$$/X=Name: ^1, syns: ^2, inclExport: ^3, path: ^4", name, syns, RcLua.toString( inclExport ), path ) )
            if RcUtils.isOk( "OK to create new keyword: " .. path .. "?" ) then
                -- 
            else
                return false
            end
        else
            -- _debugTrace( "creating keyword: ", LOC( "$$$/X=Name: ^1, syns: ^2, inclExport: ^3, path: ^4", name, syns, RcLua.toString( inclExport ), path ) )
            local sts, other = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Create Keyword", function()
                newKw = catalog:createKeyword( name, synt, inclExport, parentKeyword, true ) -- really need synonyms on a per keyword basis.
            end )
            if newKw then
                parentKeyword = newKw
                KwC._addMapEntry( LrPathUtils.parent( path ), newKw )
                -- kwToDo[newKw.id] = true - should be no need to consolidate this keyword, since its brand new, I think.
            else
                showError( "Unable to create keyword for photo: " .. path .. ", error message: " .. RcLua.toString( other ) )
                parentKeyword = nil
                break
            end
        end
    end
    if justCheck then
        -- _debugTrace( "returning check true" )
        return true
    elseif parentKeyword ~= nil then
        KwC._assureListMapEntries( path )
        -- _debugTrace( "returning id of keyword: ", kwMap[parentKeyword.localIdentifier].mainPath )
        return parentKeyword.localIdentifier -- will actually be target keyword id upon return.
    else
        return nil
    end

end



--[[
        Synopsis:           Create a keyword given the specified path and attribute.
        
        Notes:              Creates all parent keywords as necessary.
        
                            At the moment, just creates one final target keyword, but may be enhanced to look for a blank as separator and be able to do more than one.
        
        Returns:            true if created or already existed.
--]]        
function KwC._createKeywordHierarchies( props, justCheck )

    local newKeywordIds = {}
    local name
    local syns
    local inclExport
    local formFields = {}
    local checkValue = true
    
    for i = 1,12 do
    
        name = props['newKeywordName' .. tostring( i )]
        syns = props['newKeywordSynonyms' .. tostring( i )]
        inclExport = props['newKeywordExport' .. tostring( i )]
        
        if RcString.is(name) then
            formFields[#formFields + 1] = { name=name, synonyms=syns, inclExport=inclExport }
        else
            if #formFields > 0 then
                local keywordId = KwC._createKeywordHierarchy( formFields, justCheck )
                formFields = {}
                if justCheck then
                    if not keywordId then
                        checkValue = false
                        break
                    -- else keep checking
                    end
                else
                    if keywordId then
                        newKeywordIds[#newKeywordIds + 1] = keywordId
                    else
                        return nil
                    end
                end
            else
                break
            end
        end
    end
    if justCheck then
        -- _debugTrace( "Hierarchy check value: ", checkValue )
        return checkValue
    else
        -- _debugTrace( "Hierarchy create count: ", #newKeywordIds )
        return newKeywordIds
    end

end



--[[
        Synopsis:           Performs consolidation of all items presented in the prompt.
        
        Notes:              - Assembles a list of all items with source selected and another list with items having target selected.
                            - removes all photos from source keyword and assigns them to all targets instead.
        
        Returns:            true if not consolidated.
--]]        
function KwC._doConsolidate( item, similar, props )

    local sourceIds = {}
    if props[item.id .. "_sourceChecked"] then
        sourceIds[#sourceIds + 1] = item.id
    end 
    
    --[[if #sourceIds == 0 then - *** save as reminder: it may be valuable to be able to just update synonyms or created keywords without consolidating.
    -- and a note has been added to indicate nothing was consolidated, and to keep from moving on in that case.
        showInfo( "At least one source must be checked or there won't be anything to consolidate." )
        return true
    end--]]
    
    for _, id in ipairs( similar ) do
        if props[id .. "_sourceChecked"] then
            sourceIds[#sourceIds + 1] = id
        end
    end
    local targetIds = {}
    if props[item.id .. "_targetChecked"] then
        targetIds[#targetIds + 1] = item.id
    end 
    for _, id in ipairs( similar ) do
        if props[id .. "_targetChecked"] then
            targetIds[#targetIds + 1] = id
        end
    end

    -- _debugTrace( "keyword path ", props.newKeywordPath )
    -- _debugTrace( "keyword export ", props.newKeywordExport )
    -- local kwPath = '' .. props.newKeywordPath
    -- local synonyms = RcString.split( props.newKeywordSynonyms, "," )
    -- _debugTrace( "#Syns: ", #synonyms )
    -- _debugTrace( "Syn1: ", synonyms[1] )
    local kwArray = KwC._createKeywordHierarchies( props ) -- returns array of keyword ids - already added to map.
    if kwArray ~= nil then
        for i,v in ipairs( kwArray ) do
            -- local item = kwMap[v]
            -- kwToDo[item.id] = true
            -- _debugTrace( "manual target: ", kwMap[v].mainPath )
            targetIds[#targetIds + 1] = v
        end
    else
        -- _debugTrace( "kwcreate nil" )
    end

	local originalQueueSize = #consolidationQueue

    for i,v in ipairs( sourceIds ) do
        _debugTrace( "Consolidating one: ", kwMap[v].mainPath )
        KwC._doConsolidateOne( v, targetIds, consolidationQueue )
    end

	-- only do actual consolidations every so often, since doing a batch of modifications has a high fixed overhead
    if #consolidationQueue > 10 then
		KwC._commitConsolidations()
    elseif #consolidationQueue == originalQueueSize then
        showInfo( "Nothing was consolidated." )
    end
    
end



--[[
        Synopsis:           Performs the actual consolidations in the consolidation queue. 

		Notes:				Discards the queue whether successful or not
        
        Returns:            nothing
--]]        
function KwC._commitConsolidations( )

	logMessageLine( 'Committing ' .. #consolidationQueue .. ' consolidations' )

	local sts, other = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Keyword Consolidation", function()
		for i,func in ipairs( consolidationQueue ) do
			func()
		end
	end )
	consolidationQueue = {}
	if sts then
		nConsolidated = nConsolidated + #consolidationQueue
		logMessageLine( 'Consolidations committed successfully' )
	else
		showError( "Consolidation error: " .. RcLua.toString( other ) )
	end
end



--[[
        Synopsis:           Gets photo count corresponding to keyword item, including '(' & ')' for dialog box display. 
        
        Notes:              Beware: calling context expects ' (0)' to indicate no photos.
        
        Returns:            string
--]]        
function KwC._getPhotoCountForDisplay( item )
    local photos = item.kw:getPhotos()
    if photos then
        return ' (' .. tostring( #photos ) .. ')'
    else
        return ''
    end
end



--[[
        Synopsis:           Checks if pair of names are on the ignore list.
        
        Notes:              order is unimportant.
        
        Returns:            boolean
--]]        
function KwC._isOnIgnorePathsList( path1, path2 )
    if ignorePaths then
        for i,v in ipairs( ignorePaths ) do
            if ((ignorePaths[i][1] == path1) and (ignorePaths[i][2] == path2)) or ((ignorePaths[i][1] == path2) and (ignorePaths[i][2] == path1)) then
                return true
            end
        end
    end
    return false
end



--[[
        Synopsis:           Determines if two items should be included on conslidation form.
        
        Notes:              Included main paths or synonum paths not on ignore list, and improved by user if prompted.
                            Similarity has already been ascertained before calling.
        
        Returns:            t/f.
--]]        
function KwC._isToBeIncludedItems( item1, item2 )

    -- _debugTrace( "Testing for item similarity, item1: ", item1.mainPath .. ", item2: " .. kwMap[_id].mainPath ) 
    local path1 = item1.mainPath
    local path2 = item2.mainPath
    local syn1Ix = 1
    local syn2Ix = 1
    repeat
        -- _debugTrace( "Checking for path similarity, path1: ", path1 .. ", path2: " .. path2 ) 
        if KwC._isOnIgnorePathsList( path1, path2 ) then
            -- ignore
        elseif prefs.promptForIgnorePaths then
            if KwC._isToBeIgnoredPaths( path1, path2 ) then
                -- ignore
            else
                return true
            end
        else
            return true
        end
        if prefs.ignoreSynonyms then
            return false
        end        
        local name2 = item2.synonyms[syn2Ix]
        if name2 == nil then
            local name1 = item1.synonyms[syn1Ix]
            if name1 == nil then
                break
            else
                path1 = item1.parentPath .. '/' .. name1
                syn1Ix = syn1Ix + 1
            end
            path2 = item2.mainPath
            syn2Ix = 1
        else
            path2 = item2.parentPath .. '/' .. name2
            syn2Ix = syn2Ix + 1
        end
            
    until false
    return false
end



--[[
        Synopsis:           Determines if item should be included on consolidation form.
        
        Notes:              Decision based on similar items and ignore items.
        
        Returns:            t/f.
--]]        
function KwC._isToBeIncluded( item, similars, ignoreItems )

    local include = false
    for i,v in ipairs( similars ) do
        local item2 = kwMap[v]
        if KwC._isToBeIncludedItems( item, item2 ) then
            include = true
        else
            ignoreItems[item2.id] = true
        end
    end
    return include
    
end



--[[
        Synopsis:           Saves paths and synonym paths of both items in the ignore list.
        
        Notes:              Ignore list written only upon successful session termination.
        
        Returns:            nothing
--]]        
function KwC._ignoreItems( item1, item2 )

    -- _debugTrace( "Ignoring items, item1: ", item1.mainPath .. ", item2: " .. kwMap[_id].mainPath ) 
    local path1 = item1.mainPath
    local path2 = item2.mainPath
    local syn1Ix = 1
    local syn2Ix = 1
    repeat
        logMessageLine( "Ignoring paths forever: " .. path1 .. ", path2: " .. path2 ) 
        ignorePaths[#ignorePaths + 1] = { path1, path2 }
        if prefs.ignoreSynonyms then
            return
        end        
        local name2 = item2.synonyms[syn2Ix]
        if name2 == nil then
            local name1 = item1.synonyms[syn1Ix]
            if name1 == nil then
                break
            else
                path1 = item1.parentPath .. '/' .. name1
                syn1Ix = syn1Ix + 1
            end
            path2 = item2.mainPath
            syn2Ix = 1
        else
            path2 = item2.parentPath .. '/' .. name2
            syn2Ix = syn2Ix + 1
        end
            
    until false
end



--[[
        Synopsis:           Saves item and similar items in ignore list.
        
        Notes:              Ignored items not presented next pass.
        
        Returns:            
--]]        
function KwC._ignoreForever( item, similar )

    for i,v in ipairs( similar ) do
        KwC._ignoreItems( item, kwMap[v] )
    end

end



--[[
        Synopsis:           Prompts the user for what he/she wants to do when encountering similar keywords.
        
        Notes:              - although you can't delete a keyword, you can at least log which keywords are empty so the user can do it.
        
        Returns:            
--]]        
function KwC._doSomething( item, similar )

    -- _debugTrace( "do something with ", item.mainPath .. " (and similar keywords)" )
    -- logMessageLine( LOC("$$$/X=Doing something with '^1', similar to '^2'", name, similar ) )
    
    -- local name = item.name

    local ignoreItems = {}
    if KwC._isToBeIncluded( item, similar, ignoreItems ) then
        -- keep going
    else
        return
    end
    
    local answer
    local srcPaths
    local targPath
    RcUtils.wrap( "Consolidation Prompt", false, function( context )
        local props = LrBinding.makePropertyTable( context )
        local args = {}
        args.title = "Keyword Consolidatation"
        args.resizable = true
        args.save_frame = 'ConsolidationPrompt'
        
        repeat
        
            local contents = {}
            local nameItems = {} -- for keyword name combo box.
            
            contents[1] = vf:row {
                vf:static_text {
                    title = 'Replace these keywords:',
                    font = config.defaultFont,
                },
            }
            contents[#contents + 1] = vf:spacer { height=5 }
    
            -- sources
            props[item.id .. "_sourceChecked"] = false
            local photoCountString = KwC._getPhotoCountForDisplay( item )
            if RcString.is( photoCountString ) and photoCountString ~= ' (0)' then
                contents[#contents + 1] = vf:row {
                    vf:checkbox {
                        title = item.mainPath .. photoCountString,
                        font = config.defaultFont,
                        value = LrView.bind( item.id .. "_sourceChecked" ),
                        checked_value = item.id,
                    }
                }
                if #item.synonyms > 0 then
                    local syn = '    Synonyms: ' .. table.concat( item.synonyms, "," )
                    contents[#contents + 1] = vf:row {
                        vf:static_text {
                            title = syn,
                            font = config.defaultFont,
                        }
                    }
                end
            end
            for i,v in ipairs( similar ) do
                if not ignoreItems[v] then
                    local sim = kwMap[v]
                    props[sim.id .. "_sourceChecked"] = false
                    photoCountString = KwC._getPhotoCountForDisplay( sim )
                    if RcString.is( photoCountString ) and photoCountString ~= ' (0)' then
                        contents[#contents + 1] = vf:row {
                            vf:checkbox {
                                title = sim.mainPath .. photoCountString,
                                font = config.defaultFont,
                                value = LrView.bind( sim.id .. "_sourceChecked" ),
                                checked_value = sim.id,
                            },
                        }
                        if #sim.synonyms > 0 then
                            local syn = '    Synonyms: ' .. table.concat( sim.synonyms, "," )
                            contents[#contents + 1] = vf:row {
                                vf:static_text {
                                    title = syn,
                                    font = config.defaultFont,
                                }
                            }
                        end
                    end
                end
            end
    
            -- targets
            contents[#contents + 1] = vf:spacer { height=10 }
            contents[#contents + 1] = vf:row {
                vf:static_text {
                    title = 'With these keywords:',
                    font = config.defaultFont,
                },
            }
            contents[#contents + 1] = vf:spacer { height=5 }
    
            props[item.id .. "_targetChecked"] = false
            nameItems[#nameItems + 1] = item.name
            contents[#contents + 1] = vf:row {
                vf:checkbox {
                    title = item.mainPath .. KwC._getPhotoCountForDisplay( item ),
                    font = config.defaultFont,
                    value = LrView.bind( item.id .. "_targetChecked" ),
                    checked_value = item.id,
                }
            }
            if #item.synonyms > 0 then
                RcTable.append( nameItems, item.synonyms )
                local syn = '    Synonyms: ' .. table.concat( item.synonyms, "," )
                contents[#contents + 1] = vf:row {
                    vf:static_text {
                        title = syn,
                        font = config.defaultFont,
                    }
                }
            end
            for i,v in ipairs( similar ) do
                if not ignoreItems[v] then
                    local sim = kwMap[v]
                    nameItems[#nameItems + 1] = sim.name
                    props[sim.id .. "_targetChecked"] = false
                    contents[#contents + 1] = vf:row {
                        vf:checkbox {
                            title = sim.mainPath .. KwC._getPhotoCountForDisplay( sim ),
                            font = config.defaultFont,
                            value = LrView.bind( sim.id .. "_targetChecked" ),
                            checked_value = sim.id,
                        },
                    }
                    if #sim.synonyms > 0 then
                        RcTable.append( nameItems, sim.synonyms )
                        local syn = '    Synonyms: ' .. table.concat( sim.synonyms, "," )
                        contents[#contents + 1] = vf:row {
                            vf:static_text {
                                title = syn,
                                font = config.defaultFont,
                            }
                        }
                    end
                end
            end
            
            
            contents[#contents + 1] = vf:spacer { height=5 }
            contents[#contents + 1] = vf:row {
                vf:static_text {
                    title = "And/or with these keywords (pre-existing or create new)\n - first entry is root keyword, last entry is target keyword - separate with a blank entry to specify more than one.",
                    font = config.defaultFont,
                },
            }
            for i = 1,12 do
                props["newKeywordName" .. tostring( i )] = ''
                props["newKeywordExport" .. tostring( i )] = true
                props["newKeywordSynonyms" .. tostring( i )] = ''
                contents[#contents + 1] = vf:row {
                    vf:static_text {
                        title = "Keyword",
                        font = config.defaultFont,
                    },
                    vf:edit_field {
                        width_in_chars = 20,
                        font = config.defaultFont,
                        value = LrView.bind( 'newKeywordName'  .. tostring( i ) ),
                        _props = props,
                        _index = i,
                    },
                    vf:push_button {
                        title = "<",
                        font = config.defaultFont,
                        _items = nameItems,
                        _props = props,
                        _key = "newKeywordName" .. tostring( i ),
                        _index = i,
                        action = function( button )
                            if #(button._items) == 0 then
                                showInfo( "No items" )
                                return
                            end
                            if not RcString.is( button._props[button._key] ) then
                                button._props[button._key] = button._items[1]
                            end
                            local v = vf:combo_box{
                                bind_to_object = button._props,
                                font = config.defaultFont,
                                items = button._items,
                                value = LrView.bind( button._key ),
                            }
                            local a = {}
                            a.title = 'Select Keyword Name'
                            a.contents = v
                            a.cancelVerb = 'OK'
                            RcGui.presentModalFrame( a )
                        end
                    },
                    vf:static_text {
                        title = "Synonyms (comma separated)",
                        font = config.defaultFont,
                    },
                    vf:edit_field {
                        width_in_chars = 30,
                        font = config.defaultFont,
                        value = LrView.bind( 'newKeywordSynonyms' .. tostring( i ) ),
                        -- enabled = false,
                    },
                    vf:checkbox {
                        title = 'Export',
                        font = config.defaultFont,
                        value = LrView.bind( 'newKeywordExport' .. tostring( i ) ),
                    },
                }
            end
            
            contents.bind_to_object = props
            args.contents = vf:column( contents )
            args.accessoryView = vf:column {
                vf:row {
                    vf:push_button {
                        title = 'Log',
                        font = config.defaultFont,
                        action = function( button )
                            LrDialogs.stopModalWithResult( button, 'log' )
                        end,
                    },
                    vf:push_button {
                        title = 'Ignore Forever',
                        font = config.defaultFont,
                        action = function( button )
                            LrDialogs.stopModalWithResult( button, 'ignore_forever' )
                        end,
                    },
                    vf:push_button {
                        title = 'Consolidate And Move On',
                        font = config.defaultFont,
                        action = function( button )
                            LrDialogs.stopModalWithResult( button, 'consolidate_go' )
                        end,
                    },
                    vf:push_button {
                        title = 'Consolidate And Stay',
                        font = config.defaultFont,
                        action = function( button )
                            LrDialogs.stopModalWithResult( button, 'consolidate_stay' )
                        end,
                    },
                },
            }
            args.actionVerb = "Move On"
            args.cancelVerb = "Quit"
        
            answer = LrDialogs.presentModalDialog( args ) -- true => return all buttons.
            --[[args = {} - *** save for possibly more investigation into the combo-box bug/work-around.
            args.title = 'Test'
            props['itval'] = 'asdf'
            args.contents = vf:combo_box {
                    bind_to_object = props,
                    font = config.defaultFont,
                    title='cbttl',
                    items={ 'it1', 'it2' },
                    value = LrView.bind( 'itval' ),
                }
            RcGui.presentModalFlame( args )
            LrDialogs.message( props['itval'] )
            answer = '?'--]]
            done = true            
            if answer == 'consolidate_go' or answer == 'consolidate_stay' then
                ---- _debugTrace( "consolidate" )
                -- check keyword entry reasonability    
                for i = 1,12 do
                    if RcString.is( props["newKeywordName" .. tostring( i )] ) then
                        local name = '' .. props["newKeywordName" .. tostring( i )]
                        local isDelim = name:find( "[\/\\\>]" )
                        if isDelim then
                            showWarning( "Get the delimiters out of the keyword name (" .. name .. ") - one simple name per line - multiple lines constitute a single structured keyword entry..." )
                            done = false
                            break
                        end
                    else
                        break
                    end
                end
                if prefs.newKeywordPrompt then
                    done = KwC._createKeywordHierarchies( props, true ) -- true => just prompt for new keyword creation approval.
                end
                if done then
                    local notConsolidated = KwC._doConsolidate( item, similar, props )
                    if notConsolidated then
                        done = false -- errm already displayed.                    
                    elseif answer == 'consolidate_stay' then -- stay
                        showInfo( "Consolidated - go again...", "ConsolidatedAndStaying" )
                        -- RcUtils.showBriefly( "Done", .5 )
                        done = false
                    -- else consolidate ok and moving on...
                    end
                end
            elseif answer == 'log' then -- no
                KwC._doLog( item, similar )
            elseif answer == 'ok' then -- skip
                nConsolidationsSkipped = nConsolidationsSkipped + 1
                -- do nothing
            elseif answer == 'ignore_forever' then
                KwC._ignoreForever( item, similar )
                -- nConsolidationsSkipped = nConsolidationsSkipped + 1
                -- do nothing
            else -- answer == 'quit'
                -- _debugTrace( "quit" )
                quit = true
                quitMessage = "Done, for now..."
            end
        until done or quit
    
    end )
end



--[[
        Synopsis:           Adds a keyword to the map with the specified path.
        
        Notes:              
        
        Returns:            
--]]        
function KwC._addMapEntry( p, kw )

    local item = {}
    item.name = kw:getName()
    item.id = kw.localIdentifier
    item.synonyms = kw:getSynonyms()
    if RcString.is( p ) and p ~= '/' then
        item.mainPath = p .. '/' .. item.name -- may not be used(?)
        item.parentPath = p
    else
        item.mainPath = '/' .. item.name -- may not be used(?)
        item.parentPath = ''
    end
    item.kw = kw
    -- additional paths with synonyms may be computed on demand.
    -- _debugTrace( "Adding map entry: ", item.mainPath )
    _G.kwMap[item.id] = item

	local lowerName = LrStringUtils.lower( item.name )
	if nameToIds[ lowerName ] == nil then
		nameToIds[ lowerName ] = { item.id }
	else
		nameToIds[ lowerName ][ #nameToIds[ lowerName ] + 1 ] = item.id
	end

	for _,synonym in pairs( item.synonyms ) do
		local lowerSynonym = LrStringUtils.lower( synonym )
		if synonymToIds[ lowerSynonym ] == nil then
			synonymToIds[ lowerSynonym ] = { item.id }
		else
			synonymToIds[ lowerSynonym ][ #synonymToIds[ lowerSynonym ] + 1 ] = item.id
		end
	end

    -- ###1LrTasks.yield()

end



--[[
        Synopsis:           Add or assure existing map entries for the path which should track with the keywords.
        
        Notes:              
        
        Returns:            
--]]        
function KwC._assureMapEntries( path, keywords )

    local comps = RcString.breakdownPath( path )
    local path = ''
    local index = 1
    for i,v in ipairs( comps ) do
        if v ~= '/' then
            if keywords[index] then
                local id = keywords[index].localIdentifier
                if kwMap[id] then
                    -- keyword already mapped - no prob
                else
                    KwC._addMapEntry( path, keywords[index] )
                end
                path = path .. '/' .. v
                index = index + 1
            else
                error( "keyword components inconsistent with path: " .. path .. ", at index: " .. tostring( index ) ) -- propagates to "other" parameter returned
                -- by with-do gate, assuming it is called in protected mode, which it always should be.
            end
        end
    end

end



--[[
        Synopsis:           Builds keyword map.
        
        Notes:              none.
        
        Returns:            table.
--]]        
function KwC._buildMap( parent, keywords )

    local tbl = {}

    for i, k in ipairs( keywords ) do
    
        yc = RcUtils.yield( yc, 50 )
    
        local keywordName = k:getName()
        KwC._addMapEntry( parent, k )
        
        tbl[i] = {}
        tbl[i].name = keywordName
        tbl[i].tbl = {}
        
        local c = k:getChildren()
        if (c ~= nil) and (#c ~= 0) then
            tbl[i].tbl = KwC._buildMap( parent .. '/' .. keywordName, c )
        -- else
        --    tbl[i].tbl = nil
        end

    end
    return tbl
    
end



--[[
        Synopsis:           Consider consolidation of specified item against all mapped keywords.
        
        Notes:              Traverses whats left of the todo items and looks for similarities, if found
                            calls a function to do something about it.
        
        Returns:            nothing
--]]        
function KwC._consolidateKeyword( id )

    local item = kwMap[id]
    if item ~= nil then
        local similar = KwC._findSimilar( item ) -- find all similar keyword items and return as array of id.
        if similar ~= nil and #similar > 0 then
            local nTotal = #(item.kw:getPhotos())
            for i,v in ipairs( similar ) do
                nTotal = nTotal + #(kwMap[v].kw:getPhotos())
            end
            if nTotal > 0 then
                KwC._doSomething( item, similar )
            else
                -- _debugTrace( "No photos..." )
            end
        else
            -- logMessageLine( LOC("$$$/X=One-of-a-kind keyword: '^1'", name ) )
        end
    else
        -- _debugTrace( "No item to consolidate" )
    end

end




--[[
        Synopsis:           Updates one photo's develop metadata, and maybe develop setting.
        
        Notes:              Reads photo's dev settings, then consolidates metadata, and checks for hot-edits.
        
        Returns:            could return "enough" but at the moment doesn't return anything.
--]]        
function KwC._consolidateKeywords()

    KwC._initToDo()

	LrFunctionContext.callWithContext( 'KwC_consolidate', function (context)

        local progressScope = LrProgressScope{ 
            title = "Keyword Consolidator",
            caption = "Scanning for matches",
            functionContext = context,
        }
		local numberDone = 0
		local totalCount = 0
		
		progressScope:setCancelable( true )

		for id, sts in pairs( kwToDo ) do
			totalCount = totalCount + 1
		end

		for id, sts in pairs( kwToDo ) do
			numberDone = numberDone + 1
			progressScope:setPortionComplete(numberDone, totalCount)
			yc = RcUtils.yield( yc, 5 )
			if progressScope:isCanceled() then break end
			
			if sts then
				KwC._consolidateKeyword( id )
				if quit then break end
			end
		end
	end )
    
	KwC._commitConsolidations()

end



--[[
        Synopsis:           Updates one photo's develop metadata, and maybe develop setting.
        
        Notes:              Reads photo's dev settings, then consolidates metadata, and checks for hot-edits.
        
        Returns:            could return "enough" but at the moment doesn't return anything.
--]]        
function KwC._consolidateKeywordsSelectedPhotos()

    KwC._initToDo()

	LrFunctionContext.callWithContext( 'KwC_consolidate', function (context)

        local progressScope = LrProgressScope{ 
            title = "Keyword Consolidator",
            caption = "Scanning for matches",
            functionContext = context,
        }
		
		progressScope:setCancelable( true )

		targetPhotos = catalog:getTargetPhotos() -- module var. Note: test for selection already pre-detected.

		for _,photo in ipairs( targetPhotos ) do
			progressScope:setPortionComplete( _, #targetPhotos )
			yc = RcUtils.yield( yc, 5 )
			if progressScope:isCanceled() then return end

			keywords = photo:getRawMetadata( 'keywords' )
			if keywords ~= nil then -- not sure if nil ever happens but its cheap insurance.
				for __,keyword in ipairs( keywords ) do
					-- _debugTrace( "Photo Keyword: " , keyword:getName() ) 
					if kwToDo[keyword.localIdentifier] then
						KwC._consolidateKeyword( keyword.localIdentifier )
						if quit then return end
					end
				end
			end
		end
	end )
    
	KwC._commitConsolidations()

end



--[[
        Synopsis:           Updates develop settings metadata for selected photos.
        
        Notes:              Errors occuring in update-photo function are trapped and presented generally to the user, who can chooses to keep going or toss in the towel.
        
        Returns:            Nothing.
--]]        
function KwC._consolidate( context )

    quit = false
    quitMessage = ''
    
    if not _G.initializing and not _G.initialized then
        -- this would hopefully only be the case when auto-init is turned off.
        showInfo( "Lengthy initialization for consolidation needs to be done before first consolidation of the session - consider auto-init in plugin manager.", "AutoInitPrompt" )
        KwC._initData( false ) -- sets initializing flag, or maybe quit flag.
    elseif not _G.initializing and _G.initialized then -- Note: as long as map is maintained, one should never have to re-initialize it.
        -- what might need to be re-initialized is just the to-do list. ###3.
        local answer = showInfo( "Re-initialize for new session or continue previous session?", nil, "New Session", "Continue" )
        if answer == 'ok' then
            KwC._initData( false ) -- sets initializing flag, or maybe quit flag.
        end
    end

    if not quit then
        while( not _G.initialized ) do
            if RcUtils.isOk( "Initialization has not completed - check again?" ) then
                LrTasks.sleep( 1 )
            else
                quit = true
                quitMessage = "Quit before init."
                return
            end
        end
    else
        return
    end
    
    if RcTable.isEmpty( _G.kwMap ) then
        quit = true
        quitMessage = "No keywords init."
        return
    end

    local pcallStatus
    local enough
    
    -- initStats
    nConsolidated = 0
    nDuplicates = 0
    nLogged = 0
    nNameIgnoresSkipped = 0
    nPathIgnoresSkipped = 0
    nConsolidationsSkipped = 0
    nNamesIgnored = 0
    nPathsIgnored = 0
    
    KwC._loadIgnoreTable()
    if quit then return end -- support file error.
   
    catalog = LrApplication.activeCatalog()   
    
    -- showInfo( "Commencing second step - you determine what needs to be consolidated and what does not - the first pass may take you a long time since many similarities will be caught, but permissible similarities are remembered and subsequent passes will take less time." )
    
    selectedPhoto = catalog:getTargetPhoto()
    if selectedPhoto then
        KwC._consolidateKeywordsSelectedPhotos() -- just selected ones.
    else
        KwC._consolidateKeywords() -- all in catalog
    end
    
    KwC._saveIgnoreTable()
    
    -- log stat
    logMessageLine()
    logMessageLine( LOC( "$$$/X=Keywords consolidated: ^1", nConsolidated ) )
    logMessageLine( LOC( "$$$/X=Logged for further consideration: ^1", nLogged ) )
    logMessageLine( LOC( "$$$/X=Consolidations skipped: ^1", nConsolidationsSkipped ) )
    logMessageLine( LOC( "$$$/X=Similar keyword names ignored forever: ^1", nNamesIgnored ) )
    logMessageLine( LOC( "$$$/X=Similar keyword paths ignored forever: ^1", nPathsIgnored ) )
    logMessageLine( LOC( "$$$/X=Similar keyword names ignored for now: ^1", nNameIgnoresSkipped ) )
    logMessageLine( LOC( "$$$/X=Similar keyword paths ignored for now: ^1", nPathIgnoresSkipped ) )
    logMessageLine( LOC( "$$$/X=Duplicates discovered: ^1", nDuplicates ) )

end



-- returns nothing.
function KwC._autoConsolidateTrees( opName, context )
    if not initialized then
        RcUtils.showWarning( "Init not complete." )
        return
    end
    quit = false
    quitMessage = ''
    assert( kwMap, "no map" )
    local _tPhoto = catalog:getTargetPhoto()
    local photos
    if _tPhoto == nil then
        photos = catalog:getAllPhotos()
    else
        photos = catalog:getMultipleSelectedOrAllPhotos()
    end
    if #photos == 0 then
        RcUtils.showWarning( "Select photo(s) first." )
        return
    end
    local props = LrBinding.makePropertyTable( context )
    local vf = LrView.osFactory() -- redundent?
    local srcRoot, destRoot
    local args = {}
    args.title = "Enter source and target tree roots, then click 'Auto-consolidate' (or click 'Cancel' to abort...)\n \nSyntax: /root/parent/child..., for example - Source Root: '/Old Keywords'; Target Root: '/New Keywords' (without the apostrophes)"
    local viewItems = { bind_to_object = props }
    local function check( name, root )
        if root == nil or root == "" then
            return false, name .. " can not be blank."
        end
        --_debugTrace( "looking for", root )
        for k, v in pairs( kwMap) do
            local p1, p2 = v.mainPath:find( root, 1, true )
            if p1 then
                if p1 == 1 then
                    return true
                else
                    --_debugTrace( "found but not starting with", v.mainPath )
                end
            else
                --_debugTrace( "not a match", v.mainPath )
            end
        end
        return false, name .. " not found."
    end
    local function validate( vw, val )
        local root = LrStringUtils.trimWhitespace( val )
        if root:sub( 1, 1 ) ~= "/" then
            return false, "/" .. root, "Must start with '/'"
        end            
        if root:sub( -1 ) == "/" then
            if root == "/" then return true, root, nil end
            return false, root:sub( 1, #root - 1 ), "Must not end with '/'"
        end
        return true, root, nil
    end
    viewItems[#viewItems + 1] =
        vf:row {
            vf:static_text {
                title = "Source Root:",
            },
            vf:edit_field {
                value = LrView.bind( 'srcRoot' ),
                width_in_chars = 60,
                validate = validate,
            },
        }
    viewItems[#viewItems + 1] =
        vf:row {
            vf:static_text {
                title = "Target Root:",
            },
            vf:edit_field {
                value = LrView.bind( 'destRoot' ),
                width_in_chars = 60,
                validate = validate,
            },
        }
    args.contents = vf:view( viewItems )
    repeat
        local button = LrDialogs.presentModalDialog( args )
        if button == 'ok' then
            local src = props.srcRoot
            local dest = props.destRoot
            local s, m = check( "'Source Root'", src )
            if s then
                s, m = check( "'Target Root'", dest )
                if s then
                    srcRoot = src
                    destRoot = dest
                    break
                else
                    RcUtils.showWarning( m )
                end
            else
                RcUtils.showWarning( m )
            end         
        else
            quit = true
            quitMessage = "Canceled"
            return
        end
    until false
    --RcUtils.showInfo( LOC( "$$$/X=^1, ^2", srcRoot, destRoot ) )
    if not RcUtils.isOk( LOC( "$$$/X=Auto-consolidate keywords from '^1' to '^2' as found amongst ^3 photos?", srcRoot, destRoot, #photos ) ) then
        quit = true
        quitMessage = "Canceled"
        return
    end
    local function getPath( kw )
        local comp = { kw:getName() }
        local parent = kw:getParent()
        while parent do
            comp[#comp + 1] = parent:getName()
            parent = parent:getParent()
        end
        RcTable.reverseInPlace( comp )
        local path = "/"..table.concat( comp, "/" )
        --_debugTrace( "path gotten", path )
        return path
    end
    local function findInSrc( kw )
        local item = kwMap[kw.localIdentifier]
        if not item then
            return nil
        end
        local path = getPath( kw )
        local p1, p2 = path:find( srcRoot, 1, true )
        if p1 then
            if p1 == 1 then
                return item.id, path
            end
        end
        return false
    end
    local function findInDest( id )
        local kwName = kwMap[id].name
        for k, v in pairs( kwMap ) do
            if v.id ~= id then
                if RcString.isEqualIgnoringCase( v.name, kwName ) then
                    local p1, p2 = v.mainPath:find( destRoot, 1, true )
                    if p1 then
                        if p1 == 1 then
                            return kwMap[v.id].kw
                        end
                    end
                end
            end
        end
    end
    local photoSet = {}
    local consolidate = {}
    local cnt = 0
    local scope = LrProgressScope {
        title = "Auto-consolidate Trees",
        caption = "Gathering consolidation info...",
        functionContext = context,
    }
    LrTasks.yield()
    local yc = 0
    local srcWarned = {}
    local destWarned = {}
    for i, photo in ipairs( photos ) do
        scope:setPortionComplete( i-1, #photos )
        local keywords = photo:getRawMetadata( 'keywords' )
        for j, keyword in ipairs( keywords ) do
            repeat
                if consolidate[keyword] then
                   photoSet[photo] = true
                   break 
                end
                local id, srcPath = findInSrc( keyword )
                if id == nil then
                    if not srcWarned[id] then
                        RcUtils.logWarning( LOC( "$$$/X=Keyword not found in source tree - ignoring '^1' - try again after reloading plugin.", keyword:getName() ) )
                        srcWarned[id] = true
                    end
                    break
                end
                if not id then
                    break
                end
                --local subPath = LrPathUtils.makeRelative( srcPath, srcRoot )
                --assert( subPath ~= nil and subPath ~= "", "bad subpath" )
                local srcKeyword = kwMap[id].kw
                assert( keyword == srcKeyword, "src kw mism" )
                local destKeyword = findInDest( id )
                if destKeyword == nil then
                    if not destWarned[id] then
                        RcUtils.logWarning( LOC( "$$$/X=Keyword not found in target tree - ignoring '^1'.", keyword:getName() ) )
                        destWarned[id] = true
                    end
                    break
                end
                local destPath = getPath( destKeyword )
                photoSet[photo] = true
                consolidate[srcKeyword] = { srcPath=srcPath, destKw=destKeyword, destPath=destPath }
                cnt = cnt + 1
            until true
        end
        if scope:isCanceled() then
            quit = true
            quitMessage = "Scope canceled."
            return
        else
            yc = RcUtils.yield( yc )
        end
    end
    scope:setPortionComplete( 1 )
    if cnt > 0 then
        scope:setCaption( "Consolidating "..cnt.." keywords..." )
        -- _debugTrace( "rmv/add", getPath( rmv[1] ) .. "/ " .. getPath( add[1] ) )
        local cnt2 = 0
        local guts = function()
            local yc = 0
            for srcKw, c in pairs( consolidate ) do
                scope:setPortionComplete( cnt2, cnt )
                cnt2 = cnt2 + 1
                local ps = srcKw:getPhotos()
                for i, p in ipairs( ps ) do
                    if photoSet[p] then
                        RcUtils.logMessageLine( p:getRawMetadata( 'path' ) )
                        if RcUtils.testMode then
                            RcUtils.logMessageLine( LOC( "$$$/X=WOULD consolidate '^1' to '^2'", c.srcPath, c.destPath ) )
                        else
                            p:removeKeyword( srcKw )
                            p:addKeyword( c.destKw )
                            RcUtils.logMessageLine( LOC( "$$$/X=Consolidated '^1' to '^2'", c.srcPath, c.destPath ) )
                        end
                    -- else dont consolidate.
                    end
                    if not scope:isCanceled() then
                        yc = RcUtils.yield( yc )
                    else
                        quit = true
                        quitMessage = "Scope canceled."
                        return
                    end
                end
            end
            scope:setPortionComplete( 1 )
        end
        assert( RcUtils.testMode ~= nil, "tm not init" )
        local sts, msg
        if not RcUtils.testMode then
            sts, msg = RcUtils.withCatalogDo( 60, catalog.withWriteAccessDo, catalog, "Consolidate Keywords", guts )
        else
            guts()
            sts = true
        end
        if sts then
            RcUtils.logInfo( "done" )
        else
            error( msg )
        end
    else
        RcUtils.logMessageLine( "None to consolidate" )
    end
    
end



--[[
        Synopsis:           Removes parent keywords for selected or all filmstrip photos.
        
        Notes:              Errors occuring in update-photo function are trapped and presented generally to the user, who can chooses to keep going or toss in the towel.
        
        Returns:            Nothing.
--]]        
function KwC._removeParents( opName, context )

    quit = false
    quitMessage = ''

    local pcallStatus
    local enough
    
    -- initStats
    nParentsRemoved = 0
    nWereNotAssigned = 0
   
    catalog = LrApplication.activeCatalog()   
    
    targetPhotos = catalog:getTargetPhotos() -- selected or whole filmstrip. OK to do whole filmstrip since user pre-notified.
    
    if targetPhotos ~= nil and #targetPhotos > 0 then -- tends to return empty table not nil - I check for both.
        if RcUtils.isOkOrDontAsk( "Remove explicit parent keyword assignments leaving only child keywords selected, for " .. RcString.plural( #targetPhotos, "photo" ) .. "?", opName .. " - Prompt" ) then
            -- RcUtils.logInfo( "User approved ...
        else
            quit = true
            quitMessage = 'User canceled.'
            return
        end
    else
        RcUtils.showInfo( "No target photos." )
        return
    end

    
    local toDo = {}

    local hund = 100
    
    for i,photo in ipairs( targetPhotos ) do
    
        local photoPath = photo:getRawMetadata( 'path' )
    
        local keywords = photo:getRawMetadata( "keywords" )
        if keywords then
            for i2, keyword in ipairs( keywords ) do
                local keywordName = keyword:getName()
                -- logMessageLine( "Photo: " .. photoPath .. ", keyword: " .. keyword:getName() )
                local parent = keyword:getParent()
                while( parent ~= nil ) do

                    local photos = parent:getPhotos()
                    local nSaved = nParentsRemoved
                    for i3, photo2 in ipairs( photos ) do
                    
                        if photo == photo2 then -- photo under consideration is assigned to parent
                            if RcUtils.testMode == true then
                                -- _debugTrace( "WOULD Remove parent: ", parent:getName() )
                                logMessageLine( "WOULD Remove parent: " .. parent:getName() )
                            else
                                -- _debugTrace( "Removing parent: ", parent:getName() )
                                toDo[#toDo + 1] = { keywordName, parent, photo, function( _keywordName, _parent, _photo )
                                    logMessageLine( "Removing parent: " .. _parent:getName() .. ", from photo: " .. _photo:getRawMetadata( 'path' ) .. ", leaf keyword: " .. _keywordName )
                                    _photo:removeKeyword( _parent )
                                end }
                            end
                            nParentsRemoved = nParentsRemoved + 1
                            break -- no need to look further if target encountered.
                        else
                            -- ignore other photos assigned to parent.
                        end
                    
                    end
                    if nSaved == nParentsRemoved then
                        nWereNotAssigned = nWereNotAssigned + 1
                        logMessageLine( "Parent was not assigned: " .. parent:getName(), VERBOSE )
                    end
                    
                    parent = parent:getParent()
                    
                end
            end
        else
            -- _debugTrace( "Photo has no keywords: " .. photo:getRawMetadata( 'path' ) )
        end

        LrTasks.yield()
        hund = hund - 1
        if hund == 0 then break end
    
    end
    
    if #toDo > 0 then
        local sts, other = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Remove Parent Keywords", function()
            for i,v in ipairs( toDo ) do
            
                v[4](v[1],v[2],v[3])
            
            end
        end )
        if sts then
            -- ?
        else
            showError( "Error removing parent keywords: " .. RcLua.toString( other ) )
        end
    end
    
    -- log stat
    logMessageLine()
    logMessageLine( LOC( "$$$/X=Parents removed: ^1", nParentsRemoved ) )
    logMessageLine( LOC( "$$$/X=Parents not assigned: ^1", nWereNotAssigned ) )

end



--[[
        Synopsis:           Saves the id of each item in the map.
        
        Notes:              as items are done they are removed from the todo list.
        
        Returns:            nothing - initialized global list.
--]]        
function KwC._initToDo()
	consolidationQueue = {}		-- should always be empty here, but just in case
    _G.kwToDo = {}
    for k,v in pairs( kwMap ) do
        -- _debugTrace( "Initing To-Do: ", v.mainPath )
        _G.kwToDo[k] = true
    end
end



--[[
        Synopsis:           Updates develop settings metadata for selected photos.
        
        Notes:              Errors occuring in update-photo function are trapped and presented generally to the user, who can chooses to keep going or toss in the towel.
        
        Returns:            Nothing.
--]]        
function KwC._initData( asTask )

    _G.initializing = true -- external guard var.
    _G.initialized = false
    quit = false
    quitMessage = ''
    
    RcUtils.wrap( "Keyword Consolidator Initialization", asTask, function( context ) -- externally guarded.
    
        local progressScope = LrProgressScope{ 
            title = "Keyword Consolidator",
            caption = "Initializing...",
            functionContext = context,
        }
    
        local pcallStatus
        local enough
        
        catalog = LrApplication.activeCatalog()   
        local keywords = catalog:getKeywords()
        
        _G.kwMap = {}
        
        logMessageLine()
        logMessageLine( "Building keyword map:" )
        logMessageLine()
        yc = 0 -- yield counter
        _G.kwListMap = KwC._buildMap( '', keywords )
        -- assert( not RcTable.isEmpty( _G.kwListMap ) , "list map not init" ) - list-map will be empty upon creation of new catalog: dont throw error - there's a warning logged elsewhere that is sufficient.
        logMessageLine()
        
        if prefs == nil then
            prefs = LrPrefs.prefsForPlugin()
        end
        if prefs.ctrlTabAhk then
            KwC.initKeyHelpers()    
        end
        
        _G.initializing = false
        _G.initialized = true
    end )

end



--[[
        Synopsis:           Gets index of component (keyword name) at the specified heirarchical level.
        
        Notes:              Level must not be nil - check in calling context.
        
        Returns:            0 if not found, else array index.
--]]        
function KwC._getCompIndex( level, comp )
    for i = 1, #level do
        if level[i].name == comp then
            return i
        end    
    end
    return 0
end



--[[
        Synopsis:           Updates portion of keyword database used by Keyword List function, if necessary.
        
        Notes:              Update is of the "add" or verify existence variety, will not remove list-map entry.
        
        Returns:            nada
--]]        
function KwC._assureListMapEntries( path )

    if _G.kwListMap == nil then
        logWarning( "Keyword List Map uninitialized." )
        return
    end

    local comps = RcString.breakdownPath( path )
    
    local level = _G.kwListMap
    
    for i,comp in ipairs( comps ) do
        if comp ~= '/' then
            if level == nil then
                logWarning( "Keyword List Map entry uninitialized." )
                return
            end
            local index = KwC._getCompIndex( level, comp )
            if index > 0 then -- name exists at this level
                -- just ignore if already exists.
            else -- new entry at this level
                index = #level + 1
                local tbl = {}
                tbl.name = comp
                tbl.tbl = {}
                level[index] = tbl
            end
            level = level[index].tbl
        end
    end
    
end



--[[
        Synopsis:           Equivalent of lr-path-utils leaf-name function to handle reverse form.
        
        Notes:              
        
        Returns:            simple text.
--]]        
function KwC._reverseLeafName( path )

    local p1, p2
    p1, p2 = path:find( '>', 1, true )
    if p1 then
        return LrStringUtils.trimWhitespace( path:sub( 1, p1 - 1 ) )
    else
        return LrStringUtils.trimWhitespace( path )
    end

end



--[[
        Synopsis:           Equivalent of lr-path-utils parent function to handle reverse form.
        
        Notes:              
        
        Returns:            simple text or nil.
--]]        
function KwC._reverseParent( path )

    local p1, p2
    p1, p2 = path:find( '>', 1, true )
    if p1 then
        return LrStringUtils.trimWhitespace( path:sub( p2 + 1 ) )
    else
        return nil
    end

end



--[[
        Synopsis:           Compute forward or reverse path given specified end-point keyword.
        
        Notes:              
        
        Returns:            path as text.
--]]        
function KwC._getPath( keyword, reversed )

    local pathComp = {}
    pathComp[1] = keyword:getName()
    local parent = keyword:getParent()
    while( parent ~= nil ) do
        pathComp[#pathComp + 1] = parent:getName()
        parent = parent:getParent()
    end
    local s
    if reversed then
        s = pathComp[1]
        for i = 2, #pathComp do
            s = s .. ' > ' .. pathComp[i]
        end
    else
        s = ''
        for i = #pathComp, 1, -1 do
            s = s .. '/' .. pathComp[i]
        end
    end
    return s
            
end



--[[
        Synopsis:           Reloads values from target photo(s) into properties on form.
        
        Notes:              - Sometimes called when keyword only changes, in which case doing the title and caption are redundent.
                            - Someteims called when all fields are to change.
                            
                            - Sets global variables for looking up keywords, and detecting field changes, critical items:
                              - g-keyword-names:    simple text, or forward/reverse paths - its what goes into the keyword-text field, and remove keywords combo box.
                              - g-keyword-lookup:   format differs depending on path vs. no path. - only used for keyword removal.
                                - paths: a table for each photo containing the end-point keyword associated with each path.
                                - simple: the keyword multi-string for each photo - parsed later to find associated keywords if necessary.
                              - g-prev{field}:      saves loaded values to support subsequent change detection.
        
        Returns:            nothing.
--]]        
function KwC._reloadForm() -- ###1 props )

    -- I don't think the form re-entrancy vars are necessary anymore, but they're cheap insurance.
    if _G.loadingForm then return end
    _G.loadingForm = true

    if targetPhotos == nil or #targetPhotos == 0 then
        props.keywordList = ''
        _G.keywordNames = {}
        _G.keywordPaths = {}
        _G.keywordNamesWithoutStars = {}
        _G.keywordLookup = {}
        _G.loadingForm = false
        return
    end
    
    local photos
    if props.allPhotos then
        photos = targetPhotos
    else
        photos = { targetPhotos[props.photoIndex] }
    end
    
    if not props.viewPaths then
        if #photos == 1 then
            props.keywordList = ''
        else
            props.filePath = "Loading..."
        end
    else
        props.filePath = "Loading..."
    end
    
    local ttl = nil
    local cap = nil

    local newTextArray = {}
    local keywordSeen = {}
    -- _G.keywordNames = {} - set at bottom.
    _G.keywordPaths = {}
    _G.keywordNamesWithoutStars = {}
    _G.keywordLookup = {}
    local max = tonumber( prefs.maxKeywords )
    
    for i, photo in ipairs( photos ) do
    
        local photoTitle = photo:getFormattedMetadata( 'title' ) 
        local photoCaption = photo:getFormattedMetadata( 'caption' ) 
        
        if ttl == nil then
            ttl = photoTitle
        elseif ttl ~= photoTitle then
            ttl = '< mixed >'
        end
        if cap == nil then
            cap = photoCaption
        elseif cap ~= photoCaption then
            cap = '< mixed >'
        end
        
        local _keywordNames = {}
        local _keywordPaths = {}
        
        -- _debugTrace( "adding lookups for ", photo )

        --if props.viewPaths then
            local keywords = photo:getRawMetadata( "keywords" )
            
            if #keywords > max then
                local diff = #keywords - max
                local msg = LOC( "$$$/X=^1 has ^2 too many keywords, limit is ^3.", photo:getRawMetadata( "path" ), diff, max )
                logWarning( msg )
                showInfo( msg .. " A warning has been logged.", "KeywordLimitExceededPrompt" ) 
            end
            
            local lookup = {}
            for j,v in ipairs( keywords ) do
                local keywordPath
                local keywordName
                if kwMap[v.localIdentifier] then
                    keywordPath = kwMap[v.localIdentifier].mainPath
                    keywordName = kwMap[v.localIdentifier].name
                else
                    logMessageLine( "Keyword not in map: " .. RcLua.toString( v:getName() ) .. ", if initialization was complete when this happened, then its an error - otherwise ignore..." )
                    keywordPath = KwC._getPath( v, props.reversePaths ) -- ###2 - reminder: reverse no longer supported.
                    keywordName = v:getName()
                end
                _keywordPaths[j] = keywordPath
                _keywordNames[j] = keywordName -- won't be reversed.
                lookup[keywordPath] = v
            end
            _G.keywordLookup[photo] = lookup
        --[[else
            local keywordString = photo:getFormattedMetadata( "keywordTags" )
            keywordNamesOrPaths = RcString.split( keywordString, ',' )
            keywordLookup[photo] = keywordNamesOrPaths -- only needed for deleting.
            
        end--]]
        
        if _keywordPaths ~= nil and #_keywordPaths > 0 then
        
            for j, path in ipairs( _keywordPaths ) do

                if keywordSeen[path] then
                    keywordSeen[path] = keywordSeen[path] + 1
                else
                    _G.keywordPaths[#_G.keywordPaths + 1] = path
                    keywordSeen[path] = 1
                    if props.viewPaths then
                        _G.keywordNamesWithoutStars[#_G.keywordNamesWithoutStars + 1] = path
                    else
                        _G.keywordNamesWithoutStars[#_G.keywordNamesWithoutStars + 1] = _keywordNames[j]
                    end
                end
                
            end
        
        end
    
    end
    
    if props.viewPaths then
        local leafFunc
        local parentFunc
        if not props.reversePaths then
            leafFunc = LrPathUtils.leafName
            parentFunc = LrPathUtils.parent
        else
            leafFunc = KwC._reverseLeafName
            parentFunc = KwC._reverseParent
        end
        if props.sortEndpoints then
            table.sort( _G.keywordNamesWithoutStars, function( path1, path2 )
                local p1 = path1
                local p2 = path2
                repeat
                    one = leafFunc( p1 )
                    two = leafFunc( p2 )
                    if one ~= nil and two ~= nil then
                        -- could probably have used a simple string comparator to accomplish the same thing.
                        if one < two then
                            return true
                        elseif one > two then
                            return false
                        else
                        --[[if one ~= two then -- remove this code if no problems after a while.
                            local pair = { one, two }
                            table.sort( pair )
                            if pair[1] == one then
                                return true
                            else
                                return false                            
                            end
                        else--]]
                            p1 = parentFunc( p1 )
                            if p1 == nil then
                                return false
                            end
                            p2 = parentFunc( p2 )
                            if p2 == nil then
                                return false
                            end
                        end
                    else
                        return false
                    end
                until false
            end )
        else
            table.sort( _G.keywordNamesWithoutStars )
        end
    else
        table.sort( _G.keywordNamesWithoutStars )
    end
    
    --[[for i,v in ipairs( _G.keywordNames ) do
    	_debugTrace( "kwn: ", v )
    end--]]
 
    -- _debugTrace( "new: ", newText )
    
    if #photos == 1 then
        _G.keywordNames = _G.keywordNamesWithoutStars
        local photo = photos[1]
        local filePath = photo:getRawMetadata( 'path' )
        if photo:getRawMetadata( "isVirtualCopy" ) then
            local copyName = photo:getFormattedMetadata( 'copyName' )
            filePath = filePath .. '(' .. copyName .. ')'
        end
        props.filePath = filePath
    else
        _G.keywordNames = {}
        props.filePath = 'All Selected Photos'
        for i,v in ipairs( _G.keywordNamesWithoutStars ) do
        	-- _debugTrace( "kwn: ", v )
        	if keywordSeen[v] ~= #photos then
        	    _G.keywordNames[i] = _G.keywordNamesWithoutStars[i] .. "*"
        	else
        	    _G.keywordNames[i] = _G.keywordNamesWithoutStars[i]
        	end
        end
    end
    
    local newText = table.concat( _G.keywordNames, "\r\n" ) -- works on both platforms.
    
    props.title = ttl or ''
    props.caption = cap or ''

    _G.prev_title = props.title
    _G.prev_caption = props.caption
    _G.prevKeywordList = newText
    
    props.keywordList = newText

    _G.loadingForm = false -- I don't think the form reentrancy protection is necessary anymore,
                           -- but its being maintained as cheap insurance.
    
end



--[[
        Synopsis:           Applies changed field values to target photos.
        
        Notes:              Supports commit function tied to property observer.
        
        Returns:            nothing
--]]        
function KwC._applyFieldEdits( props, fieldName, fieldValue, wrapped )

    local key = "prev_" .. fieldName
    local chg = (_G[key] ~= fieldValue)
    
    local before
    local after
    if chg then
        -- keep going
        if props.allPhotos then
            local p1, p2 = fieldValue:find( '< mixed >', 1, true )
            if p1 then
                if p1 >= 1 then
                    before = fieldValue:sub( 1, p1 - 1 )
                else
                    before = ""
                end
                if p2 < #fieldValue then
                    after = fieldValue:sub( p2 + 1 ) or ""
                else
                    after = ""
                end
            end
        end
    else
        return
    end

    local photo

    --[[
            Note:       debug traces in here keep field from switching.
                        presumably so would other dialog presentations.
    --]]
    local updFunc = function()

        if props.allPhotos then
        
            local newFieldValue    
                        
            --LrDialogs.message( _G[key], fieldName .. " | " .. fieldValue .. "   " .. before .. " - " .. after )            
            
            for i,photo in ipairs( targetPhotos ) do
                if before ~= nil then
                    assert( after ~= nil, "no after" )
                    local status, prevValue = LrTasks.pcall( photo.getFormattedMetadata, photo, fieldName )
                    if not status then
                        prevValue = LrTasks.pcall( photo.getRawMetadata, photo, fieldName )
                        if not status then
                            error( "Unable to get previous metadata value, field: " .. ( fieldName or "nil" )  )
                        end
                    end
                    newFieldValue = before .. prevValue .. after
                else
                    newFieldValue = fieldValue
                end                
                photo:setRawMetadata( fieldName, newFieldValue )
            end
        else
            photo = targetPhotos[props.photoIndex]
            photo:setRawMetadata( fieldName, fieldValue )
        end
    end
    
    local sts, other
    if wrapped then
        -- _debugTrace( "wrapped" )
        sts, other = LrTasks.pcall( updFunc )
    else
        -- _debugTrace( "unwrapped" )
        sts, other = RcUtils.withCatalogDo( 10, catalog.withWriteAccessDo, catalog, "Update Metadata", updFunc )
    end
    
    if sts then
        _G[key] = fieldValue
        local m
        if props.allPhotos then
            m = "all selected photos."      
        else
            m = photo:getRawMetadata( "path" )
        end
        logMessageLine( fieldName .. " changed to " .. fieldValue .. " - " .. m, VERBOSE )
    else
        _G[key] = fieldValue -- presumably may keep from repeating the same error ad-infinitum.
        showError( "Metadata update not applied. If this error keeps happening, try restarting Lightroom - and please report bug to me - thanks." )
    end

end



--[[
        Synopsis:           Checks present title or caprion field against last value loaded in form.
        
        Notes:              Supports commit function called as property observer.
        
        Returns:            t/f.
--]]        
function KwC._checkForFieldEdits( props, field, value )
    local key = "prev_" .. field
    if _G[key] == nil or value == '< mixed >' then
        return false
    end
    if _G[key] ~= value then
        -- _debugTrace( "title change detected, to: ", props.title )
        return true
    else
        -- _debugTrace( "title not changed, is", props.title )
        return false
    end
end



--[[
        Synopsis:           Checks present keyword text against last value loaded in form.
        
        Notes:              Supports commit function called as property observer.
        
        Returns:            t/f.
--]]        
function KwC._checkForKeywordEdits( props, key, value )
    if _G.prevKeywordList == nil then
        return false
    end
    -- assert( value == props.keywordList, "val mix" )
    if _G.prevKeywordList ~= props.keywordList then
        -- _debugTrace( "was ", _G.prevKeywordList )
        -- _debugTrace( "is ", props.keywordList )
        return true
    end
    return false
end



--[[
        Synopsis:           Checks for any kind of edit changes.
        
        Notes:              Presently only used for debugging.
        
        Returns:            nil or name of changed data.
--]]        
function KwC._checkForEdits( props )
    local edit = KwC._checkForFieldEdits( props, 'title', props.title )
    if edit then
        return "Title"
    end
    edit = KwC._checkForFieldEdits( props, 'caption', props.caption )
    if edit then
        return "Caption"
    end
    edit = KwC._checkForKeywordEdits( props, 'keywordList', props.keywordList )
    if edit then
        return "Keyword"
    end
    return nil
end



--[[
        Synopsis:           Assign a single (endpoint) keyword to all or most selected photo.
        
        Notes:              Must be done via task inside with-do gate, and only AFTER returning from with-do func that may have created the keyword.
        
        Returns:            nada.
--]]        
function KwC._assignKeywordToPhotos( keyword )    
    assert( _G.props ~= nil, "no props" )
    assert( targetPhotos ~= nil, "no photos" )
    if _G.props.allPhotos then
        for i,photo in ipairs( targetPhotos ) do
            -- _debugTrace( "adding keyword to photo ", photo.path )
            photo:addKeyword( keyword )
        end
    else
        local photo = targetPhotos[_G.props.photoIndex]
        photo:addKeyword( keyword )
        -- logMessageLine( "Assigned " .. keyword:getName() .. " to " .. photo.path, VERBOSE )
    end
end



--[[
        Synopsis:           Adds specified keyword to target photos.
        
        Notes:              - Called wrapped in response to keyword list changes.
                            - Called unwrapped in response to '+' to add a single.
        
        Returns:         sts[,msg]    
--]]        
function KwC._addKeyword( props, keywordSpec, wrapped )

    -- _debugTrace( "adding" )
    
    if keywordSpec == nil then
        return false, "no keyword to add"
    end
    
    local keywordText
    local keywordAttrs
    local syn
    local incl
    if type( keywordSpec ) == 'table' then
        keywordText = keywordSpec.keywordName
        keywordAttrs = keywordSpec.attrs
        if not RcTable.isEmpty( keywordAttrs ) then
            syn = keywordAttrs.synonyms
            incl = keywordAttrs.includeOnExport
        end
    else -- had better be string.
        keywordText = LrStringUtils.trimWhitespace( keywordSpec )
        incl = true
    end
    
    if not RcString.is( keywordText ) then
        return false
    elseif keywordText == '/' then
        return false
    elseif keywordText == '\\' then
        return false
    end
    
    local keyword = nil
    local attrsToDo = {}
    local path = ''
    local keywords = {}

    -- throws error if problems    
    local createKeywordFunc = function()

        local comps
        if keywordText:find( "[/\\]" ) then
            comps = RcString.breakdownPath( keywordText )
        elseif keywordText:find( ">" ) then
            -- comps = KwC._breakdownReversePath( keywordText ) -- algorithm below not working for reverse case ###3
            -- error( "'>' is an invalid character: try /root/child or child > root notation." )
            error( "'>' is an invalid character: use /root/child until child > root notation supported." ) -- error propagates to calling context.
        elseif keywordText:find( "<" ) then
            -- error( "'<' is an invalid character: try /root/child or child > root notation." )
            error( "'<' is an invalid character: try /root/child until child > root notation supported." ) -- error propagates to calling context.
        else
            comps = { keywordText }
        end
        local parent = nil
        local err = false
        for i, v in ipairs( comps ) do
            repeat
                if v == '/' then -- ignore of root spec comp.
                    break
                end
                path = path .. '/' .. v
                if RcUtils.testMode then -- dialog boxes and logging seem problematic when called from event handlers or maybe catalog functions(?)
                    -- _debugTrace( "would found or created: ", v )
                    -- logMessageLine( "WOULD create " .. v .. " (if not already existing)" )
                else
                    -- keyword = catalog:createKeyword( v, syn, incl, parent )
                    keyword = catalog:createKeyword( v, nil, true, parent, true )
                    if keyword then
                        -- logMessageLine( "Created " .. v .. " (if not already existing)" )
                        -- ###3 Now that I'm using initialized map, I could just check before creating, like during consolidation.
                        -- On the other hand, its even easier just to pretend they don't exist, and recreate.
                        -- reminder: newly created keywords are not available for use until after returning from with-do function.
                        -- Note: 
                        keywords[#keywords + 1] = keyword -- save for latter mapping - after closing with-gate.
                        -- note: only the final endpoint keyword should be assigned to a photo.
                        if i == #comps then -- end-point keyword
                            if not RcTable.isEmpty( keywordAttrs ) then
                                -- assert( keyword.setAttributes, "strange keyword" )
                                -- keyword:setAttributes( { includeOnExport = true } ) -- keywordAttrs ) - keyword is on probation at this point - even if already existing.
                                local atbl = {}
                                atbl.kw = keyword
                                atbl.attrs = keywordAttrs
                                attrsToDo[#attrsToDo + 1] = atbl
                            end
                        end
                        parent = keyword
                    else
                        error( "Unable to created keyword: " .. RcLua.toString( v ) ) -- propagated out.
                    end
                end
            until true
        end
    end
    
    local assignKeywordFunc = function()    -- use module fn? ###3
        -- showInfo( "Added keyword: " .. keywordText .. ", error message: " .. RcLua.toString( other ) )
        if props.allPhotos then
            for i,photo in ipairs( targetPhotos ) do
                -- _debugTrace( "adding keyword to photo ", photo.path )
                photo:addKeyword( keyword )
            end
        else
            local photo = targetPhotos[props.photoIndex]
            photo:addKeyword( keyword )
            -- logMessageLine( "Assigned " .. keyword:getName() .. " to " .. photo.path, VERBOSE )
        end
    end

    local sts, other
    if wrapped then -- there's a bug here: you can't assign a recently created keyword or do anything else with it
        sts, other = LrTasks.pcall( createKeywordFunc )
        if sts and keyword then -- ###2 might be better off, to just split the add-keyword function into two: create-keywords, and assign-keywords,
            -- then calling context can choose how to call. Presently, all map business and keyword assignment must be handled in calling context when wrapped.
        end
    else
        -- _debugTrace( "add" )
        sts, other = RcUtils.withCatalogDo( 1, catalog.withWriteAccessDo, catalog, "Create Keyword " .. keywordText, createKeywordFunc )
        if sts and keyword then
            KwC._assureMapEntries( path, keywords ) -- would like to have this code a little smoother and better integrated...
            KwC._assureListMapEntries( path )
            sts, other = RcUtils.withCatalogDo( 1, catalog.withWriteAccessDo, catalog, "Assigning Keyword " .. keywordText, assignKeywordFunc )
        end
        if sts and keyword and #attrsToDo > 0 then
            -- _debugTrace( "nm", attrsToDo[1].kw:getName() )
            local func = function()
                for i,v in ipairs( attrsToDo ) do
                    v.kw:setAttributes( v.attrs )
                end
            end
            sts, other = RcUtils.withCatalogDo( 1, catalog.withWriteAccessDo, catalog, "Setting Keyword Attributes" .. keywordText, func )
        end
    end
    
    if sts and keyword then
        -- KwC._reloadForm( props ) - do in calling
    else
        showError( "Unable to add keyword: " .. keywordText .. ", error message: " .. RcLua.toString( other ) )
    end
    return sts, other, path, keywords
            
end



--[[
        Synopsis:           Close edits for present photo, before proceeding to next photo or changing view mode.
        
        Notes:              
        
        Returns:            sts[,msg]
--]]        
function KwC._closeEdits( props )

    local applyTitle = nil
    local applyCaption = nil
    local applyKeywordText = nil
    
    local edit = KwC._checkForFieldEdits( props, 'title', props.title )
    if edit then
        applyTitle = props.title
    end
    edit = KwC._checkForFieldEdits( props, 'caption', props.caption )
    if edit then
        applyCaption = props.caption
    end
    edit = KwC._checkForKeywordEdits( props, 'keywordList', props.keywordList )
    if edit then
        applyKeywordText = props.keywordList
    end

    if applyTitle or applyCaption or applyKeywordText then
        -- keep going
    else
        return false -- no msg
    end
    
    local newKeywords = {}
    local delKeywords = {}
    
    if applyKeywordText then
        local newLines
        -- eol is platform dependent in multi-line text file properties.
        if props.keywordList:find( "\r\n" ) then -- Lr3 on Windows
            newLines = RcString.split( props.keywordList, "\r\n" )
        else -- Lr4 on Windows, or its a Mac.
            newLines = RcString.split( props.keywordList, "\n" )
        end
        -- look for new keywords
        -- showInfo( "Keyword list does not support changes via text edit, yet." )
        for i,line in ipairs( newLines ) do
        
            if line ~= '' then
                local match = false
                for k, name in ipairs( keywordNames ) do -- having stars.
                    if name == line then
                        match = true
                        break
                    else
                    end
                end
            
                if not match then
                    local keywordText
                    if RcString.lastChar( line ) == '*' then
                        keywordText = line:sub( 1, #line - 1 )
                    else
                        keywordText = line
                    end
                    newKeywords[#newKeywords + 1] = keywordText
                end
            end
        
        end
        -- look for missing keywords
        for i, name in ipairs( keywordNames ) do

            local match = false
    
            for k,line in ipairs( newLines ) do

                if line ~= '' then                    
                    if name == line then
                        match = true
                        break
                    else
                    end
                end
            end
            
            if not match then
                local keywordText
                if RcString.lastChar( name ) == '*' then
                    keywordText = name:sub( 1, #name - 1 )
                else
                    keywordText = name
                end
                delKeywords[#delKeywords + 1] = keywordText
            end
        
        end
    end
                
    -- _debugTrace( "new: ", #newKeywords )
    -- _debugTrace( "del: ", #delKeywords )
    -- must be done from task - start before calling.
    -- _debugTrace( "Entering" )
    local keywords = {}
    local sts, other, path -- until 23/Feb/2013 8:03
    local sts, other, path, kws -- as of 23/Feb/2013 8:03 ###1 not yet released @23/Feb/2013 8:04 (bug? - only if strict, otherwise kws is oopsidental global).
    sts, other = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Apply Keyword Edits", function()
        -- _debugTrace( "Entering2" ) -- 
        if applyTitle then
            -- _debugTrace( "Applying changed title: ", applyTitle )
            KwC._applyFieldEdits( props, "title", applyTitle, true ) -- shows-error but returns nothing
            -- _debugTrace( "Applied changed title: ", props.title )
        end
        if applyCaption then
            KwC._applyFieldEdits( props, "caption", applyCaption, true ) -- shows-error but returns nothing
        end
        for i,v in ipairs( newKeywords ) do
            sts, other, path, kws = KwC._addKeyword( props, v, true ) -- true => already wrapped.
            if sts then
                keywords[#keywords + 1] = {}
                keywords[#keywords].path = path
                keywords[#keywords].keywords = kws
            end
        end
        for i,v in ipairs( delKeywords ) do
            local _sts, _msg = KwC._removeKeyword( props, v, true ) -- true -> already wrapped.
            if _sts then
                -- good
            else
                showError( "Unable to remove keyword: " .. RcLua.toString( v ) .. ", error message: " .. RcLua.toString( _msg ) )
            end
        end
        -- _debugTrace( "Exiting" )
    end )
    if sts then
        if #keywords > 0 then
            sts, other = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Assign New Keywords", function()
                for i,v in ipairs( keywords ) do
                    local path, kws = v.path, v.keywords
                    KwC._assureMapEntries( path, kws ) -- would like to have this code a little smoother and better integrated...
                    KwC._assureListMapEntries( path )
                    sts, other = LrTasks.pcall( KwC._assignKeywordToPhotos, kws[#kws] )
                end
            end )
        end
        return sts, other
    else
        logError( "Unable to apply edits, error message: " .. RcLua.toString( other ) )
        showError( "Unable to apply edits, error message: " .. RcLua.toString( other ) .. ". If this error keeps happening, try restarting Lightroom - and please report bug to me - thanks." )
        return false, "Unable to apply edits, error message: " .. RcLua.toString( other ) .. ". If this error keeps happening, try restarting Lightroom - and please report bug to me - thanks."
    end

end



--[[
        Synopsis:           Breaks down a path in reverse notation into its constituent components.
        
        Notes:              Not presently called - save for future.
        
        Returns:            array
--]]        
function KwC._breakdownReversePath( path )
    local comps = {}
    local pos = 1
    local p1, p2 = path:find( '>', pos, true )
    repeat
        if p1 then
            comps[#comps + 1] = LrStringUtils.trimWhitespace( path:sub( pos, p1 - 1 ) )
            pos = p2 + 1
            p1, p2 = path:find( '>', pos, true )
        else
            comps[#comps + 1] = LrStringUtils.trimWhitespace( path:sub( pos ) )
            break
        end
    until false
    -- RcUtils.logTable( comps )
    return comps
end



--[[
        Synopsis:           Determines if endpoint keyword matches specified component names all the way to root.
        
        Notes:              In other words its comparing for keyword equivalence between two forms.
                            *** Not presently called.
        
        Returns:            t/f.
--]]        
function KwC._followChain( keyword, comps, index )
    local parent = keyword:getParent()
    -- _debugTrace( "chain check, parent: ", parent )
    while( parent ~= nil and index <= #comps ) do
        -- _debugTrace( "chain check, comp: ", comps[index] .. ", parent name: " .. parent:getName() )
        if comps[index] == parent:getName() then
            -- good
            -- _debugTrace( "chain check comp match" )
            index = index + 1
            parent = parent:getParent()
        else
            -- _debugTrace( "chain check comp mismatch: ", comps[index] )
            return nil
        end
    end
    if index > #comps then -- we checked all components and never got a mismatch.
        return true
    else -- exited due to nil parent, without having checked all components.
        return false
    end
end



--[[
        Synopsis:           Find keyword that is not in the lookup table.
        
        Notes:              At the moment, only those in reverse-path notation fit that description.
        
        Returns:            lr-keyword proper, or nil.
--]]        
function KwC._findKeywordForPhoto( photo, keywordText )

    local comps = KwC._breakdownReversePath( keywordText )
    -- _debugTrace( "got comps, 1: ", comps[1] )
    local index = 1
    local keywords = photo:getRawMetadata( "keywords" )
    -- _debugTrace( "got keywords" )
    local keyword = nil
    for i,v in ipairs( keywords ) do
        if v:getName() == comps[1] then
            if #comps == 1 then
                -- _debugTrace( "found simple keyword" )
                return v
            end
            local chainMatch = KwC._followChain( v, comps, 2 )
            if chainMatch then
                -- _debugTrace( "chain match" )
                return v
                -- break
            else
                -- _debugTrace( "chain mismatch" )
            end
        else
            -- _debugTrace( "comp mismatch" )
        end
    end
    
    return nil -- keyword

end



--[[
        Synopsis:           Looks up a lr-keyword based on keyword-text (name or path).
        
        Notes:              This probably should be done using a lookup.
                            Note: this is not a critical function: its only used to help
                            provide an initial combo box selection for ++ & '-'.
                            And, its a good thing, since its not robust.
        
        Returns:            
--]]        
--[[ function KwC._getKeywordFromText( photos, _keywordText ) - *** save for possible future resurrection.

    if not RcString.is( _keywordText ) then
        return nil
    end
    
    local keyword = nil
    
    local keywordText
    if not _G.props.viewPaths then
        keywordText = LrPathUtils.leafName( _keywordText )
    else
        keywordText = _keywordText
    end
    _debugTrace( "kw-text: " , keywordText )
    for i,v in ipairs( photos ) do
    
        local lookup = _G.keywordLookup[ v ]
        if lookup then
            local kw = lookup[keywordText]
            if kw then
                if keyword == nil then
                    if _G.props.viewPaths then
                        return keywordText -- can not be ambiguous
                    else
                        keyword = keywordText
                    end
                else
                    return nil -- ambiguous
                end
            else
                _debugTrace( "not: ", keywordText )
            end
        else
            _debugTrace( "no lookup: ", v )
        end
    
    end
    return keyword
end--]]



--[[
        Synopsis:           Remove specified keyword from specified photo.
        
        Notes:              props are not presently used.
                            keyword is text and may be simple end-point or forward/reverse path notation.
        
        Returns:            sts[,msg]
--]]        
function KwC._removeKeywordFromPhoto( props, photo, keyword )

    local sts, msg
    
    local photoPath = photo:getRawMetadata( 'path' )
    
    local lookup = _G.keywordLookup[photo]
    if lookup == nil then
        return false, "Keyword lookup table not found for photo (" .. RcLua.toString( photoPath ) .. ") - please report."
    end
    
    local lrKeyword
    lrKeyword = lookup[keyword]
    if lrKeyword == nil then
        -- lrKeyword = KwC._findKeywordForPhoto( photo, keyword )
        if lrKeyword == nil then
            return false, "keyword not found: " .. RcLua.toString( keyword )
        else
            -- _debugTrace( "keyword found: ", lrKeyword:getName() )
        end
    else
        -- lookup successful.
    end
        
    photo:removeKeyword( lrKeyword )
    -- _debugTrace( "keyword removed from: ", photo.path )
    return true
    
end



--[[
        Synopsis:           Get keyword for removal using dialog box.
        
        Notes:              keyword as simple end-point, path, or reversed path: text.
        
        Returns:            
--]]        
function KwC._getKeywordToRemoveFromUser( props )
    local keywordText = ''
    RcUtils.wrap( "Remove Keyword", false, function( context )
        local _props = LrBinding.makePropertyTable( context )
        if #keywordNamesWithoutStars == 0 then
            showInfo( "No keywords to remove" )
            return
        else
            _props.keyword = _G.keywordPaths[1]
            for i,v in ipairs( _G.keywordPaths ) do
                if v == props.editKeyword then
                    _props.keyword = v
                    break
                end
            end
            --[[local photos
            if props.allPhotos then
                photos = targetPhotos
            else
                photos = { targetPhotos[props.photoIndex] }
            end
            local keyword = KwC._getKeywordFromText( photos, _G.props.editKeyword )
            if keyword then
                _props.keyword = keyword
            end--]]
        end            
        local args = {}
        local contents = {}
        local title
        if props.allPhotos and #targetPhotos > 1 then
            title = 'Remove keyword from all selected photos'
        else
            title = 'Remove keyword from ' .. LrPathUtils.leafName( targetPhotos[props.photoIndex].path )
        end
        contents[#contents + 1] = vf:static_text {
           title = title,
           font = config.defaultFont,
        }
        contents[#contents + 1] = vf:combo_box {
            items = _G.keywordPaths,
            font = config.defaultFont,
            value = LrView.bind( "keyword" ),
        }
        contents.bind_to_object = _props
        args.title = "Remove Keyword"
        args.contents = vf:column( contents )
        args.save_frame = "RemoveKeywordBox"
        local button = LrDialogs.presentModalDialog( args )
        if button == 'ok' then
            keywordText = _props.keyword
        end
    end )
    return keywordText
end



--[[
        Synopsis:           Gets synonym and incl-on-export attributes corresponding to the corresponding path. 
        
        Notes:              ###1 this function has the side effect of actually creating the keyword its getting the attributes of,
                            if it does not already exist. There is room for improvement - storing a lookup table that translates
                            from path to keyword for existing keywords would do it. This sort of exists on a per photo basis
                            to support other functionality, but it may be worthwhile to store keyword corresponding to each path
                            in the global mapping tables.
        
        Returns:            attrs = { synonyms = syn, includeOnExport = incl }, or nil.
--]]        
function KwC._getAttributes( keywordText )

    local comps
    if keywordText:find( "[/\\]" ) then
        comps = RcString.breakdownPath( keywordText )
    elseif keywordText:find( ">" ) then
        -- comps = KwC._breakdownReversePath( keywordText )
        error( "'>' is an invalid character: try /root/child until child > root notation supported." )
    elseif keywordText:find( "<" ) then
        -- error( "'<' is an invalid character: try /root/child or child > root notation." )
        error( "'<' is an invalid character: try /root/child until child > root notation supported." )
    else
        comps = { keywordText }
    end
    local parent = nil
    local err = false
    -- local extra = nil
    local keyword
    local func1 = function()
        for i, v in ipairs( comps ) do -- ###3 needs to handle reverse case
            repeat
                if v == '/' then -- ignore of root spec comp.
                    break
                end
                if RcUtils.testMode then -- dialog boxes and logging seem problematic when called from event handlers or maybe catalog functions(?)
                    -- _debugTrace( "would found or created: ", v )
                    -- logMessageLine( "WOULD create " .. v .. " (if not already existing)" )
                else
                    -- keyword = catalog:createKeyword( v, syn, incl, parent ) -- syn & incl parms not working for me here - dont remember details.
                    keyword = catalog:createKeyword( v, nil, true, parent, true ) -- I don't necessarily want to create it, but short of building the map, I don't know how else to do this. It'll probably be created anyway, otherwise user should purge...
                    if keyword then
                        -- logMessageLine( "Created " .. v .. " (if not already existing)" )
                        if i == #comps then -- end-point keyword
                            -- extra = keyword
                        end
                        parent = keyword
                    else
                        error( "Unable to created keyword: " .. RcLua.toString( v ) )
                    end
                end
            until true
        end
    end
    
    local attrs = nil
    local func2 = function()
        local syn = keyword:getSynonyms()
        local incl = keyword:getAttributes().includeOnExport -- does not return syns like doc says.
        attrs = { synonyms = syn, includeOnExport = incl }
    end
        
    local sts, msg = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Create Keywords For Attributes", func1 )
    
    if sts and keyword then
        func2() -- cat access not required.
        return attrs
    else
        return nil
    end
end



--[[
        Synopsis:           Get keyword spec for adding using dialog box.
        
        Notes:              keyword as simple end-point, path, or reversed path: text.
        
        Returns:            
--]]        
function KwC._getKeywordSpecFromUser( props )
    local keywordSpec = nil
    RcUtils.wrap( "Get Keyword For Add", false, function( context )
        local _props = LrBinding.makePropertyTable( context )
        _props.keywordName = ''
        _props.synonyms = ''
        -- do not initialize incl-on-exp - its absence indicates "do not change"
        local args = {}
        local contents = {}
        local title
        if props.allPhotos and #targetPhotos > 1 then
            title = 'Add or modify keyword - all selected photos'
        else
            title = 'Add or modify keyword - ' .. LrPathUtils.leafName( targetPhotos[props.photoIndex].path )
        end
        for i,v in ipairs( _G.keywordPaths ) do
            if v == props.editKeyword then
                _props.keywordName = v
                break
            end
        end
        --[[local photos
        if props.allPhotos then
            photos = targetPhotos
        else
            photos = { targetPhotos[props.photoIndex] }
        end
        local keyword = KwC._getKeywordFromText( photos, _G.props.editKeyword )
        if keyword then
            _props.keywordName = keyword
        end--]]
        if RcString.is( _props.keywordName ) then
            local attrs = KwC._getAttributes( _props.keywordName )
            if attrs then
                if attrs.synonyms then
                    _props.synonyms = table.concat( attrs.synonyms, ", " )
                else
                    _props.synonyms = ''
                end
                if attrs.includeOnExport then
                    _props.includeOnExport = attrs.includeOnExport
                else
                    _props.includeOnExport = nil
                end
            else
                _props.synonyms = ''
                _props.includeOnExport = nil
                _props.keywordName = ''
            end
        else
            _props.keywordName = props.editKeyword
        end 
        contents[#contents + 1] = vf:static_text {
           title = title,
           font = config.defaultFont,
        }
        contents[#contents + 1] = vf:spacer {
           height = 5,
        }
        contents[#contents + 1] = vf:static_text {
            title = "Keyword Name",
            font = config.defaultFont,
        }
        local enabled = #_G.keywordNames > 0
        contents[#contents + 1] = vf:row {
            vf:edit_field {
                width_in_chars = 30,
                font = config.defaultFont,
                fill_horizontal = 1,
                value = LrView.bind( "keywordName" ),
            },
            vf:push_button {
                title = '<',
                font = config.defaultFont,
                _props = _props,
                enabled = enabled,
                action = function( button )
                    -- does not need recursion guard since modal dialog pretty much covers it.
                    RcUtils.wrap( "Get Keyword Spec", true, function( context )
                        local __props = LrBinding.makePropertyTable( context )
                        for i,v in ipairs( _G.keywordPaths ) do
                            if button._props.keywordName == v then
                                __props.keywordName = v
                            end
                        end
                        if not __props.keywordName then
                            __props.keywordName = _G.keywordPaths[1]
                        end
                        local args = {}
                        local contents = { bind_to_object = __props }
                        contents[#contents + 1] = vf:static_text {
                            title = "Select keyword to view or modify",
                            font = config.defaultFont,
                        }
                        contents[#contents + 1] = vf:combo_box {
                            items = _G.keywordPaths,
                            font = config.defaultFont,
                            value = LrView.bind( 'keywordName' )
                        }
                        args.title = "Select Keyword"
                        args.contents = vf:column( contents )
                        args.save_frame = "AddKeywordForSpecBox"
                        local answer = LrDialogs.presentModalDialog( args )
                        if answer == 'ok' then
                            -- _debugTrace( "ok" )
                            button._props.keywordName = __props.keywordName
                            local attrs = KwC._getAttributes( button._props.keywordName )
                            if attrs then
                                if attrs.synonyms then
                                    button._props.synonyms = table.concat( attrs.synonyms, ", " )
                                else
                                    button._props.synonyms = ''
                                end
                                if attrs.includeOnExport then
                                    button._props.includeOnExport = attrs.includeOnExport
                                else
                                    button._props.includeOnExport = nil
                                end
                            else
                                button._props.synonyms = ''
                                button._props.includeOnExport = nil
                            end
                        else
                            -- button._props.keywordName = '' -- cancel selection
                            -- button._props.synonyms = ''
                            -- button._props.includeOnExport = nil
                        end
                        -- _debugTrace( "button ", button )
                    end ) -- no cleanup handler, default failure handler.
                end
            }
        }
        contents[#contents + 1] = vf:static_text {
            title = "Synonyms",
            font = config.defaultFont,
        }
        contents[#contents + 1] = vf:edit_field {
            width_in_chars = 30,
            font = config.defaultFont,
            height_in_lines = 3,
            fill_horizontal = 1,
            value = LrView.bind( "synonyms" ),
        }
        contents[#contents + 1] = vf:checkbox {
            title = 'Include On Export',
            font = config.defaultFont,
            value = LrView.bind( "includeOnExport" ),
        }
        contents.bind_to_object = _props
        args.title = "Add Keyword, or Modify Attributes"
        args.contents = vf:column( contents )
        args.save_frame = "AddKeywordBox"
        local button = LrDialogs.presentModalDialog( args )
        if button == 'ok' then
            keywordSpec = {}
            local attrs = {}
            keywordSpec.keywordName = _props.keywordName
            local synonyms = RcString.split( _props.synonyms, ',' )
            if #synonyms > 0 then
                attrs.synonyms = synonyms
            end
            if _props.includeOnExport ~= nil then
                attrs.includeOnExport = _props.includeOnExport
            end
            keywordSpec.attrs = attrs
        else
            -- stays nil
        end
    end )
    return keywordSpec
end



--[[
        Synopsis:           Removes specified keyword from one or more target photos.
        
        Notes:              - Which target photos to do is derived from specified properties.
                            - Keyword text comes from the combo box or by comparing keyword text to previous value.
                            - Wrapped mode is used when keyword removal used in conjunction with adding.
                              Unwrapped mode is used when removing via combo box.
                            - if successful - rebuild keyword text pane if necessary, upon return.
                            
        Returns:            sts[,msg]
--]]        
function KwC._removeKeyword( props, keywordText, wrapped )

    local sts, msg
    local removeKeywordFunc = function()
        if props.allPhotos then
            for i,photo in ipairs( targetPhotos ) do
                KwC._removeKeywordFromPhoto( props, photo, keywordText ) -- ignore removal errors in all-photos mode - generally means the photo did not have the keyword.
                sts = true
                -- sts, msg = KwC._removeKeywordFromPhoto( props, photo, keywordText )
                --if not sts then
                --    break
                --end
            end
        else
            sts, msg = KwC._removeKeywordFromPhoto( props, targetPhotos[props.photoIndex], keywordText )
        end        
        if not sts then
            error( msg ) -- this will propagate to status of pcall or with-catalog return value.
        end
    end
    
    if keywordText ~= '' then
        -- _debugTrace( "keyword to remove: ", keywordText )
        if wrapped then
            sts, msg = LrTasks.pcall( removeKeywordFunc )
        else
            sts, msg = RcUtils.withCatalogDo( 5, catalog.withWriteAccessDo, catalog, "Remove Keywords", removeKeywordFunc )
        end
        return sts, msg
    else
        return false, "no keyword to remove"
    end
    
end



--[[
        Synopsis:           edit-keyword field's 
        
        Notes:              
        
        Returns:            
--]]        
function KwC._anticipateEditKeyword( view, value )

    props = view._props

    local forward = false
    local comps
    if value:find( "[/\\]" ) then
        comps = RcString.breakdownPath( value )
        --forward = true
    elseif value:find( '>' ) then
        -- comps = KwC._breakdownReversePath( value )
        return false, value, "'>' is an invalid character: try /root/child until child > root notation supported."
    elseif value:find( '<' ) then
        -- error( "'<' is an invalid character: try /root/child or child > root notation." ) -- this won't happen since its pre-screened.
        return false, value, "'<' is an invalid character: try /root/child until child > root notation supported."
    else
        comps = { value }
    end
    
    if value:len() > 1 and RcString.lastChar( value ) == '/' then
        comps[#comps + 1] = '/'
    end
    
    local hints = {}
    
    local level = _G.kwListMap
    local targIndex = 0
    
    local done = false
    for i1, v1 in ipairs( comps ) do -- does not handle reverse case
        hints = {}
        repeat
            local comp
            if v1 == '/' then
                comp = nil
            else
                comp = LrStringUtils.lower( v1 )
            end
             -- _debugTrace( "comp: ", comp .. ", level-1 name: " .. level[1].name )
            targIndex = -1
            if level == nil then -- cheap insurance in case init not complete or something.
                return true, value
            end
            for i2, v2 in ipairs( level ) do
                -- logMessageLine( "comp level " .. i1 .. ": " .. v2.name )
                if comp == nil then
                    hints[#hints + 1] = v2.name
                else
                    local name = LrStringUtils.lower( v2.name )
                    if comp == name then
                        hints[#hints + 1] = v2.name
                        targIndex = i2
                    else
                        if name:find( comp ) == 1 then
                            hints[#hints + 1] = v2.name
                        end
                    end
                end
            end
            if #hints == 0 then
                done = true
                break
            elseif #hints == 1 then
                if i1 < #comps then
                    if level[targIndex] == nil or level[targIndex].tbl == nil then
                        --done = true
                        --break
                        level = {}
                    else
                        level = level[targIndex].tbl
                        --_debugTrace( "new level: ", level[1].name )
                         -- hints = {}
                    end
                end
            end
        until true
        if done then
            break
        end
    end

    -- _debugTrace ( "#hints: ", RcLua.toString( #hints ) )
    local hintString = table.concat( hints, "\r\n" )
    -- logMessageLine( "got hints: " .. hintString )
    props.keywordHint = hintString
    
    local newValue
    if #hints == 0 then
        _G.props.keywordMode = true
        _G.props.enableAcceptButton = false
        newValue = value
    elseif #hints == 1 then
        _G.props.keywordMode = false
        _G.props.enableAcceptButton = true
        newValue = '/' 
        for i = 2, #comps - 1 do 
            newValue = newValue .. comps[i] .. '/' -- forward only...
        end
        newValue = newValue .. hints[1]
    else
        _G.props.keywordMode = false
        _G.props.enableAcceptButton = false
        newValue = value
    end    
    return true, newValue

end



--[[
        Synopsis:           Executes the specified command via the windows command shell.
        
        Notes:              format is typically a path to an executable, with parms, properly quoted.
        
        Returns:            Nothing at the moment, but proably should return execution status. ###1
--]]        
function KwC._executeWindowsCommand( command )
    if WIN_ENV then
        local exe = LrPathUtils.child( _PLUGIN.path, command )
        if RcFileUtils.exists( exe ) then -- must use borrowed form since this is called pre- rc-file-utils init.
            local sts = LrTasks.execute( exe )
            -- local sts = 0
            if sts ~= nil and sts == 0 then 
                logMessageLine( "Executed command: " .. exe, VERBOSE )
            else
                logError( "Unable to execute command: " .. exe, VERBOSE )
            end
        else
            logError( "Command file is missing: " .. exe, VERBOSE )
        end
    end
end



--[[
        Synopsis:           Initializes windows auto-hot-key helper scripts.
        
        Notes:              Presently a no-op on mac.
                            Just starts a task and returns.
        
        Returns:            nothing.
--]]        
function KwC.initKeyHelpers()
    if WIN_ENV then
        RcUtils.wrap( "Init Key Helpers", true, function() -- best if errors are caught - context ignored.
            KwC._executeWindowsCommand( "LrKwC_Ctrl-Tab.ahk" )
        end )
    -- else Does not work on Mac - there is a difference between programmatic keys and user typed keys.
    end
end



--[[
        Synopsis:           Issued in response to the keyword add button on windows, since focus is shifted.
        
        Notes:              - does nothing if mac, since focus does not change by clicking buttons.
        
                            - Depends on edit field being just before add button.
        
        Returns:            nothing.
--]]        
function KwC._returnToKeywordEditField()
    if WIN_ENV then
        KwC._executeWindowsCommand( "ShiftTabKey.vbs" )
    else
        -- KwC._executeMacCommand( "ShiftTabKey" ) - keyword edit field is not departed when clicking buttons on Mac.
    end
end



--[[
        Synopsis:           Called when user clicks anything outside the keyword-to-add field,
                            to return edit mode to normal keyword list and cancel keyword look-ahead entry...
        Notes:              
        
        Returns:            
--]]        
function KwC._releaseKeywordEdit()
    _G.props.enableAcceptButton = false
    _G.props.keywordMode = true
end



--[[
        Synopsis:           Guts of function serving menu initiated keyword list feature.
        
        Notes:              Presents form and handles button events + field change events.
        
        Returns:            Nothing.
--]]        
function KwC._viewKeywordList( context )

    -- assert( config.defaultFont ~= nil, "no font" )
    if _G.config == nil then
        logError( "Plugin initialization error: " .. RcLua.toString( _G.initMsg ) )
        quit = true
        quitMessage = "Initialization error."
        return
    elseif _G.initMsg then
        logMessageLine( RcLua.toString( _G.initMsg ) )
    end
    quit = false
    quitMessage = ''
    prefs = LrPrefs.prefsForPlugin()
    vf = LrView.osFactory()
    catalog = LrApplication.activeCatalog()
    targetPhotos = catalog.targetPhotos
    if targetPhotos == nil or #targetPhotos == 0 then
        showWarning( "No target photos." )
        quit = true
        quitMessage = "No target photos."
        return
    end
    selectedPhoto = catalog.targetPhoto
    if not selectedPhoto then
        catalog:setSelectedPhotos( targetPhotos[1], targetPhotos )
    end

    local button = ''
    if not _G.initializing and not _G.initialized then
        -- this would hopefully only be the case when auto-init is turned off.
        button = RcUtils.showInfo( "Perform lengthy initialization? ('Keyword list' will function without being initialized, but its slower, and can't do look-ahead anticipation as 'Keyword to add' is being typed), and it may also log some warnings. - consider auto-init in plugin manager.", "AutoInitPrompt2", {{ label="Initialize And Wait", verb='iWait'},{ label="Initialize But Dont Wait", verb='iGo'}} )
        -- _debugTrace( "btn: ", button )
        if button == 'iGo' then
            KwC._initData( true ) -- Initialize asynchronously. sets initializing flag, or maybe quit flag.
        elseif button == 'iWait' then
            KwC._initData( false ) -- sets initializing flag, or maybe quit flag.
        else
            quit = true
            quitMessage = "Initialization cancelled."
            return
        end
    end

    if quit then
        return
    end
    
    if button ~= 'iGo' and not _G.initialized then
        local answer = showInfo( "Click 'OK' to dismiss this prompt - the 'Keyword List Form' will be presented once initialization is complete, or click 'Continue Without Init' to keep going without benefit of initialization, or 'Cancel' to quit for now.", nil, "OK", "Cancel", "Continue Without Init" )
        -- _debugTrace( "ans: ", answer )
        if answer == 'ok' then
            while( not _G.initialized ) do
                LrTasks.sleep( 1 )
            end
        elseif answer == 'other' then
            -- keep going
        else
            quit = true
            quitMessage = "Initialization incomplete - 'Keyword List Form' cancelled."
            return
        end
    end
    
    if quit then
        return
    end

    RcUtils.opTitle = "Keyword List Form" -- ###2
    
    if _G.initialized then    
        if RcTable.isEmpty( _G.kwListMap ) then
            logWarning( "Keyword list map is empty - if you have any keywords defined in this catalog, it should not be." )
        end
    end

    -- RcUtils.logObject( _G.kwListMap )
   
    _G.props = LrBinding.makePropertyTable( context )
    local args = {}
    local buttons = {}
    props.photoIndex = 1
    buttons[#buttons + 1] = vf:push_button {
        title = "All Photos",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "All Photos Button", false, function( context )
                KwC._releaseKeywordEdit()
                _G.switchInProgress = true -- keeps commit function from jumping in too soon.
                RcUtils.wrap( "All Photos Task", true, function()
                    KwC._closeEdits( props ) -- same action regardless of errors.
                    if not props.allPhotos then
                        props.allPhotos = true
                    else
                        props.allPhotos = false
                        catalog:setSelectedPhotos( targetPhotos[props.photoIndex], targetPhotos )
                    end
                    KwC._reloadForm( props )
                end, function()
                    _G.switchInProgress = false
                end )
            end )
        end,
    }
    buttons[#buttons + 1] = vf:push_button {
        title = "|<",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "First Photo Button", false, function( context )
                KwC._releaseKeywordEdit()
                if not props.allPhotos and props.photoIndex == 1 then
                    return
                end
                _G.switchInProgress = true -- keeps commit function from jumping in too soon.
                RcUtils.wrap( "First Photo Task", true, function()
                    KwC._closeEdits( props )
                    props.allPhotos = false
                    props.photoIndex = 1
                    catalog:setSelectedPhotos( targetPhotos[props.photoIndex], targetPhotos )
                    KwC._reloadForm( props )
                end, function()
                    _G.switchInProgress = false
                end )
            end )
        end,
    }
    buttons[#buttons + 1] = vf:push_button {
        title = "<",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "Previous Photo Button", false, function( context )
                KwC._releaseKeywordEdit()
                if not props.allPhotos and props.photoIndex == 1 then
                    return
                end
                _G.switchInProgress = true -- keeps commit function from jumping in too soon.
                RcUtils.wrap( "Previous Photo Task", true, function()
                    KwC._closeEdits( props )
                    props.allPhotos = false
                    if props.photoIndex > 1 then
                        props.photoIndex = props.photoIndex - 1
                    end
                    catalog:setSelectedPhotos( targetPhotos[props.photoIndex], targetPhotos )
                    KwC._reloadForm( props )
                end, function()
                    _G.switchInProgress = false
                end )
            end )
        end,
    }
    buttons[#buttons + 1] = vf:push_button {
        title = ">",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "Next Photo Button", false, function( context )
                KwC._releaseKeywordEdit()
                if not props.allPhotos and props.photoIndex >= #targetPhotos then
                    return
                end
                -- tried outputting a tab key via mac script turned app but it did not work - tab key happened, but field still not committed.
                _G.switchInProgress = true -- keeps commit function from jumping in too soon.
                RcUtils.wrap( "Next Photo Task", true, function( context )
                    KwC._closeEdits( props )
                    props.allPhotos = false
                    if props.photoIndex < #targetPhotos then
                        props.photoIndex = props.photoIndex + 1
                    end
                    catalog:setSelectedPhotos( targetPhotos[props.photoIndex], targetPhotos )
                    KwC._reloadForm( props )
                end, function( status, other )
                    _G.switchInProgress = false
                end )
            end )
        end,
    }
    buttons[#buttons + 1] = vf:push_button {
        title = ">|",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "Last Photo Button", false, function( context )
                KwC._releaseKeywordEdit()
                if not props.allPhotos and props.photoIndex >= #targetPhotos then
                    -- _debugTrace( "ret" )
                    return
                end
                _G.switchInProgress = true -- keeps commit function from jumping in too soon.
                RcUtils.wrap( "Last Photo Task", true, function( context )
                    KwC._closeEdits( props )
                    props.allPhotos = false
                    props.photoIndex = #targetPhotos
                    catalog:setSelectedPhotos( targetPhotos[props.photoIndex], targetPhotos )
                    KwC._reloadForm()
                end, function( status, other )
                    _G.switchInProgress = false
                end )
            end )
        end,
    }
    buttons[#buttons + 1] = vf:push_button {
        title = "Apply Edits",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "Apply Edits", false, function( context )
                KwC._releaseKeywordEdit()
                if KwC._checkForEdits( props ) then
                    LrTasks.startAsyncTask( function()
                        KwC._closeEdits( props )
                        KwC._reloadForm( props )
                    end )
                else
                    showInfo( "There are no unapplied edits pending to apply.", "NoEditsToApplyPrompt" )
                end
            end )
        end
    }
    buttons[#buttons + 1] = vf:push_button {
        title = "Discard Edits",
        font = config.defaultFont,
        action = function( button )
            RcUtils.wrap( "Discard Edits", false, function( context )
                KwC._releaseKeywordEdit()
                _G.props.title = _G.prev_title
                _G.props.caption = _G.prev_caption
                _G.props.keywordList = _G.prevKeywordList
            end )
        end
    }
    buttons[#buttons + 1] = vf:push_button {
        title = "Keyword View",
        action = function( button )
            RcUtils.wrap( "Keyword View", false, function( context )
                _G.props.editKeyword = LrStringUtils.trimWhitespace( _G.props.editKeyword or '' )
                if RcString.is( _G.props.keywordHint ) and RcString.is( _G.props.editKeyword ) then
                    _G.props.keywordMode = not _G.props.keywordMode
                else
                    _G.props.keywordList = LrStringUtils.trimWhitespace( _G.props.keywordList or '' )
                    if not RcString.is( _G.props.keywordList ) then
                        _G.props.keywordMode = true
                        showInfo( "No keywords are assigned to this photo." )
                    end
                end
            end )
        end
    }
    local buttonRow = vf:row( buttons )
    --if prefs.reversePaths then
    --    props.reversePaths = prefs.reversePaths
    --else
        props.reversePaths = false
    --end
    if prefs.viewPaths ~= nil then
        props.viewPaths = prefs.viewPaths
    else
        props.viewPaths = true
    end
    if prefs.sortEndpoints ~= nil then
        props.sortEndpoints = prefs.sortEndpoints
    else
        props.sortEndpoints = true
    end
    props.allPhotos = false
    props.keywordList = ''
    props.keywordHint = ''
    props.keywordMode = true
    
    local lineHeight
    if prefs.lineHeight ~= nil then
        lineHeight = tonumber( prefs.lineHeight )
    else
        lineHeight = 15
    end
    
    local fontSpec
    if config.keywordListFont == nil then
        if config.defaultFont == nil then
            if prefs.smallFont then
                fontSpec = '<system/small>'
            else
                fontSpec = "<system>"
            end
        else
            fontSpec = config.defaultFont
        end
    else
        fontSpec = config.keywordListFont
    end
    local keywordPane = vf:view {  
        place = 'overlapping',
        fill_horizontal = 1,
        vf:edit_field {
            height_in_lines = lineHeight,
            font = fontSpec,
            width_in_chars = 45,
            fill_horizontal = 1,
            value = LrView.bind ( 'keywordHint' ),
            enabled = false,
            visible = LrBinding.negativeOfKey( 'keywordMode' ),
        },
        vf:edit_field {
            height_in_lines = lineHeight,
            font = fontSpec,
            width_in_chars = 45,
            fill_horizontal = 1,
            value = LrView.bind ( 'keywordList' ),
            visible = LrView.bind( 'keywordMode' ),
            immediate = true, -- hang onto the progressing value since mac not commiting properly. - Incompatible with commit function ala property observer.
            validate = function( view, value )
                local sts = true
                local retVal = value
                local errMsg = nil
                RcUtils.wrap( "Keyword List Validation", false, function( context )
                    if not _G.props.viewPaths then
                        LrTasks.startAsyncTask( function()
                            _G.props.viewPaths = true
                            KwC._reloadForm()
                        end )
                        retVal = _G.props.keywordList
                    elseif not RcString.is( _G.props.keywordList ) and #_G.keywordPaths > 0 then
                        LrTasks.startAsyncTask( function()
                            KwC._reloadForm()
                        end )
                        value = _G.props.keywordList -- Note: this is a fail-safe. If all goes well, re-load form will overwrite the value in short order. This
                            -- just makes sure if there is an error in form re-loading, we're not left with all keywords disappeared.
                    else
                        -- cool2
                    end
                end )
                return sts, retVal, errMsg
            end
        }
    }
        
    local contents = { bind_to_object = props }
    props.filePath = 'Working...'
    contents[#contents + 1] = vf:static_text {
        title = "Photo(s) being edited",
    }
    contents[#contents + 1] = vf:edit_field {
        fill_horizontal = 1,
        font = config.defaultFont,
        value = LrView.bind( 'filePath' ),
        enabled = false,
        immediate = true,
        _props = props,
    }
    contents[#contents + 1] = vf:spacer {
        height = 5,
    }
    contents[#contents + 1] = vf:static_text {
        title = 'Title',
        font = config.defaultFont,
    }
    contents[#contents + 1] = vf:edit_field {
        fill_horizontal = 1,
        font = config.defaultFont,
        value = LrView.bind( 'title' ),
        immediate = true, -- hang onto the progressing value since mac not commiting properly. - Incompatible with commit function ala property observer.
        validate = function( view, value )
            _G.props.keywordMode = true
            return true, value
        end
    }
    contents[#contents + 1] = vf:static_text {
        title = 'Caption',
        font = config.defaultFont,
    }
    contents[#contents + 1] = vf:edit_field {
        fill_horizontal = 1,
        font = config.defaultFont,
        height_in_lines = 2,
        value = LrView.bind( 'caption' ),
        immediate = true, -- hang onto the progressing value since mac not commiting properly. - Incompatible with commit function ala property observer.
        validate = function( view, value )
            _G.props.keywordMode = true
            return true, value
        end
    }
    contents[#contents + 1] = vf:spacer { height = 10 }
    contents[#contents + 1] = buttonRow
    contents[#contents + 1] = vf:spacer{ height = 10 }
    contents[#contents + 1] = vf:static_text {
        title = "Keyword to add",
    }
    contents[#contents + 1] = vf:row {
        vf:edit_field {
            fill_horizontal = 1,
            font = config.defaultFont,
            height_in_lines = 1,
            value = LrView.bind( 'editKeyword' ),
            immediate = true, -- hang onto the progressing value since mac not commiting properly. - Incompatible with commit function ala property observer.
            _props = props,
            validate = function( view, value )
                -- check for illegal characters? - its done when pressing '+' anyway so not much point actually.
                if value:len() > 0 then
                    if string.find( value, '<', 1, true ) then
                        return false, value, "Reverse path notation not yet supported, use forward path notation with '/' as separator."
                    elseif string.find( value, '<', 1, true ) then
                        return false, value, "Reverse path notation uses '>' as separator, and anyway its not yet supported, use forward path notation with '/' as separator."
                    elseif string.find( value, '\\', 1, true ) then
                        return false, value, "Use forward path notation with '/' as separator."
                    else
                        return KwC._anticipateEditKeyword( view, value )
                    end
                else
                    _G.props.keywordMode = true
                end
            end
        },
        vf:push_button {
            title = "+",
            font = config.defaultFont,
            action = function( button )
                -- _debugTrace( "add" )
                if props.editKeyword then
                    props.editKeyword = LrStringUtils.trimWhitespace( props.editKeyword )
                end
                if not RcString.is( props.editKeyword ) or props.editKeyword == '/' then
                    showWarning( "Enter keyword name or path first, then click '+' (or use '++')." )
                    return
                end
                KwC._releaseKeywordEdit()
                LrTasks.startAsyncTask( function()
                    local sts, msg = KwC._closeEdits( props ) -- not sure what to do differently based on status!?
                    local added, other = KwC._addKeyword( props, props.editKeyword )
                    if added then
                        -- _debugTrace( "added" )
                        props.editKeyword = ''
                        KwC._reloadForm( props )
                        KwC._returnToKeywordEditField()
                    elseif sts then
                        KwC._reloadForm( props )
                    end
                end )
            end
        },
        vf:push_button {
            title = "++",
            font = config.defaultFont,
            action = function( button )
                KwC._releaseKeywordEdit()
                LrTasks.startAsyncTask( function()
                    local sts, msg = KwC._closeEdits( props )
                    if sts then
                         KwC._reloadForm( props ) -- recomputes keyword-names.
                    end
                    local keywordSpec = KwC._getKeywordSpecFromUser( props )
                    if keywordSpec then
                        local added, msg = KwC._addKeyword( props, keywordSpec )
                        if added then
                            -- _debugTrace( "added" )
                            KwC._reloadForm( props )
                        else
                            -- _debugTrace( "not added ", msg )
                            -- showError( "" ) - error already shown.
                        end
                    end
                end )
            end
        },
        vf:push_button {
            title = "-",
            font = config.defaultFont,
            action = function( button )
                KwC._releaseKeywordEdit()
                LrTasks.startAsyncTask( function() 
                    local sts,msg = KwC._closeEdits( props )
                    if sts then
                         KwC._reloadForm( props ) -- recomputes keyword-names.
                    end
                    local keywordText = KwC._getKeywordToRemoveFromUser( props )
                    if keywordText ~= '' then
                        local removed, msg = KwC._removeKeyword( props, keywordText, false )
                        if removed then
                            KwC._reloadForm( props )
                        elseif msg then
                            showError( "Unable to remove keyword, error message: " .. RcLua.toString( msg ) )
                        end
                    else
                    end
                end )
            end
        },
    }
    props.enableAcceptButton = false
    -- reminder: one can not force Mac to commit a field edit by programmatic tabbing - has to be the real thing.
    -- thus, this button does no good on a Mac.
    if WIN_ENV then
        contents[#contents + 1] = vf:spacer {
            height = 2,
        }
        contents[#contents + 1] = vf:push_button {
            title = 'a c c e p t   k e y w o r d   b e l o w',
            font = config.defaultFont,
            fill_horizontal = 1,
            enabled = LrView.bind( 'enableAcceptButton' ),
            action = function( button )
                RcUtils.wrap( "Accept Keyword Below", true, function( context )
                    if WIN_ENV then
                        KwC._executeWindowsCommand( "4ShiftTabs1EndKey.vbs" )
                        _G.props.enableAcceptButton = false
                        _G.props.keywordMode = true
                    else
                        --[[ KwC._executeMacCommand( "TabShiftTabRightKeys" ) - this control not present on Mac: must use quick-key...
                        _G.props.enableAcceptButton = false
                        _G.props.keywordMode = true--]]
                    end
                end )
            end
        }
    end
    contents[#contents + 1] = vf:spacer {
        height = 5,
    }
    function updateView( props, key, value )
        KwC._releaseKeywordEdit()
        prefs.viewPaths = props.viewPaths
        prefs.reversePaths = props.reversePaths
        prefs.sortEndpoints = props.sortEndpoints
        LrTasks.startAsyncTask( function()
            KwC._reloadForm( props )
        end )
    end
    --[[function commitField( props, key, value )
        if _G.switchInProgress then
            -- _debugTrace( "not commiting" )
            return
        end            
        if not _G.fieldUpdateInProgress then
            -- _debugTrace( "checking" )            
            if KwC._checkForFieldEdits( props, key, value ) then
                _G.fieldUpdateInProgress = true
                -- _debugTrace( "commit field task starting" )            
                LrTasks.startAsyncTask( function()
                    KwC._applyFieldEdits( props, key, value )
                    _G.fieldUpdateInProgress = false
                end )
            end
        end
    end--]]
    --[[function commitKeyword( props, key, value )
        -- _debugTrace( "commit" )
        -- Lightroom has a way of "overcalling commit
        -- its worth checking whether it really needs to execute
        -- before starting a task to do it.
        if _G.switchInProgress then -- do not proceed if in mid photo-switch.
            return
        end            
        if not _G.keywordUpdateInProgress then -- if already in mid-update, do not proceed with update.
            if RcString.is( value ) then
                _G.keywordUpdateInProgress = true
                -- _debugTrace( "commit task" )            
                LrTasks.startAsyncTask( function()
                    if _G.newValueSaved and _G.newValueSaved == props.editKeyword then
                        local sts, msg = KwC._addKeyword( props, value ) -- note: does not reload form.
                        if sts then
                            props.editKeyword = ''
                            KwC._reloadForm( props )
                        else
                            -- presumably not necessary to reload if add failed.
                        end
                    else
                        -- _debugTrace( "new-value-saved: ", RcLua.toString( _G.newValueSaved ) .. ", props: " .. props.editKeyword  )
                    end
                    _G.keywordUpdateInProgress = false
                end )
            end
        end
    end--]]
    --[[function commitKeywords( props, key, value )
        -- _debugTrace( "commit" )
        -- Lightroom has a way of "overcalling commit
        -- its worth checking whether it really needs to execute
        -- before starting a task to do it.
        if _G.switchInProgress then -- do not proceed if in mid photo-switch.
            return
        end            
        if not _G.keywordUpdateInProgress then -- if already in mid-update, do not proceed with update.
            if KwC._checkForKeywordEdits( props, key, value ) then -- if nothings changed, do not proceed with update.
                -- Note: changes are compared against previous values saved when form was reloaded, not against initial blank form values.
                _G.keywordUpdateInProgress = true
                -- _debugTrace( "commit task" )            
                LrTasks.startAsyncTask( function()
                    KwC._applyKeywordListEdits( props, key, value ) -- note: does not reload form.
                    _G.keywordUpdateInProgress = false
                end )
            end
        end
    end--]]
    props:addObserver( 'viewPaths', updateView )
    props:addObserver( 'sortEndpoints', updateView )
    props:addObserver( 'reversePaths', updateView )
    -- props:addObserver( 'title', commitField )
    -- props:addObserver( 'caption', commitField )
    -- props:addObserver( 'editKeyword', commitKeyword )
    -- props:addObserver( 'keywordList', commitKeywords )
    contents[#contents + 1] = vf:row {
        vf:static_text {
            title = "Keyword list",
        },
        vf:checkbox {
            title = "Paths",
            font = config.defaultFont,
            value = LrView.bind( 'viewPaths' ),
        },            
        vf:checkbox {
            title = "Parental Order",
            enabled = LrView.bind( 'viewPaths' ),
            value = LrBinding.negativeOfKey( 'sortEndpoints' ),
        },
    }
    contents[#contents + 1] = keywordPane
    -- contents[#contents + 1] = vf:spacer{ height = 10 }
    -- contents[#contents + 1] = boxRow
    local targetPhoto = catalog.targetPhoto
    if targetPhoto then
        for i,v in ipairs( targetPhotos ) do
            if v == targetPhoto then
                props.photoIndex = i
                break
            end
        end
    end
    RcUtils.wrap( "Initialize Keyword List Form", true, KwC._reloadForm ) -- does not need to be a task, but this way the form comes up quicker,
        -- possibly saying "Loading...", instead of a long startup delay. No cleanup handler, default failure handler.
    args.title = "Keyword List Form"
    args.contents = vf:view( contents )
    args.save_frame = "KeywordListMain"
    args.accessoryView = vf:row { 
        vf:push_button {
            title = 'Quick Tips',
            font = config.defaultFont,
            action = function( button )
                RcUtils.wrap( "Quick Tips", false, function( context )
                    KwC._releaseKeywordEdit()
                    local m = {}
                    m[#m + 1] = "There are three ways to add keywords: (1) Insert full path in '/root/parent/child...' notation anywhere in the 'Keyword list'. (2) Type full-path in '/root/parent/child...' notation in the 'Keyword to add' field then press '+'. (3) '++' can also be used to add keywords one at a time and offers the capability to define non-default attributes, as well as the ability to view/modify attributes of existing keywords."
                    m[#m + 1] = "For 'Keyword to add', I strongly recommend using QuickKeys (or something like it - maybe even OS proper) to configure your Mac with a 'tab,shift-tab,right-arrow' keystroke sequence to streamline keyword entry. Windows users should download & install AutoHotKey and then use Ctrl-Tab for this sequence, or click the 'a c c e p t ...' button."
                    m[#m + 1] = "Use Ctrl-J (on Windows), or Option-Return (on Mac) to enter a line feed into the 'Keyword list' in order to add multiple keywords. Make sure to cursor to the desired insertion point first."
                    m[#m + 1] = "There are two ways to remove keywords: (1) Select and delete them from the 'Keyword list'. (2) Click '-' and select the keyword to remove from the drop-down."
                    m[#m + 1] = "Keywords removed from photos are not deleted from Lightroom. To delete keywords entirely, use Lightroom proper."
                    m[#m + 1] = "'Title', 'Caption', and 'Keyword list' edits are saved when you click one of the navigation buttons ('All Photos', '|<', '<', '>', '>|') or one of the keyword entry buttons ('+', '++', '-'). If you just want to apply the changes and stay where you are, then click 'Apply Edits'. 'Keyword to add' is only added when clicking the '+' button."
                    m[#m + 1] = "I highly recommend moving the 'Keyword List Form' and the other subsidiary boxes so you can see Lightroom proper while working - their locations will be remembered."
                    m[#m + 1] = "The only difference between the 'OK' button and the 'Cancel' button, is that 'OK' will save any un-saved changes before exiting - cancel will discard them."
                    m[#m + 1] = "Quickest way to start is using the keystroke sequence: Alt-F-S-K (Windows Only). Mac users can configure a shortcut for quick-start by using built-in OS features, or something like QuickKeys."
                    RcGui.quickTips( m )                    
                end )
            end
        },
    }
    
    repeat
        local button = LrDialogs.presentModalDialog( args )
        -- _debugTrace( "button: ", button )
        if button == 'ok' then
            local sts, msg = KwC._closeEdits( props )
            if not sts and msg then
                if RcUtils.isOk( "Edits have not been applied - exit anyway?" ) then
                    break
                end
            else
                break
            end
        else
            break
        end
    until false
end




--[[-------------------------------------------------------------------------------
    
    Section Synopsis:       Public functions.
    
    Notes:                  - quit flag and message not supported.
                            - logging only done in test mode or optimize function.
    
-----------------------------------------------------------------------------------]]



--[[
        Synopsis:           Serves 'Keyword List' menu initiated function.
        
        Notes:              The one-instance flags are hardly necessary, since the modal dialog box comes up pretty fast,
                            which would preclude starting another instance, but still: seems like cheap insurance to me.
        
        Returns:            
--]]        
function KwC.viewKeywordList()

    local opName = "Keyword List Form"
    RcUtils.wrapGuarded( opName, true, function( context )
        KwC._init( opName )
        KwC._viewKeywordList( context ) -- inits the quits
    end, function( status, message )        
        RcUtils.endWrap( opName, status, message, quit, quitMessage )
    end )
        
end   
   


--[[
        Synopsis:           Serves 'Reset Ignore Lists' button in plugin manager.
        
        Notes:              Called as plugin manager button handler so no errors thrown.
        
        Returns:            X - errors handled within.
--]]        
function KwC.resetIgnoreList( props )

    local opName = "Reset Ignore List"
    RcUtils.wrap( opName, true, function( context ) -- doesn't have to run as a task (and didn't used to, pre-wrap),
        -- but the guarded wrap has been working great and this way if something inside ever yields or sleeps it won't bomb...
        
        quit = false
        quitMessage = ''

        RcUtils.initService( props.testMode, props.logFilePath, props.logVerbose, props.logOverwrite, opName )

        assert( props ~= nil, "no props" )
        assert( RcUtils ~= nil, "no utils" )
        assert( props.testMode ~= nil, "no test mode prop" )
        
        
        assert( RcUtils.testMode ~= nil, "no test mode in utils" )
        
        local path = LrPathUtils.child( LrPathUtils.parent( LrApplication.activeCatalog():getPath() ), "RcKeywordConsolidatorSupport.lua" )
        if RcFileUtils.existsAs( path, 'file', false ) then
            if RcUtils.isOk( "Move " .. path .. " to trash?" ) then
                local sts, qual = RcFileUtils.moveToTrash( path )
                if sts then
                    if qual then
                        showInfo( 'Ignore file NOT actually deleted: ' .. RcLua.toString( qual ) )
                    else
                        ignoreNames = {}
                        ignorePaths = {}
                        showInfo( 'Ignore file deleted - similarities to ignore list is hereby starting over...' )
                    end
                else
                    showError( "Unable to reset ignore list file, qualification: " .. RcLua.toString( qual ) )
                end
            end
        else
            showWarning( "Ignore list file does not exist: " .. path )
        end
        
    end, function( status, message )
        RcUtils.endWrap( opName, status, message, quit, quitMessage )
    end )
    
end   
    


--[[
        Synopsis:           Serves menu initiated consolidation function.
        
        Notes:              
        
        Returns:            
--]]        
function KwC.consolidate()
    local opName = "Keyword Consolidation Session"
    RcUtils.wrapGuarded( opName, true, function( context )
        KwC._init( opName )
        KwC._consolidate( context ) -- inits quits
    end, function( status, message )
        RcUtils.endWrap( opName, status, message, quit, quitMessage )    
    end )
end



--[[
        Synopsis:           Serves 'Init for Consolidate' button presented in plugin manager.
        
        Notes:              - Beware MAY be plugin init environment...
                            - Does not init-service, since services are not nestable (e.g. rc-utils only has only one log-file variable).
        
        Returns:            X - its a plugin init and button handler function.
--]]        
function KwC.initStart()
    if not _G.initializing then -- must not be internal recursion guard, since checked externally.
        KwC._initData( true ) -- task-wrapped in calling context.
    else
        showInfo( "Already initializing..." ) -- this probably never happens.
    end
end



--[[
        Synopsis:           Serves 'Remove Parents' button presented in plugin manager.
        
        Notes:              
        
        Returns:            
--]]        
function KwC.removeParents()
    local opName = "Removing Parent Keywords"
    RcUtils.wrapGuarded( opName, true, function( context )
        KwC._init( opName )
        KwC._removeParents( opName, context ) -- inits quits
    end, function( status, message )
        RcUtils.endWrap( opName, status, message, quit, quitMessage )
    end )
end



--- Consolidate keywords from one tree to another tree.
function KwC.autoConsolidateTrees()
    local opName = "Auto-consolidating trees"
    RcUtils.wrapGuarded( opName, true, function( context )
        KwC._init( opName )
        KwC._autoConsolidateTrees( opName, context ) -- inits quits
    end, function( status, message )
        RcUtils.endWrap( opName, status, message, quit, quitMessage )
    end )
end



return KwC

