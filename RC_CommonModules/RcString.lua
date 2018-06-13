--[[----------------------------------------------------------------------------

Filename:			RcString.lua

Synopsis:			String utils to supplement lua and/or lightroom SDK.

Limitations:        - None I can think of.

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
------------------------------------------------------------------------------------

Edit History:       2009-02-13: Enhanced by Rob Cole...

--------------------------------------------------------------------------------

To Do:              - See ### & ??? spots.

------------------------------------------------------------------------------]]


-- Define this module:
local RcString = {}


-- Evaluate pre-requisites:
assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


-- Lightroom dependencies:
local LrStringUtils = RcModuleLoader.import( 'LrStringUtils' ) -- include lr-string-utils emulation in non-lightroom environment.
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' ) -- include lr-string-utils emulation in non-lightroom environment.


-- Rc dependencies:
local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )



local pluralLookup
local singularLookup



--[[
        Synopsis:           Break down a file path into an array of components.
        
        Notes:              1st component is root.
        
        Returns:            array, usually not empty, never nil.
--]]        
function RcString.breakdownPath( path )
    local a = {}
    local p = LrPathUtils.parent( path )
    local x = LrPathUtils.leafName( path )
    
    while x do
        a[#a + 1] = x
        if p then
            x = LrPathUtils.leafName( p )
        else
            break
        end
        p = LrPathUtils.parent( p )
    end

    local b = {}
    local i = #a
    while i > 0 do
        b[#b + 1] = a[i]
        i = i - 1
    end
    return b
end



--[[
        Synopsis:           Split a string based on delimiter.
        
        Notes:              - Seems like there should be a lua or lr function to do this, but I haven't seen it.
                            - components returned are trimmed.
                            - return components may be empty string if repeating delimiters exist.
        
        Returns:            array of trimmed components - never nil nor empty table unless input is nil or empty string.
--]]        
function RcString.split( s, delim )

    if s == nil then return nil end
    if s == '' then return {} end
    local t = {}
    local p = 1
    repeat
        local start, stop = s:find( delim, p, true )
        if start then
            t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p, start - 1 ) )
            p = stop + 1
        else
            t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p ) )
            break
        end
    until false
    return t
end



function RcString.makePathFromComponents( comps )

    local path = comps[1]

    for i = 2, #comps do
        path = LrPathUtils.child( path, comps[i] )
    end

    return path

end
        



--[[
		Synopsis:			Determine if two strings are equal other than case differences.
--]]
function RcString.equalIgnoringCase( s1, s2 )
	local s1l = string.lower( s1 )
	local s2l = string.lower( s2 )
	return s1l == s2l
end
RcString.isEqualIgnoringCase = RcString.equalIgnoringCase -- synonym to support boolean function naming convention.


--[[
		Synopsis:			Makes a string of spaces - used for indentation and output formatting...

		Notes:				Not very efficient so use sparingly.
--]]
function RcString.makeSpace( howMany )
	local i = 1
	local spaces = {}
	while( i <= howMany ) do
		spaces[#spaces + 1] = ' '
		i = i + 1
	end
	return table.concat( spaces, '' )
end



--[[
        Synopsis:           Remove spaces from middle of a string (as well as ends).
        
        Notes:              Convenience function to make more readable.
        
        Returns:            squeezed string, nil -> empty.
--]]        
function RcString.squeeze( s )
    if s == nil then
        return ''
    else
        return s:gsub( " ", '' )
    end
end



--[[
        Synopsis:       Squeezes a path to fit into fixed width display field

        Format:         first-part-of-path.../filename.

        Initial Application:    progress caption, where path/filename will be auto-truncated if not formatted explicitly.
                        ###2 I think caption does this automatically - this may make things worse in that case.
--]]
function RcString.squeezePath( _path, _width )
    local len = string.len( _path )
    if len <= _width then
        return _path
    end
    -- fall-through => path reduction necessary.
    local dir = LrPathUtils.parent( _path )
    local filename = LrPathUtils.leafName( _path )
    local fnLen = string.len( filename )
    local dirLen = _width - fnLen - 4 -- dir len to be total len less filename & .../
    if dirLen > 0 then
        dir = string.sub( dir, 1, dirLen ) .. ".../"
        return dir .. filename
    else
        return filename -- may still be greater than width. If this becomes a problem, return substring of filename,
            -- or even first...last.
    end
end
        

--[[
        Synopsis:       Squeezes a path to fit into fixed width display field

        Format:         first half ... last half

--]]
function RcString.squeezeToFit( _str, _width )

    local sz = ( _width - 3 ) / 2
    if sz > 0 and sz < ( _str:len() - 5 ) then
        return _str:sub( 1, sz ) .. "..." .. _str:sub( _str:len() - sz )
    else
        return _str
    end

end
        


--[[
        Synopsis:       Pads a string on the left with specified character up to width.

        Motivation:     Typically used with spaces for tabular display, or 0s when string represents a number.
--]]
function RcString.padLeft( str, chr, wid )
    local n = wid - string.len( str )
    while( n > 0 ) do
        str = chr .. str
        n = n - 1
    end
    return str
end



--[[
        Convenience function for getting the n-th character of a string.
--]]
function RcString.getChar( s, index )
    return string.sub( s, index, index )
end



--[[
        Convenience function for getting the first character of a string.
--]]    
function RcString.getFirstChar( s )
    return string.sub( s, 1, 1 ) -- bombs if s nil or not string.
end
RcString.firstChar = RcString.getFirstChar


--[[
        Convenience function for getting the last character of a string.
--]]    
function RcString.lastChar( s )
    local len = string.len( s )
    return string.sub( s, len, len )
end
RcString.getLastChar = RcString.lastChar



--[[
        Synopsis:       Compare two strings.

        Returns:        0 if same, else difference position.
--]]
function RcString.compare( s1, s2 )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    if len1 > len2 then
        return len2
    elseif len2 > len1 then
        return len1
    end
    local c1, c2
    for i=1, len1, 1 do
        c1 = RcString.getChar( s1, i )
        c2 = RcString.getChar( s2, i )
        if c1 ~= c2 then
            return i
        end
    end
    return 0
end



--[[
        Synopsis:           Get the difference between two strings.
        
        Notes:              - used to see the difference between two strings.
        
        Returns:            diff-len, s1-remainder, s2-remainder.
--]]        
function RcString.getDiff( s1, s2 )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    local compLen
    local diffLen = len1 - len2
    if diffLen > 0 then
        compLen = len2
    else
        compLen = len1
    end
    local c1, c2, i
    i = 1
    while i <= compLen do
        c1 = RcString.getChar( s1, i )
        c2 = RcString.getChar( s2, i )
        if c1 ~= c2 then
            return diffLen, string.sub( s1, i ), string.sub( s2, i )
        end
        i = i + 1
    end
    if diffLen > 0 then
        return diffLen, string.sub( s1, i ), nil
    elseif diffLen < 0 then
        return diffLen, nil, string.sub( s2, i )
    else
        return 0, nil, nil
    end
        
end
        


--[[
        Synopsis:       Compare two strings.

        Returns:        nil if same, else array of difference points.
--]]
function RcString.compareAll( s1, s2, count )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    if len1 > len2 then
        return { len2 }
    elseif len2 > len1 then
        return { len1 }
    end
    local c1, c2
    local diffs = {}
    for i=1, len1, 1 do
        c1 = RcString.getChar( s1, i )
        c2 = RcString.getChar( s2, i )
        if c1 ~= c2 then
            diffs[#diffs + 1] = i
        end
    end
    if #diffs > 0 then
        return diffs
    else
        return nil
    end
end



--[[
        Synopsis:       Extra a number from the front of a string.

        Notes:          Returns the next parse position.

        Warning:        *** Does NOT check incoming string or parse position.
--]]
function RcString.getNonNegativeNumber( s )
    local pos1, pos2 = string.find( s, "%d+", 1 )
    if pos1 ~= nil and pos1 == 1 then
        return tonumber( string.sub( s, pos1, pos2 ) ), pos2 + 1
    else
        return nil, -1
    end
end



--[[
    *** BEWARE: NOT a boolean function.

    Plain text prefix test - returns position where part after starts,
    or zero if its not present. Thus, a simple comparison works:
    local pos = startsWith( s, t )
    if pos > 0 then
        local ending = string.sub( s, pos )
    end
--]]
function RcString.startsWith( s, t ) 
    local start, stop = string.find( s, t, 1, true )
    if start ~= nil and start == 1 then
        return stop + 1
    else
        return 0
    end
end



--[[
        Synopsis:           Determine if one string starts with another.
        
        Notes:              Avoids the problem of using the nil returned by string.find in a context that does not like it.
        
        Returns:            
--]]        
function RcString.isStartingWith( s, t )
    return RcString.startsWith( s, t ) > 0
end



--[[
        Synopsis:   Makes a word presumed to be singular into its plural form.
        
        Notes:      Call is-plural and trim beforehand if necessary.
--]]
function RcString.makePlural(word)

    RcString.initPlurals() -- if not already.

	local lowerword = string.lower(word)
	local wordlen = string.len(word)

	-- test to see if already plural, if so, return word as is
	-- if TestIsPlural(word) == true then return word end - more efficient to not test unless
	-- unless there is a question about it. if it already is plural, then it will get double pluralized

	-- test to see too short
	if wordlen <=2 then return word end  -- not a word that can be pluralized

	-- test to see if it is in special dictionary
	--check special dictionary, return word if found but keep first letter from original
	local dicvalue  = pluralLookup [lowerword]
	if dicvalue ~= nil then
		dicvaluelen = #dicvalue
		return string.sub(word,1,1) .. string.sub(dicvalue,2,dicvaluelen)
	end

	-- if the word ends in a consonant plus -y, change the -y into, ies or es
	pw = string.sub(lowerword, wordlen-1,wordlen)
	if	pw=="by" or pw=="cy" or pw=="dy" or pw=="fy" or pw=="gy" or pw=="hy" or
		pw=="jy" or pw=="ky" or pw=="ly" or pw=="my" or pw=="ny" or pw=="py" or
		pw=="qy" or pw=="ry" or pw=="sy" or pw=="ty" or
		pw=="vy" or pw=="wy" or pw=="xy" or pw=="zy" then

		return string.sub(word,1,wordlen -1) .. "ies"
	
	-- for words that end in -is, change the -is to -es to make the plural form.
	elseif pw=="is" then return string.sub(word,1,wordlen -2) .. "es"

		-- for words that end in a "hissing" sound (s,z,x,ch,sh), add an -es to form the plural.
	elseif pw=="ch" or pw=="sh" then return word .. "es"

	else
		pw=string.sub(pw,2,1)
		if pw=="s" or pw=="z" or pw=="x" then
			return word .. "es"
		else
			return word .. "s"
		end
	end
	
end -- function to return plural form of singular



--[[
        Synopsis:       Make a plural form singular.
        
        Notes:          If unsure, call is-plural before-hand, and trim if necessary.
--]]
function RcString.makeSingular(word)

    RcString.initPlurals() -- if not already.
    
	local wordlen = string.len(word)

	--not a word that can be made singular if only two letters!
	if wordlen <= 2 then return word end
	
	--check special dictionary, return word if found but keep first letter from original
	local lowerword = string.lower(word)
	local dicvalue  = singularLookup [lowerword]
	if dicvalue ~= nil then
		dicvaluelen = #dicvalue
		return string.sub(word,1,1) .. string.sub(dicvalue,2,dicvaluelen)
	end

	-- if it is singular form in the special dictionary, then you can't remove plural
	if pluralLookup [lowerword] ~= nil then return word end
	
	-- if at this point it doesn't end in and "s", it is probably not plural
	if string.sub(lowerword,wordlen,wordlen) ~= "s" then return word end

	--If the word ends in a consonant plus -y, change the -y into -ie and add an -s to form the plural – so reverse engineer it to get the singular
	if wordlen >=4 then
		pw = string.sub(lowerword, wordlen-3,wordlen)
		if	pw=="bies" or pw=="cies" or pw=="dies" or pw=="fies" or pw=="gies" or pw=="hies" or
			pw=="jies" or pw=="kies" or pw=="lies" or pw=="mies" or pw=="nies" or
			pw=="pies" or pw=="qies" or pw=="ries" or pw=="sies" or pw=="ties" or
			pw=="vies" or pw=="wies" or pw=="xies" or pw=="zies" then
			return string.sub(word,1,wordlen -3) .. "y"
		--for words that end in a "hissing" sound (s,z,x,ch,sh), add an -es to form the plural.
		elseif pw=="ches" or pw=="shes" then
			return string.sub(word,1,wordlen -2)
		end
	end

	if wordlen >=3 then
		pw = string.sub(lowerword, wordlen-2,wordlen)
		if	pw=="ses" or pw=="zes" or pw=="xes" then
			-- some false positive here, need to add those to dictionary as found
			return string.sub(word,1,wordlen -2)
		elseif string.sub(pw,2,3)=="es" then
			return string.sub(word,1,wordlen -2) .. "is"
		end
	end

	-- at this point, just remove the "s"
	return string.sub(word,1,wordlen-1)

end -- function to return a singular form of plural word



--[[
        Synopsis:       Tests if a word is singular or plural.
        
        Notes:          trim beforehand if necessary.
        
        Returns:        true iff plural.
--]]
function RcString.isPlural(word)

    RcString.initPlurals() -- if not already.
    
	local lowerword = string.lower(word)
	local wordlen = #word

	--not a word that can be made singular if only two letters!
	if wordlen <= 2 then return false

	--check special dictionary to see if plural form exists
	elseif singularLookup [lowerword] ~= nil then
		return true  -- it's definitely already a plural


	elseif wordlen >= 3 then
		-- 1. If the word ends in a consonant plus -y, change the -y into -ie and add 			an -s to form the plural 
		pw = string.sub(lowerword, wordlen-3,wordlen)
		if	pw=="bies" or pw=="dies" or pw=="fies" or pw=="gies" or pw=="hies" or
			pw=="jies" or pw=="kies" or pw=="lies" or pw=="mies" or pw=="nies" or
			pw=="pies" or pw=="qies" or pw=="ries" or pw=="sies" or pw=="ties" or
			pw=="vies" or pw=="wies" or pw=="xies" or pw=="zies" or pw=="ches" or
			pw=="shes" then
			
			return true -- it's already a plural (reasonably accurate)
		end
		pw = string.sub(lowerword, wordlen-2,wordlen)
		if	pw=="ses" or pw=="zes" or pw=="xes" then
			
			return true -- it's already a plural (reasonably accurate)
		end

		pw = string.sub(lowerword, wordlen-1,wordlen)
		if	pw=="es" then
			
			return true -- it's already a plural (reasonably accurate)
		end
	end

	--not a plural word (after looking into special dictionary if it doesn't end in s
	if string.sub(lowerword, wordlen,wordlen) ~= "s" then
		return false

	else
		return true

	end -- group of elseifs
		
end -- function to test to see if word is plural



--[[
        Synopsis:       Initializes dictionaries for singular/plural support.
        
        Notes:          May be called in plugin-init, or not - will be called on first demand.
--]]        
function RcString.initPlurals()

    if singularLookup ~= nil then return end

--	Here are known words that have funky plural/singular conversions, they should
-- 	be checked first in all cases before the other rules are checked.  Probably wise to
--	set these as a global variable in the "init" code of the plug-in to keep from 
--	initializing everytime.

	pluralLookup = {
		afterlife	= "afterlives",
		alga		= "algae",
		alumna		= "alumnae",
		alumnus		= "alumni",
		analysis	= "analyses",
		antenna		= "antennae",
		appendix	= "appendices",
		axis		= "axes",
		bacillus	= "bacilli",
		basis		= "bases",
		bedouin		= "bedouin",
		cactus		= "cacti",
		calf		= "calves",
		cherub		= "cherubim",
		child		= "children",
		christmas	= "christmases",
		cod			= "cod",
		cookie		= "cookies",
		criterion	= "criteria",
		curriculum	= "curricula",
		dance		= "dances",
		datum		= "data",
		deer		= "deer",
		diagnosis	= "diagnoses",
		die			= "dice",
		dormouse	= "dormice",
		elf			= "elves",
		elk			= "elk",
		erratum		= "errata",
		esophagus	= "esophagi",
		fauna		= "faunae",
		fish		= "fish",
		flora		= "florae",
		focus		= "foci",
		foot		= "feet",
		formula		= "formulae",
		fundus		= "fundi",
		fungus		= "fungi",
		genie		= "genii",
		genus		= "genera",
		goose		= "geese",
		grouse		= "grouse",
		hake		= "hake",
		half		= "halves",
		headquarters= "headquarters",
		hippo		= "hippos",
		hippopotamus= "hippopotami",
		hoof		= "hooves",
		horse		= "horses",
		housewife	= "housewives",
		hypothesis	= "hypotheses",
		index		= "indices",
		jackknife	= "jackknives",
		knife		= "knives",
		labium		= "labia",
		larva		= "larvae",
		leaf		= "leaves",
		life		= "lives",
		loaf		= "loaves",
		louse		= "lice",
		magus		= "magi",
		man			= "men",
		memorandum	= "memoranda",
		midwife		= "midwives",
		millennium	= "millennia",
		miscellaneous= "miscellaneous",
		moose		= "moose",
		mouse		= "mice",
		nebula		= "nebulae",
		neurosis	= "neuroses",
		nova		= "novas",
		nucleus		= "nuclei",
		oesophagus	= "oesophagi",
		offspring	= "offspring",
		ovum		= "ova",
		ox			= "oxen",
		papyrus		= "papyri",
		passerby	= "passersby",
		penknife	= "penknives",
		person		= "people",
		phenomenon	= "phenomena",
		placenta	= "placentae",
		pocketknife	= "pocketknives",
		pupa		= "pupae",
		radius		= "radii",
		reindeer	= "reindeer",
		retina		= "retinae",
		rhinoceros	= "rhinoceros",
		roe			= "roe",
		salmon		= "salmon",
		scarf		= "scarves",
		self		= "selves",
		seraph		= "seraphim",
		series		= "series",
		sheaf		= "sheaves",
		sheep		= "sheep",
		shelf		= "shelves",
		species		= "species",
		spectrum	= "spectra",
		stimulus	= "stimuli",
		stratum		= "strata",
		supernova	= "supernovas",
		swine		= "swine",
		synopsis	= "synopses",
		terminus	= "termini",
		thesaurus	= "thesauri",
		thesis		= "theses",
		thief		= "thieves",
		trout		= "trout",
		vulva		= "vulvae",
		wife		= "wives",
		wildebeest	= "wildebeest",
		wolf		= "wolves",
		woman		= "women",
		yen			= "yen",
	}

	-- this creates a reverse lookup table of the special dictionary by reversing the variables
	-- names with the string result

	singularLookup = {}
	for k, v in pairs (pluralLookup) do
		singularLookup [v] = k
	end
	
end -- of dictionary initialization function



--[[
        For UI - A nice function.
--]]
function RcString.plural( count, singular, useNumberForSingular )
	local countStr
	local suffix = singular
	if count then
	    if count == 1 then
			if useNumberForSingular then
				countStr = '1 '
			else
		        local firstChar = RcString.getFirstChar( singular )
		        if firstChar >= 'A' and firstChar <= 'Z' then
		            countStr = "One "
		        else
		            countStr = "one "
		        end
			end
	    else
	        countStr = RcLua.toString( count ) .. " "
			suffix = RcString.makePlural( singular ) -- correct 99.9% of the time.
	    end
	else
		countStr = 'nil '
	end
	return countStr .. suffix
end



--[[
        Call to check whether a value is a non-nil, non-empty string.
        Avoids checking both aspects, or getting a "expected string, got nil" error.
        
        If type is questionable as well, then use 'really-is' instead.
--]]
--[=[ *** save for posterity
function RcString.____is ntAnymore( s )
                if s and (string.len( s ) > 0) then -- I think this bombs if s is not a string type.
                    return true
                else
                    return false
                end
end--]=]



--[[
        Call to check whether a value is a non-nil, non-empty string.
        Avoids checking both aspects, or getting a "expected string, got nil" error.
        
        This is more robust than the previous rendition of "is" was - asserts a more informative error in calling context,
        instead of here.
--]]
function RcString.is( s )
    if s ~= nil then
        if type( s ) == 'string' then
            if s:len() > 0 then
                return true
            else
                return false
            end
        else -- data-type error
            error( LOC( "$$$/X=RcString.is argument should be string, not ^1", type( s ) ), 2 ) -- 2 => assert error in calling context instead of this one.
        end
    else
        return false
    end
end



--[[
        Call to check whether a value is a non-nil, non-empty string.
        Avoids checking both aspects, or getting a "expected string, got nil" error.
        
        Although this weathers the case when s is a table (or number?), it may misleadingly
        allow program to continue in case of data-type error.
--]]
function RcString.reallyIs( s )
    if s and (type( s ) == 'string') and ( s ~= '' ) then
        return true
    else
        return false
    end
end



--[[
        Like the Flash/Java versions I have created,
        this is used primarily for converting backslashed
        paths or sub-paths to forward slash format.
--]]
function RcString.replaceBackSlashesWithForwardSlashes( _path )
    if _path ~= nil then
        local path = string.gsub( _path, "\\", "/" )
        return path
    else
        return ""
    end
end



--[[
        Returns iterator over lines in a string
        Assumes term seq is '\n', and so wont work on Windows file strings.
--]]
function RcString.lines( s )
    local pos = 1
    return function()
        local starts, ends = string.find( s, '\n', pos, true )
        if starts then
            local retStr = string.sub( s, pos, starts - 1 )
            pos = ends + 1
            return retStr
        else
            return nil
        end
    end
end



--[[
        Synopsis:           Breaks a string into tokens by getting rid of the whitespace between them.
        
        Notes:              Does similar thing as "split", except delimiter is any whitespace, not just true spaces.
--]]
function RcString.tokenize( s, nTokensMax )
    local tokens = {}
    local parsePos = 1
    local starts, ends = string.find( s, '%s', parsePos, false ) -- respect magic chars.
    local substring = nil
    while starts do
        if nTokensMax ~= nil and #tokens == (nTokensMax - 1) then -- dont pass ntokens-max = 0.
            substring = LrStringUtils.trimWhitespace( string.sub( s, parsePos ) )
        else
            substring = LrStringUtils.trimWhitespace( string.sub( s, parsePos, starts ) )
        end
        if string.len( substring ) > 0 then
            tokens[#tokens + 1] = substring
        -- else - ignore
        end
        if nTokensMax ~= nil and #tokens == nTokensMax then
            break
        else
            parsePos = ends + 1
            starts, ends = string.find( s, '%s', parsePos, false ) -- respect magic chars.
        end
    end
    if #tokens < nTokensMax then
        tokens[#tokens + 1] = LrStringUtils.trimWhitespace( s:sub( parsePos ) )
    end
    return tokens
end



--[[
        Synopsis:       Get filename sans extension from path.
        
        Notes:          *** this failed when I tried these ops in reverse, i.e. removing extension of leaf-name.
--]]
function RcString.getBaseName( fp )        
    return LrPathUtils.leafName( LrPathUtils.removeExtension( fp ) )
end



return RcString