-- Angepasst aus create-dmg (support/template.applescript): Finder-Sidebar ausblenden,
-- damit das DMG-Fenster nicht deutlich breiter als --window-size wird (u. a. macOS 13+).
--
-- Nach `close`/`open` setzt Finder den Icon-View oft auf Standard (weißer Hintergrund, Icon-Orte).
-- Daher: dieselben create-dmg-Klauseln (BACKGROUND, POSITION, …) **noch einmal** nach dem Reopen.
-- Das upstream-„bounds minus 10“-Zwischenlayout entfällt — vermeidet sichtbares Zittern/falsche Größe.

on run (volumeName)
	tell application "Finder"
		tell disk (volumeName as string)
			open

			set theXOrigin to WINX
			set theYOrigin to WINY
			set theWidth to WINW
			set theHeight to WINH

			set theBottomRightX to (theXOrigin + theWidth)
			set theBottomRightY to (theYOrigin + theHeight)
			set dsStore to "\"" & "/Volumes/" & volumeName & "/" & ".DS_STORE\""

			tell container window
				set current view to icon view
				set toolbar visible to false
				set statusbar visible to false
				try
					set sidebar width to 0
				end try
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
				set statusbar visible to false
				REPOSITION_HIDDEN_FILES_CLAUSE
			end tell

			set opts to the icon view options of container window
			tell opts
				set icon size to ICON_SIZE
				set text size to TEXT_SIZE
				set arrangement to not arranged
			end tell
			BACKGROUND_CLAUSE

			-- Positioning
			POSITION_CLAUSE

			-- Hiding
			HIDING_CLAUSE

			-- Application and QL Link Clauses
			APPLICATION_CLAUSE
			QL_CLAUSE
			close
			open
			delay 1

			-- Nach Reopen: Hintergrund & Layout erneut (sonst oft weiß / Standard-Positionen).
			set opts to the icon view options of container window
			tell opts
				set icon size to ICON_SIZE
				set text size to TEXT_SIZE
				set arrangement to not arranged
			end tell
			BACKGROUND_CLAUSE
			POSITION_CLAUSE
			HIDING_CLAUSE
			APPLICATION_CLAUSE
			QL_CLAUSE

			tell container window
				set statusbar visible to false
				try
					set sidebar width to 0
				end try
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
			end tell
		end tell

		delay 1

		tell disk (volumeName as string)
			tell container window
				set statusbar visible to false
				try
					set sidebar width to 0
				end try
				set the bounds to {theXOrigin, theYOrigin, theBottomRightX, theBottomRightY}
			end tell
		end tell

		delay 3

		set waitTime to 0
		set ejectMe to false
		repeat while ejectMe is false
			delay 1
			set waitTime to waitTime + 1

			if (do shell script "[ -f " & dsStore & " ]; echo $?") = "0" then set ejectMe to true
		end repeat
		log "waited " & waitTime & " seconds for .DS_STORE to be created."
	end tell
end run
