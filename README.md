# Zig build for xiph/opus

## Usage

Run `zig build` to obtain static and dynamic builds of opus 1.6.1.
See `zig build -h` for the full list of options.

```
Project-Specific Options:
  -Dtarget=[string]            The CPU architecture, OS, and ABI to build for
  -Dcpu=[string]               Target CPU features to add or subtract
  -Dofmt=[string]              Target object format
  -Ddynamic-linker=[string]    Path to interpreter on the target system
  -Doptimize=[enum]            Prioritize performance, safety, or binary size
                                 Supported Values:
                                   Debug
                                   ReleaseSafe
                                   ReleaseFast
                                   ReleaseSmall
  -Ddeep-plc=[bool]            Use deep PLC for SILK
  -Ddred=[bool]                Enable DRED
  -Drtcd=[bool]                Enable runtime feature detection
  -Dfixed-point=[bool]         use fixed point instead of floats
  -Dfixed-debug=[bool]         debug fixed point implementation
  -Ddisable-float-api=[bool]   disable float api (default false)
  -Dassertions=[bool]          Enable assertions (enabled by default in debug)
  -Dfloat-approx=[bool]        enable float approximations
  -Dosce=[bool]                Enable opus speech coding enhancement
  -Dosce-bwe=[bool]            Enable opus speech coding enhancement BWE
  -Dhardening=[bool]           Enable hardening (default true)
  -Ddisable-debug-float=[bool] (default true)
```

### Usage from Zig

If you're using this library from Zig, import the `opus` module, which will contain
the full implementation and translated C header files which you can use like so:

```zig
const opus = @import("opus");

test {
    std.testing.expect(0 != opus.opus_get_decoder_size());
}
```

If you want to make use of dynamic linking, then you can import the `headers` module,
which will contain the translated C header files, but none of the implementation.
