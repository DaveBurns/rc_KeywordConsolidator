--[[----------------------------------------------------------------------------

Filename:		Info.lua

Synopsis:		Summary information for plugin.

For Hire:       I am. - Please contact me at http://www.robcole.com.

------------------------------------------------------------------------------]]


return {

    appName = "KeywordConsolidator",
    author = "Rob Cole",
    authorsWebsite = "www.robcole.com",
    platformDisp = 'Windows+Mac',

	LrSdkVersion = 5.0,
	LrSdkMinimumVersion = 3.0, -- minimum SDK version required by this plugin

    LrPluginName = 'RC Keyword Consolidator',
	LrToolkitIdentifier = 'com.robcole.lightroom.plugin.KeywordConsolidator2',
	
	LrPluginInfoProvider = 'KeywordConsolidator_InfoProvider.lua',
    LrPluginInfoUrl = 'http://www.robcole.com/Rob/ProductsAndServices/KeywordConsolidatorLrPlugin',
	--LrMetadataProvider = 'KeywordConsolidator_MetadataProvider.lua', -- required for init to be called upon startup.
	LrInitPlugin = 'KeywordConsolidator_PluginInit.lua',
	LrShutdownPlugin = 'KeywordConsolidator_Shutdown.lua',
    LrTagsetProvider = "Tagsets.lua",
	
	LrExportMenuItems = {
	    {
    		title = "Con&solidate Keywords",
    		file = "KeywordConsolidator_ServiceProvider_Consolidate.lua",
        },
	    {
    		title = "&Keyword List",
    		file = "KeywordConsolidator_ServiceProvider_ViewKeywordList.lua",
        },
    },
    
	VERSION = { major = 3, minor = 7, revision = 1, build = 0 },
	

}
