


local _items = {}




--   R C   C U S T O M   M E T A D A T A
_items[#_items + 1] = "com.robcole.lightroom.metadata.RC_CustomMetadata.*"

--   D E V   M E T A
_items[#_items + 1] = "com.robcole.lightroom.metadata.DevMeta.*"

--   N X   T O O E Y
_items[#_items + 1] = "com.robcole.lightroom.plugin.nxTooey3.*"


--   E X I F   M E T A
-- handled dynamically.


return _items