--[[
        Filename:           RcGui.lua
        
        Synopsis:           Utilities to support building dialog boxes and such.

        Notes:              -
--]]


local RcGui = {}


assert( RcModuleLoader ~= nil, "Global rc-module-loader must be pre-loaded and initialized." )
assert( RcUtils ~= nil, "Global rc-utils must be pre-loaded and initialized." )


local LrFileUtils = RcModuleLoader.import( 'LrFileUtils' )
local LrPathUtils = RcModuleLoader.import( 'LrPathUtils' )
local LrTasks = RcModuleLoader.import( 'LrTasks' )
local LrErrors = RcModuleLoader.import( 'LrErrors' )
local LrDialogs = RcModuleLoader.import( 'LrDialogs' )
local LrView = RcModuleLoader.import( 'LrView' )
local LrBinding = RcModuleLoader.import( 'LrBinding' )
local LrHttp = RcModuleLoader.import( 'LrHttp' )

local RcLua = RcModuleLoader.loadRcModule( 'RcLua' )
local RcString = RcModuleLoader.loadRcModule( 'RcString' )
local RcFileUtils = RcModuleLoader.loadRcModule( 'RcFileUtils' )
local RcTable = RcModuleLoader.loadRcModule( 'RcTable' )



--[[function RcGui.findComboBox( x, visited )
    if visited == nil then visited = {} end

    if type (x) ~= "table" or visited [x] then return nil end
    visited [x] = true
   
    if x._WinClassName == "AgViewWinComboBox" then
        RcUtils.logObject( x, 0 )
        return x
    else
        -- LrDialogs.message( x._WinClassName )
    end
           
    for k, v in pairs (x) do
        local result = RcGui.findComboBox (v, visited)
        if result then return result end
    end
   
    return nil

end--]]



--[[
        Synopsis:           Returns the specified button if found in the dialog box.
        
        Notes:              specified by label, e.g. "OK"
        
        Returns:            button object or nil
--]]        
function RcGui.findButton (x, label, visited)
    if visited == nil then visited = {} end

    if type (x) ~= "table" or visited [x] then return nil end
    visited [x] = true
   
    if x._WinClassName == "AgViewWinPushButton" and x.title == label then
        return x
    else
        -- LrDialogs.message( x._WinClassName )
    end
           
    for k, v in pairs (x) do
        local result = RcGui.findButton (v, label, visited)
        if result then return result end
    end
   
    return nil
 end
 
 
--[[function RcGui.presentModalFlame( args, returnAllButtons )
    assert( args.actionVerb == nil, "Bad frame - shouldn't define action button." )
    assert( args.actionBinding == nil, "Bad binding - shouldn't define action binding." )
    assert( args.otherVerb == nil, "Bad frame - shouldn't define other button." )
	local done = false
    RcGui.findComboBox( args.contents )
  	button = LrDialogs.presentModalDialog( args )
    -- RcGui.findComboBox( args.contents )
    return button
end--]]



--[[
        Synopsis:           Presents a modal dialog without an OK button.
        
        Notes:              Note: Only suitable if when you don't need form elements to be commited upon dismissal.
        
        Returns:            dismissal button
--]]        
function RcGui.presentModalFrame( args, returnAllButtons )
    assert( args.actionBinding == nil, "Bad binding - shouldn't define action binding." )
    assert( args.otherVerb == nil, "Bad frame - shouldn't define other button." )
    args.actionVerb = args.cancelVerb -- reversed in calling context, unfortunately.
    args.cancelVerb = '< exclude >'
	local button
	local done = false
    repeat
    	button = LrDialogs.presentModalDialog( args )
    	if button == 'ok' then
    	    done = true
    	elseif button == 'cancel' then -- "the red X" is still a 'cancel' button.
    	    done = true
    	elseif returnAllButtons then
    	    done = true
        else
             -- not done.
        end
    until done
    return button
end



--[[
        Synopsis:           Prompt user to enter a string via simple dialog box.
        
        Notes:              self-wrapped.
        
        Returns:            string or nil for cancelled.
--]]        
function RcGui.getSimpleTextInput( param )

    local text, msg

    RcUtils.wrap( "get simple text input", false, function( context )
    
        local props = LrBinding.makePropertyTable( context )
        local vf = LrView.osFactory()
    
        local args = {}
        args.title = param.title
        local viewItems = { bind_to_object = props }
        viewItems[#viewItems + 1] =
            vf:row {
                vf:static_text {
                    title = param.subtitle,
                },
            }
        viewItems[#viewItems + 1] =
            vf:row {
                vf:edit_field {
                    value = LrView.bind( 'text' ),
                    fill_horizontal = 1,
                },
            }
        args.contents = vf:view( viewItems )
        local button = LrDialogs.presentModalDialog( args )
        if button == 'ok' then
            text = props.text
        else
            msg = "Canceled"
        end
            
    end )
    
    return text, msg
    
end



--[[
        Synopsis:           Fetch a user selection from a combo-box.
        
        Notes:              self-wrapped.
        
        Returns:            string or nil for cancel
--]]        
function RcGui.getComboBoxSelection( param )

    local text, msg
    
    RcUtils.wrap( "get combo-box selection", false, function( context )
    
        repeat
        
            if RcTable.isEmpty( param.items ) then
                msg = "No items"
                break
            end
    
            local vf = LrView.osFactory()
            local props = LrBinding.makePropertyTable( context )
            
            props.text = param.items[1] -- can be optimized if inadequate.
        
            local args = {}
            args.title = param.title or 'Choose Item'
            local viewItems = { bind_to_object = props }
            viewItems[#viewItems + 1] =
                vf:row {
                    vf:static_text {
                        title = param.subtitle or "Choose an item from the drop-down list",
                    },
                }
            viewItems[#viewItems + 1] =
                vf:row {
                    vf:combo_box {
                        value = LrView.bind( 'text' ),
                        items = param.items,
                    },
                }
            args.contents = vf:view( viewItems )
            local button = LrDialogs.presentModalDialog( args )
            if button == 'ok' then
                text = props.text
            else
                msg = "Canceled"
            end
            
        until true
            
    end )
    
    return text, msg
    
end



--[[
        Synopsis:           Allows user to select a folder by way of the "open file" dialog box.
        
        Notes:              param's are same as run-open-panel, except all are optional:
                            - title
                            - prompt ("OK" button label alternative)
                            - can-create-directories
                            - file-types
                            - initial-directory
        
        Returns:            X - selected folder is written to named property if provided, and anyway, folder selected is returned as path string.
                            Canceled => nil.
--]]        
function RcGui.selectFolder( param, props, name )

    local args = {}
    args.title = param.title or "Choose File"
    args.prompt = param.prompt or "OK"
    args.canChooseFiles = false
    if param.canCreateDirectories == nil then
        args.canCreateDirectories = false
    else
        args.canCreateDirectories = param.canCreateDirectories
    end
    args.canChooseDirectories = true
    args.allowsMultipleSelection = false
    args.initialDirectory = param.initialDirectory or "/" -- I hate defaulting to documents folder - put 'em at da top...

    local folders = LrDialogs.runOpenPanel( args )
    
    if folders then
        if props then
            props[name] = folders[1]
        end
        return folders[1]
    else
        return nil
    end
    
end



--[[
        Synopsis:           Allows user to select a file by way of the "open file" dialog box.
        
        Notes:              param's are same as run-open-panel, except all are optional:
                            - title
                            - prompt ("OK" button label alternative)
                            - filetypes
                            - initial-directory
        
        Returns:            X - selected file is written to named property if provided, and anyway, file selected is returned as path string.
                            Canceled => nil.
--]]        
function RcGui.selectFile( param, props, name )

    local args = {}
    args.title = param.title or "Choose File"
    args.prompt = param.prompt or "OK"
    args.canChooseFiles = true
    args.canCreateDirectories = false
    args.canChooseDirectories = false
    args.allowsMultipleSelection = false
    args.fileTypes = param.fileTypes or "*"
    args.initialDirectory = param.initialDirectory or "/" -- I hate defaulting to documents folder - put 'em at da top...

    local files = LrDialogs.runOpenPanel( args )
    
    if files then
        if props then
            props[name] = files[1]
        end
        return files[1]
    else
        return nil
    end
    
end



--[[
        Synopsis:           Present quick-tips dialog box.
        
        Notes:              Convenience function for presenting a help string with standard title, buttons, and link to web for more info.
        
        Returns:            X
--]]        
function RcGui.quickTips( strTbl )
    local helpStr
    if type( strTbl ) == 'table' then
        helpStr = table.concat( strTbl, "\n\n" )
    elseif type( strTbl ) == 'string' then
        helpStr = strTbl
    else
        helpStr = "Sorry - no quick tips."
    end
    local button = RcUtils.showInfo( helpStr, nil, "More on the Web", "That's Enough" )
    if button == 'ok' then
        LrHttp.openUrlInBrowser( RcUtils.getPluginUrl() ) -- get-plugin-url returns a proper url for plugin else site home.
    end

end



function RcGui.sectionsForTopOfInfoDialog( f, propTbl )
    
    local section = {}
    
    local compatStr = RcUtils.getCompatibilityString()
    
    section.title = RcUtils.getPluginName()
    section.synopsis = compatStr

    section[#section + 1] = 
		f:row {
			f:static_text {
				title = 'Compatible with ' .. compatStr,
			},
			f:static_text {
				title = 'Author: ' .. RcUtils.getAuthor(),
			},
			f:static_text {
				title = "Author's Website: " .. RcUtils.getAuthorsWebsite(),
			},
		}
    section[#section + 1] = 
		f:row {
			f:push_button {
				title = 'Donate',
				font = '<system/bold>',
				action = function( button )
				    LrHttp.openUrlInBrowser( "http://www.robcole.com/Rob/Donate" )
				end,
			},
			f:static_text {
				-- title = "If you find " .. RcUtils.getPluginName() .. " useful, please donate to help development",
				title = "Please donate to help further development of this and other plugins - thanks...",
			},
		}
    
    return { section }
end





return RcGui
