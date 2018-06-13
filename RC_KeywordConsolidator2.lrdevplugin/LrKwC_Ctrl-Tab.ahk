; ##########################################################################################
; NOTES: -----------------------------------------------------------------------------------
; ##########################################################################################
; 
; Script to send tab, shift-tab, home in response to ctrl-tab.

#SingleInstance force

;SetTitleMatchMode, 2

;KDef = 0
;if KDef
;#IfWinActive Lightroom
    ^tab::Send {Shift Up}{Tab}{Shift Down}{Tab}{Shift Up}{End}
;#IfWinActive

#x::ExitApp   ; So far, programmatic exiting not working, but Start-X keystroke trigger seems to work just dandy.


;Sleep 2000
;IfWinExist, Lightroom
;    MsgBox Starting
;    ^tab::Send {Shift Up}{Tab}{Shift Down}{Tab}{Shift Up}{Right}
;IfWinNotExist, Lightroom
;{
;    MsgBox stopping
;    ExitApp
;}

;SetTitleMatchMode, 2

;Loop
;{
;    IfWinNotExist, Lightroom - Library
;        ExitApp
;Sleep 30000
;ExitApp    
;}    
    




