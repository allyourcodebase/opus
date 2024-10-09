# Zig build for xiph/opus

Initial implementation of a Zig build script for xiph/opus.

The current code doesn't implement some optional configuration, 
open an issue if you need support for any of those secondary options.

**NOTE: the upstream project contains UB and thus is built with ubsan disabled.**

Run `zig build test` to run the opus API test.
