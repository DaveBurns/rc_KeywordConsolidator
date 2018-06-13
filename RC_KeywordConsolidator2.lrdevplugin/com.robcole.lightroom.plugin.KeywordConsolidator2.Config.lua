--[[
        Plugin configuration file.
        
        Can be stored in plugin folder, or plugin parent folder, with catalog, or in one of these directories:
        
        { 'home', 'documents', 'appPrefs', 'desktop', 'pictures' }
        
--]]        


local _t = {}

--[[
        Font name:      set to named font on your machine, or one of the following:
                            *  <system>
                            * <system/small>
                            * <system/bold>
                            * <system/small/bold>
                        or, set to a table with these values:
                            name = font-family-name
                            size = {regular|small|mini} - or if that doesn't work, then a number.
                        or, set to nil to get default font.

        Examples:       _t.font = nil                                      -- use default font and size.

                        _t.font = 'Helvetica'

                        _t.font = { name = "my-custom-font", size = "mini" }
                        _t.font = { name = "Arial", size = 12 }
--]]

-- _t.defaultFont = nil
-- _t.defaultFont = { name = "Arial", size=13 }
-- _t.keywordListFont = nil
-- _t.keywordListFont = { name = "Arial", size=11 }

return _t