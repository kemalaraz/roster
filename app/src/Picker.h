// Picker.h — interactive terminal profile picker (TUI).
#import <Foundation/Foundation.h>

// Draws a styled arrow-key menu on /dev/tty to choose a profile for `tool`
// ("claude" or "codex"), then prints the chosen profile's config dir to stdout
// (empty line = Default/global, or cancelled). Returns 0.
int RunPicker(NSString *tool);
