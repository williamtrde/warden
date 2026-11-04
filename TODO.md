# TODO

- Run the DMG on a real macOS 14 machine. The weak link to FoundationModels is confirmed in the binary, but launch has only been tested on macOS 26.
- Click the Accept and Revert buttons of a real notification by hand. The routing is covered by reading and by engine tests, not by an automated UI test.
- Surgical revert rewrites filtered files: comments and formatting are lost, and integers beyond 64 bits lose precision. A backup is saved first. A text-level patch would keep them.
- After a state reset, on-device AI goes back to enabled even if it was turned off.
- The sidebar still shows green checks while monitoring is paused.
