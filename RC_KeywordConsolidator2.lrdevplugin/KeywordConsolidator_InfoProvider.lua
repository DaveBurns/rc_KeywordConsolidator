--[[----------------------------------------------------------------------------

Filename:		KwCInfoProvider.lua

Synopsis:		Export service provider description for Lightroom KwC export plugin.

------------------------------------------------------------------------------------
Origin:         Please do not delete these origin lines, unless this file has been
                edited to the point where nothing original remains... - thanks, Rob.

    		    The contents of this file is based on code originally written by
                Rob Cole, robcole.com, 2008-09-02.

                Rob Cole is a software developer available for hire.
                For details please visit www.robcole.com
------------------------------------------------------------------------------------

Edit History:   2010-06-20: Enhanced by Rob Cole...

--------------------------------------------------------------------------------
For Hire:       I am. - Please contact me at http://www.robcole.com.
For Hire:       I am. - Please contact me at http://www.robcole.com.
For Hire:       I am. - Please contact me at http://www.robcole.com.
--------------------------------------------------------------------------------

To Do:          - See ### & ??? spots.

------------------------------------------------------------------------------]]



local LrPathUtils = import 'LrPathUtils'


-- Lightroom SDK - rc-module-loader not warranted here, since all lightroom modules are the real deal - not emulations.
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrApplication = import 'LrApplication'
local LrPrefs = import 'LrPrefs'
local LrDialogs = import 'LrDialogs'
local LrSystemInfo = import 'LrSystemInfo'

-- My Modules
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcGui = RcModuleLoader.loadRcModule( 'RcGui' )


local KwC = RcModuleLoader.loadModule( 'KeywordConsolidator_ServiceProvider' )



-- Define module.
local Info = {}



function Info.sectionsForBottomOfInfoDialog( f, props )

    -- math.randomseed( LrDate.currentTime() ) -- assures unique IDs are generated.

    local prefs = LrPrefs.prefsForPlugin()
    
    if prefs.enableAutoInit == nil then
        props.enableAutoInit = false
    else
        props.enableAutoInit = prefs.enableAutoInit
    end
    if prefs.newKeywordPrompt == nil then
        props.newKeywordPrompt = true
    else
        props.newKeywordPrompt = prefs.newKeywordPrompt
    end
    if prefs.duplicatesOnly == nil then
        props.duplicatesOnly = false
    else
        props.duplicatesOnly = prefs.duplicatesOnly
    end
    if prefs.promptForIgnore == nil then
        props.promptForIgnore = true
    else
        props.promptForIgnore = prefs.promptForIgnore
    end
    if prefs.promptForIgnorePaths == nil then
        props.promptForIgnorePaths = false
    else
        props.promptForIgnorePaths = prefs.promptForIgnorePaths
    end
    if prefs.similarities == nil then
        props.similarities = true
    else
        props.similarities = prefs.similarities
    end
    if prefs.plurals == nil then
        props.plurals = true
    else
        props.plurals = prefs.plurals
    end
    if prefs.ignoreSynonyms == nil then
        props.ignoreSynonyms = false
    else
        props.ignoreSynonyms = prefs.ignoreSynonyms
    end
    if prefs.maxKeywords == nil then
        props.maxKeywords = 50
    else
        props.maxKeywords = prefs.maxKeywords
    end
    if prefs.lineHeight == nil then
        local dispInfo =  LrSystemInfo.displayInfo()
        local displayHeight = 768
        for i = 1, #dispInfo do
            if dispInfo[i].height > displayHeight then
                displayHeight = dispInfo[i].height
            end
        end
        local macOfs = 0
        if MAC_ENV then
            macOfs = 5
        end
        if displayHeight <= 800 then
            lineHeight = 20 - macOfs
        elseif displayHeight < 1000 then
            lineHeight = 25 - macOfs
        elseif displayHeight < 1200 then
            lineHeight = 30 - macOfs
        else
            lineHeight = 35 - macOfs
        end
        props.lineHeight = lineHeight
    else
        props.lineHeight = prefs.lineHeight
    end
    if prefs.smallFont == nil then
        props.smallFont = false
    else
        props.smallFont = prefs.smallFont
    end
    if prefs.ctrlTabAhk == nil then
        props.ctrlTabAhk = false
    else
        props.ctrlTabAhk = prefs.ctrlTabAhk
    end
    
    if not RcString.is( prefs.logFilePath ) then -- log file "encouraged" for keyword consolidator
        -- you can run without one, but it'll be back next time you re-enter the plugin manager.
        props.logFilePath = _PLUGIN.id .. ".LogFile.txt"
    else
        props.logFilePath = prefs.logFilePath
    end
    if prefs.logVerbose == nil then
        props.logVerbose = false
    else
        props.logVerbose = prefs.logVerbose
    end
    if prefs.logOverwrite == nil then
        props.logOverwrite = true
    else
        props.logOverwrite = prefs.logOverwrite
    end
    if prefs.testMode == nil then
        props.testMode = false
        prefs.testMode = false
    else
        props.testMode = prefs.testMode
    end
    
    -- this really should be done for all props ###1
    local function chgHdlr( one, two, name, value )
        --RcUtils.showInfo( ( tostring( name or "no name" ) ) .. ": " .. ( tostring( value or 'false/nil' ) ) )
        prefs.testMode = value
    end
    props:removeObserver( 'testMode', KwC )
    props:addObserver( 'testMode', KwC, chgHdlr )
    
    return {
        {
    		title = LOC "$$$/KwC/ExportDialog/KwCInfo=Keyword Consolidator Shared Settings",
    		
    		synopsis = LOC "$$$/KwC/ExportDialog/InfoSynopsis=KwC log settings and directories...",
    
      		bind_to_object = props,
      		
      		spacing = 5,
      		
            f:row { -- autoupdate runs in a different environment than plugin proper, so module level local variables are not accessible.
        		f:checkbox {
        			title = 'Enable Auto-Initialization Upon Startup',
        			value = LrView.bind( 'enableAutoInit' ),
        		},
        	},
            f:spacer{ height = 3 },        
            f:separator { fill_horizontal = 1 },
            f:spacer{ height = 3 },        
            
            f:row {
        		f:static_text {
        			title = 'Log File ',
        			width = LrView.share('label_width'),
        		},
        
        		f:edit_field {
        			width_in_chars = 50,
        			height_in_lines = 1,
        			fill_horizontal = 1,
        			value = LrView.bind( 'logFilePath' )
        		},
            },
            f:row {
        		f:checkbox {
        		    title = "Test Mode",
        			value = LrView.bind( 'testMode' ),
        			width = LrView.share( 'label_width' ),
        		},
        		f:checkbox {
        		    title = "Log Verbose (Debug)",
        			value = LrView.bind( 'logVerbose' ),
        		},
        		f:checkbox {
        		    title = "Log Overwrite",
        			value = LrView.bind( 'logOverwrite' ),
        		},
            },
            f:spacer{ height = 3 },        
            f:separator { fill_horizontal = 1 },
            f:spacer{ height = 3 },        
            f:row {
                f:push_button {
                    title = 'Reset Warning Dialogs',
                    enabled = true,
                    tooltip = 'Re-enables all dialog boxes to show (just those presented by KwC) that had previously been marked "Do Not Show".',
                    action = function( button )
                        LrDialogs.resetDoNotShowFlag()
                        RcUtils.showInfo( "Warning dialogs have been reset." )
                    end, 
                },
        		f:push_button {
        			title = 'Initialize Keyword Data',
        			action = function( button )
        			    KwC.initStart() -- start if not already running.
        			end,
        		},
            },
                    
        },
        {
    		title = LOC "$$$/KwC/ExportDialog/KwCInfo=Keyword Consolidation Settings",
    		
    		synopsis = LOC "$$$/KwC/ExportDialog/InfoSynopsis=KwC defining similarities...",
    
      		bind_to_object = props,
      		
      		spacing = 5,
      		
        	f:row {
        		f:checkbox {
        			title = 'Duplicates Only',
        			-- width = LrView.share( 'cb_col_1' ),
        			value = LrView.bind( 'duplicatesOnly' ),
        			tooltip = 'If checked, similarities are ignored. If un-checked, consolidation of similarities as well as duplicates.',
        		},
        		f:checkbox {
        			title = 'Similarities',
        			value = LrView.bind( 'similarities' ),
        			enabled = LrBinding.negativeOfKey( 'duplicatesOnly' ),
        			tooltip = 'If checked, similarities like substring will be included for consolidation consideration.',
        		},
        		f:checkbox {
        			title = 'Plurals',
        			value = LrView.bind( 'plurals' ),
        			enabled = LrBinding.negativeOfKey( 'duplicatesOnly' ),
        			tooltip = 'If checked, plurals will be included for consolidation consideration.',
        		},
        		f:checkbox {
        			title = 'Synonyms',
        			value = LrBinding.negativeOfKey( 'ignoreSynonyms' ),
        			tooltip = 'If checked, synonyms will be included for consolidation consideration.',
        		},
        	},
            f:row { -- autoupdate runs in a different environment than plugin proper, so module level local variables are not accessible.
        		f:checkbox {
        			title = 'Prompt For Ignore Names',
        			-- width = LrView.share( 'cb_col_1' ),
        			value = LrView.bind( 'promptForIgnore' ),
        			enabled = LrBinding.negativeOfKey( 'duplicatesOnly' ),
        			tooltip = 'If checked, you will be prompted to ignore name similarities temporarily or permanently. If un-checked, everything not already being ignored will be offered for consolidation.',
        		},
        		f:checkbox {
        			title = 'Prompt For Ignore Paths',
        			-- width = LrView.share( 'cb_col_2' ),
        			value = LrView.bind( 'promptForIgnorePaths' ),
        			tooltip = 'If checked, you will be prompted to path similarities temporarily or permanently. If un-checked, everything not already being ignored will be offered for consolidation.',
        		},
                f:checkbox {
                    title = 'Prompt before creating new keywords',
                    value = LrView.bind( 'newKeywordPrompt' ),
                },
        	},
            f:spacer{ height = 3 },        
            f:separator { fill_horizontal = 1 },
            f:spacer{ height = 3 },        
            f:row {
        		f:push_button {
        			title = 'Remove Parents',
        			tooltip = 'Remove assignments from parent keywords, leaving only leaf descendent assigned.',
        			action = function( button )
        			    KwC.removeParents()
        			end,
        		},
        		f:push_button {
        			title = 'Auto-consolidate Trees',
        			tooltip = 'Reassign keywords from one tree, to equivalent keywords in another tree: 0-selected => whole catalog; 1-selected => whole filmstrip; multiple-selected => consolidate amongst those selected.',
        			action = function( button )
        			    KwC.autoConsolidateTrees()
        			end,
        		},
        		f:push_button {
        			title = 'Reset Ignore Lists',
        			action = function( button )
        			    KwC.resetIgnoreList( props ) -- self wrapped.
        			end,
        		},
            },
    
                    
        },
        {
    		title = LOC "$$$/KwC/ExportDialog/KwCInfo=Keyword List Settings",
    		
    		synopsis = LOC "$$$/KwC/ExportDialog/InfoSynopsis=Keyword list settings...",
    
      		bind_to_object = props,
      		
      		spacing = 5,
      		
            f:row { -- autoupdate runs in a different environment than plugin proper, so module level local variables are not accessible.
        		f:static_text {
        			title = 'Keyword Limit',
        			width = LrView.share( 'label_1' ),
        		},
        		f:edit_field {
        		    min = 1,
        		    max = 9999,
        		    width_in_chars = 5,
        		    precision = 0,
        			value = LrView.bind( 'maxKeywords' ),
        		},
        		f:static_text {
        			title = "You will be warned when a photo has more keywords than this.",
        		},
        	},
            f:row { -- autoupdate runs in a different environment than plugin proper, so module level local variables are not accessible.
        		f:static_text {
        			title = 'Lines In Frame',
        			width = LrView.share( 'label_1' ),
        		},
        		f:edit_field {
        		    min = 5,
        		    max = 100,
        		    width_in_chars = 5,
        		    precision = 0,
        			value = LrView.bind( 'lineHeight' ),
        		},
        		f:static_text {
        			title = "Number of keyword lines displayed - controls frame size.",
        		},
        	},
            f:row { -- autoupdate runs in a different environment than plugin proper, so module level local variables are not accessible.
        		f:checkbox {
        		    title = 'Small Font',
        			value = LrView.bind( 'smallFont' ),
        		},
        		f:static_text {
        			title = "Reduces font size in keyword list pane only.",
        		},
        	},
            f:row { -- autoupdate runs in a different environment than plugin proper, so module level local variables are not accessible.
        		f:checkbox {
        		    title = 'Enable Ctrl-Tab (Auto)HotKey',
        			value = LrView.bind( 'ctrlTabAhk' ),
        		},
        		f:static_text {
        			-- title = "If you have AutoHotKey installed on Windows, or IronAHK\non Mono for Mac, then I recommend enabling this\nso Ctrl-Tab can be used to accept existing keyword entry\n(if only one), so you don't have to keep typing.\n \nReminder: Press Win-X so Lightroom can exit/start again properly.",
        			title = "If you have AutoHotKey installed on Windows,\nthen I recommend enabling this, so Ctrl-Tab can\nbe used to accept an existing keyword entry option\n(if only one), so you don't have to type the rest of it.\n \nReminder: Press Win-X just before or after exiting Lightroom so it\ncan start again properly.\n \nIf you are using Lightroom on a Mac, I recommend getting QuickKeys\nand setting up a 'tab,shift-tab,right-arrow' keystroke sequence\nand use it when entering keywords in the 'Keyword to add' field.\nAnd, if you figure out another way to do it - please let me know!",
        		},
        	},
        },
    }
    
end

function Info.endInfoDialog( props )

    local prefs = LrPrefs.prefsForPlugin()

    prefs.logFilePath = props.logFilePath
    prefs.logVerbose = props.logVerbose
    prefs.logOverwrite = props.logOverwrite
    prefs.testMode = props.testMode
    prefs.enableAutoInit = props.enableAutoInit
    prefs.newKeywordPrompt = props.newKeywordPrompt
    prefs.duplicatesOnly = props.duplicatesOnly
    prefs.similarities = props.similarities
    prefs.plurals = props.plurals
    prefs.ignoreSynonyms = props.ignoreSynonyms
    prefs.promptForIgnore = props.promptForIgnore
    prefs.promptForIgnorePaths = props.promptForIgnorePaths
    prefs.maxKeywords = props.maxKeywords
    prefs.lineHeight = props.lineHeight
    prefs.smallFont = props.smallFont
    prefs.ctrlTabAhk = props.ctrlTabAhk        
end


--============================================================================--

return {
	
	sectionsForTopOfDialog = RcGui.sectionsForTopOfInfoDialog,
	sectionsForBottomOfDialog = Info.sectionsForBottomOfInfoDialog,
	endDialog = Info.endInfoDialog,
	
}
