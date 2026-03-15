   10 REM FROGMAN - BBC BASIC Loader
   20 REM By MG/RTW (c) 1993
   30 REM
   40 REM This is a plain-text reconstruction of the tokenized
   50 REM BASIC program "Ribbit" from the original disk.
   60 REM
   70 REM The original sets PAGE=&1900 via !Boot, then this
   80 REM program is CHAINed. It displays the Mode 7 title
   90 REM screen, detects hardware, lets the player choose
  100 REM level 1 or 2, then *RUN Loader.
  110 REM
  120 MODE 7
  130 VDU 23,1,0;0;0;0;
  140 REM --- Title screen ---
  150 PRINT TAB(0,1)CHR$(141)CHR$(130)CHR$(157)CHR$(135)" FROGMAN "CHR$(156)
  160 PRINT TAB(0,2)CHR$(141)CHR$(130)CHR$(157)CHR$(135)" FROGMAN "CHR$(156)
  170 PRINT TAB(0,3)CHR$(131)"   ";CHR$(157)CHR$(131);CHR$(156)
  180 PRINT TAB(0,5)CHR$(134)" Written and designed  by"
  190 PRINT TAB(0,6)CHR$(134)"     Matthew Godbolt"
  200 PRINT TAB(0,7)CHR$(134)" & Richard Talbot-Watkins"
  210 PRINT TAB(0,9)CHR$(133)"   (C) MG/RTW Feb 1993"
  220 PRINT TAB(0,11)CHR$(131)"   ";CHR$(157)CHR$(131);CHR$(156)
  230 REM --- Level selection ---
  240 PRINT TAB(0,15)CHR$(130)"Choose level";CHR$(129)"(1 or 2)";CHR$(131)":"
  250 REPEAT
  260   A%=INKEY(0)
  270 UNTIL A%=49 OR A%=50
  280 PRINT CHR$(A%)
  290 level%=A%-48
  300 REM --- Load title screen graphics ---
  310 MODE 2
  320 VDU 23,1,0;0;0;0;
  330 REM Decompress and display Data2 title graphics
  340 REM (RLE compressed Mode 2 screen data)
  350 REM --- Start game ---
  360 *RUN Loader
