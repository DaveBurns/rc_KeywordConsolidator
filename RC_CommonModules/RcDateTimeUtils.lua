--[[================================================================================

Filename:           RcDateTimeUtils.lua

Synopsis:           Provides additional date-time support in the form of utility functions.

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


assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )


local LrDate = RcModuleLoader.import( 'LrDate' )
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' ) -- *** Used for floating point -> integer conversion.



local RcString = RcModuleLoader.loadRcModule( 'RcString' )


local leapMonthSecs = nil
local normalMonthSecs = nil
local leapYearSecs = 0
local normalYearSecs = 0




local RcDateTimeUtils = {}




--[[
        Synopsis:       Convert a number of seconds to hours:mm:ss format.
        
        Note:           - Takes a number, not a string.
                        - Uses lr-path-utils-remove-extension (floor) instead of lr-string-utils-number-to-string (may round up).
                        
        Reminder:       Very small time differences wreak havoc - round to zero for sanity.
--]]
function RcDateTimeUtils.formatTimeDiff( secs )
    assert( type( secs ) == 'number', "Bad argument type" )
    local sign
    if secs < 0 then
        secs = 0 - secs
        sign = '-'
    else
        sign = ''
    end
    if secs < 1 then
        secs = 0 -- nearest second.
    end
    local hourString = LrPathUtils.removeExtension( tostring( secs / 3600 ) ) -- truncated integer string
    local hours = tonumber( hourString ) -- back to number.
    local minuteString = LrPathUtils.removeExtension( tostring( ( secs - ( hours * 3600 ) ) / 60 ) )
    local minutes = tonumber( minuteString )
    local secondString = LrPathUtils.removeExtension( tostring( secs - ( hours * 3600 ) - ( minutes * 60 ) ) )
    -- local seconds = tonumber( secondString ) -- dont need seconds as number.
    -- no reason to pad hour string - calling context can pad the whole thing upon return if desired.
    minuteString = RcString.padLeft( minuteString, "0", 2 )
    secondString = RcString.padLeft( secondString, "0", 2 )
    if hours > 0 then
        return LOC( "$$$/X=^1^2:^3:^4", sign, hourString, minuteString, secondString )
    elseif minutes > 0 then
        return LOC( "$$$/X=^1^2:^3", sign, minuteString, secondString )
    else
        return LOC( "$$$/X=^1^2", sign, secondString )
    end
end
    
    
    
--[[
		Synopsis:			Parse date in MM-DD-YY format.

		Motivation for creation:			Originally created to support windows directory entry parsing.
							###4 the unix version is in the ftp module for now (thats the only place its used).

		Notes:				Error handling is a bit weak. ###2

		Returns:			4-digit year, month(1-12), day(1-31) numbers.
							else error message.

		More Notes:			Will not work anymore after 1-1-2070.
--]]
function RcDateTimeUtils.parseMmDdYyDate( dateStr )
	local chr = RcString.getChar( dateStr, 3 )
	local monthStr, dayStr, yearStr
	if chr == '-' then
		monthStr = string.sub( dateStr, 1, 2 )
	else
		return "no dash for month in mm-dd-yy date string"
	end
	chr = RcString.getChar( dateStr, 6 )
	if chr == '-' then
		dayStr = string.sub( dateStr, 4, 5 )
		yearStr = string.sub( dateStr, 7, 8 )
	else
		return "no dash for day in mm-dd-yy date string"
	end
	local year = tonumber( yearStr )		
	local month = tonumber( monthStr )		
	local day = tonumber( dayStr )		
	if year >= 70 then -- last century
		year = 1900 + year
	else
		year = 2000 + year
	end
	return year, month, day
end



--[[
		Synopsis:			Parse time in HH:MM{AM/PM} format.

		Motivation for creation:			Originally created to support windows directory entry parsing.
							###4 ought to have a unix one too.

		Notes:				Error handling is a bit weak. ###2

		Returns:			hour (0-23), minute (0-59), 
							else error message.

		More Notes:			Will not work after 1-1-2070.
--]]
function RcDateTimeUtils.parseHhMmAmPmTime( timeStr )
	local chr = RcString.getChar( timeStr, 3 )
	local hourStr, minuteStr
	if chr == ':' then
		hourStr = string.sub( timeStr, 1, 2 )
		minuteStr = string.sub( timeStr, 4, 5 )
	else
		return "no colon for hour/minute in hh:mm{am/pm} string: " .. timeStr
	end
	local amPmStr = string.sub( timeStr, 6, 7 )
	local hour = tonumber( hourStr )		
	local minute = tonumber( minuteStr )		
	local offset
	if amPmStr == 'AM' then
		offset = 0
	elseif amPmStr == 'PM' then
		offset = 12
	else
		return "expected time in 12-hour format: " .. timeStr
	end
	return hour + offset, minute
end



--- Format time in UTC standard notation, with ms.
--
--  @param time from arbitrary time zone.
--  @param offset seconds from utc.
--  @param dls flag for dls adjustment.
--
function RcDateTimeUtils.timeToUtcFormat( time, offset, dls )

    local dlsAdj = 0
    local _offset, dlsFlg = LrDate.timeZone()
    
    if dls and dlsFlg then
        dlsAdj = 3600
    end
    
    if offset == nil then
        offset = _offset
    end
    
    time = time + offset + dlsAdj
    local fmt = LrDate.timeToW3CDate( time, 0 ):sub( 1, -7 ) -- offset already folded in.
    if fmt:find( "\\." ) then
        -- cool
    else
        local subs = time - math.floor( time )
        local ms = subs * 1000
        local msFmt = string.format( "%03u", ms )
        fmt = fmt .. "." .. msFmt
    end
    fmt = fmt .. 'Z' -- "Z" indicates UTC time when no offset present.
    return fmt

end






--[==[      *** SAVE FOR FUTURE REFERENCE: this stuff works, but lr-date has equivalent functions.
            
            function RcDateTimeUtils.getYearSecs( year )
                local secs = 0
                year = year - 1 -- dont count this year's seconds.
                while ( year >= 2001 ) do
                    if RcDateTimeUtils.isLeapYear( year ) then
                        secs = secs + leapYearSecs
                    else
                        secs = secs + normalYearSecs
                    end
                    year = year - 1
                end
                return secs
            end
            --[[
                    Works for years 2001 to 2099.
            --]]
            function RcDateTimeUtils.isLeapYear( year )
                return math.mod( year, 4 ) == 0
            end
            --[[
                    - these must be confined as follows or it will blow up:
                    year:   2001+
                    month:  1-12
                    day:    1-31
                    - these can sometimes be a bit bigger (or even a tiny bit smaller) if some adjustment has been made but not normalized:
                    hour:   0-23
                    minute: 0-59
                    second: 0-59
            --]]
            function RcDateTimeUtils.getTime( year, month, day, hour, minute, second )
                if leapMonthSecs == nil then
                    leapMonthSecs = {}
                    leapMonthSecs[1] = 0
                    leapMonthSecs[2] = 31 * 86400
                    leapMonthSecs[3] = leapMonthSecs[2] + (29 * 86400)
                    leapMonthSecs[4] = leapMonthSecs[3] + (31 * 86400)
                    leapMonthSecs[5] = leapMonthSecs[4] + (30 * 86400)
                    leapMonthSecs[6] = leapMonthSecs[5] + (31 * 86400)
                    leapMonthSecs[7] = leapMonthSecs[6] + (30 * 86400)
                    leapMonthSecs[8] = leapMonthSecs[7] + (31 * 86400)
                    leapMonthSecs[9] = leapMonthSecs[8] + (31 * 86400)
                    leapMonthSecs[10] = leapMonthSecs[9] + (30 * 86400)
                    leapMonthSecs[11] = leapMonthSecs[10] + (31 * 86400)
                    leapMonthSecs[12] = leapMonthSecs[11] + (30 * 86400)
                    normalMonthSecs = {}
                    normalMonthSecs[1] = 0
                    normalMonthSecs[2] = 31 * 86400
                    normalMonthSecs[3] = normalMonthSecs[2] + (28 * 86400)
                    normalMonthSecs[4] = normalMonthSecs[3] + (31 * 86400)
                    normalMonthSecs[5] = normalMonthSecs[4] + (30 * 86400)
                    normalMonthSecs[6] = normalMonthSecs[5] + (31 * 86400)
                    normalMonthSecs[7] = normalMonthSecs[6] + (30 * 86400)
                    normalMonthSecs[8] = normalMonthSecs[7] + (31 * 86400)
                    normalMonthSecs[9] = normalMonthSecs[8] + (31 * 86400)
                    normalMonthSecs[10] = normalMonthSecs[9] + (30 * 86400)
                    normalMonthSecs[11] = normalMonthSecs[10] + (31 * 86400)
                    normalMonthSecs[12] = normalMonthSecs[11] + (30 * 86400)
                    leapYearSecs = leapMonthSecs[12] + (31 * 86400) -- add in december
                    normalYearSecs = normalMonthSecs[12] + (31 * 86400) -- add in december
                end
                local secs = RcDateTimeUtils.getYearSecs( year)
                if RcDateTimeUtils.isLeapYear( year ) then
                    secs = secs + leapMonthSecs[ month ]
                else
                    secs = secs + normalMonthSecs[ month ]
                end
                secs = secs + ( ( day - 1 ) * 86400 )
                secs = secs + hour * 3600
                secs = secs + minute * 60
                secs = secs + second
                assert (secs == LrDate.timeFromComponents( year, month, day, hour, minute, second, 0 ), "Lightroom time does not agree." ) -- This function returns
                    -- exact same value as Lightrooms.
                return secs
            end
--]==]



return RcDateTimeUtils
