KeywordConsolidator README file.
===============================


Legal Disclaimer:
-----------------

You are responsible for any file corruption or other ill effects that result from using KeywordConsolidator, or that you think have resulted from using KeywordConsolidator.


What is KeywordConsolidator?
-----------------


- see FAQ on the website.
- see Limitations section at bottom.


What KeywordConsolidator is NOT:
---------------------

- see FAQ on the website.
- see Limitations section at bottom.



How to use KeywordConsolidator:
--------------------

- Install like any other plugin, thusly:
	Option 1 (recommended)
		1. Unzip plugin release distribution (zip file containing '.lrplugin' or '.lrdevplugin' folder) to any folder.
		2. In Lightroom, go to the 'File' Menu and click 'Plug-in Manager'.
		3. Click the 'Add' button and select the '.lrplugin' or '.lrdevplugin' folder that was unzipped in step 1.
                   - Note: The files will be accessed in place, so do NOT delete the folder after adding the plugin.
		4. You no longer have to check 'Reload plug-in on each export' box - in fact, it will work a bit faster if you don't.
	Option2 (not recommended)
		1. Copy (or move) the .lrplugin or .lrdevplugin folder AND the RC_CommonModules folder into your Lightroom 'Module' folder (hint: its a subdirectory of your Lightroom Presets folder (see Preferences under Edit Menu). Note: all my plugins have an RC_CommonModules folder included and they are generally backward compatible, but you never know - its safest to use Option 1.
		2. Restart Lightroom.

- Edit KeywordConsolidator Settings in the Plugin Manager:

    - see FAQ on the website.
    - Log File - you can enter a path and extension, but both will be ignored. Base filename will be extracted
      and log file will be stored in the root of your "Documents" folder - .log extension while being written, .txt extension afterward.
    - Test Mode - allows log file to be created when doing preset definition and application, which is not normally done.
      Also, when test mode is enabled, no files will actually be modified or deleted - although its not a bad idea to keep things backed up, just the same ;-}
      
      Note: test mode is not effective in Keyword List, only Keyword Consolidator.

    - Log Verbose (Debug) - more info in log file AND other debugging checks and such are engaged.
    - Log Overwrite - uncheck this to keep appending to the same log file - not even god knows what will happen if you don't go in and delete the monstrosity after a while...

- Select one or more photos (if none selected will do entire filmstrip).
- Invoke KeywordConsolidator via "File -> Plug-in Extras -> KeywordConsolidator -> Consolidate" (or Alt-F,S,S on Windows, for short).
- Invoke KeywordList via "File -> Plug-in Extras -> KeywordConsolidator -> Keyword List" (or Alt-F,S,K on Windows, for short).


Other User Interface Notes
--------------------------





Miscellaneous Operational Notes
-------------------------------




What if it doesn't work?
------------------------

- Dialog boxes should provide some indication as to problems detected.
- Look at the log file for clues, if none:
  - enable verbose logging in the plugin-config file and try again.
- Make sure you've followed the directions, or intelligently strayed from the directions if I screwed them up.
- Let Rob Cole know, thusly:

	http://www.robcole.com/Rob/ProblemReport

  and until I get a subject configured, PLEASE REMEMBER to reference KeywordConsolidator in the report.


What if it works so good I can hardly stand it?
-----------------------------------------------

- Make a donation, thusly:

	http://www.robcole.com/Rob/Donate (thanks - And remember to reference KeywordConsolidator in the message box)



What if I just want to make a suggestion?
-----------------------------------------

- Contact Rob Cole, and until I get a subject configured, PLEASE REMEMBER to reference KeywordConsolidator in the message.

	http://www.robcole.com/Rob/ContactMe



Limitations:
------------

- see FAQ on website.


Future Prospects:
-----------------

- Better UI.
- Removal of limitations (see above).
- Greater scope, in general, and specifically:
  (see Web FAQ for now)


Good luck, and I hope you find KeywordConsolidator useful.
Rob Cole www.robcole.com


