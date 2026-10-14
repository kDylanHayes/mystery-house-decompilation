; Apple II hardware, Monitor ROM and DOS entry points.

KBD          = $C000    ; keyboard data
KBDSTRB      = $C010    ; keyboard strobe
TXTCLR       = $C050    ; graphics mode
TXTSET       = $C051    ; text mode
MIXCLR       = $C052    ; full-screen graphics
MIXSET       = $C053    ; mixed graphics + 4 lines of text
LOWSCR       = $C054    ; display page 1
HISCR        = $C055    ; display page 2
LORES        = $C056    ; lo-res graphics
HIRES        = $C057    ; hi-res graphics
applesoft_error = $EE68    ; Applesoft error entry used for bad HPLOT/DRAW arguments
HOME         = $FC58    ; Monitor: clear the text screen
WAIT         = $FCA8    ; Monitor: delay
GETLN        = $FD6A    ; Monitor: read a line into $0200 with the prompt in $33
GETLN1       = $FD6F    ; Monitor: read a line into $0200 without a prompt
COUT         = $FDED    ; Monitor: print character A (DOS intercepts CTRL-D commands)

HI_SPACE     = $A0    ; Apple II text is high-bit ASCII
HI_CR        = $8D
