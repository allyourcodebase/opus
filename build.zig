const std = @import("std");

const BuildFlags = struct {
    fixed_point: ?bool = null,
    fixed_debug: ?bool = null,
    float_api: ?bool = null,
    assertions: ?bool = null,
    float_approx: ?bool = null,
    dred: ?bool = null,
    deep_plc: ?bool = null,
    osce: ?bool = null,
    osce_bwe: ?bool = null,
    hardening: ?bool = null,
    debug_float: ?bool = null,
    rtcd: bool = false,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flags: BuildFlags = .{
        .fixed_point = b.option(bool, "fixed-point", "use fixed point instead of floats"),
        .fixed_debug = b.option(bool, "fixed-debug", "debug fixed point implementation"),
        .float_api = b.option(bool, "float-api", "enable float api (default true)"),
        .assertions = b.option(bool, "assertions", "Enable assertions (enabled by default in debug)"),
        .float_approx = b.option(bool, "float-approx", "enable float approximations"),
        .dred = b.option(bool, "dred", "Enable DRED"),
        .deep_plc = b.option(bool, "deep-plc", "Use deep PLC for SILK"),
        .osce = b.option(bool, "osce", "Enable opus speech coding enhancement"),
        .osce_bwe = b.option(bool, "osce-bwe", "Enable opus speech coding enhancement BWE"),
        .hardening = b.option(bool, "hardening", "Enable hardening (default true)"),
        .debug_float = b.option(bool, "debug-float", "(default false)"),
        .rtcd = b.option(bool, "rtcd", "Enable runtime feature detection") orelse false,
    };

    const lib, const dynlib, const run_test = buildOpus(b, target, optimize, flags);
    b.installArtifact(lib);
    b.installArtifact(dynlib);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
    setupCi(b, target);
}

const CpuFeatures = struct {
    rtcd: bool,
    arm_v4: bool,
    arm_v5e: bool,
    arm_v6: bool,
    neon: bool,
    dotprod: bool,
    avx2: bool,
    sse: bool,
    sse2: bool,
    sse4_1: bool,
};

pub fn buildOpus(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    flags: BuildFlags,
) struct { *std.Build.Step.Compile, *std.Build.Step.Compile, *std.Build.Step.Run } {
    const upstream = b.dependency("upstream", .{});
    const arm = target.result.cpu.arch.isArm();
    const aarch64 = target.result.cpu.arch.isAARCH64();
    const x86 = target.result.cpu.arch.isX86();

    const cpu_features: CpuFeatures = .{
        .rtcd = flags.rtcd,

        .arm_v4 = !flags.rtcd and arm and
            std.Target.arm.featureSetHas(target.result.cpu.features, .has_v4t),
        .arm_v5e = !flags.rtcd and arm and
            std.Target.arm.featureSetHas(target.result.cpu.features, .has_v5te),
        .arm_v6 = !flags.rtcd and arm and
            std.Target.arm.featureSetHas(target.result.cpu.features, .has_v6),
        .neon = !flags.rtcd and (aarch64 or arm) and
            std.Target.aarch64.featureSetHas(target.result.cpu.features, .neon),
        .dotprod = !flags.rtcd and (aarch64 or arm) and
            std.Target.aarch64.featureSetHas(target.result.cpu.features, .dotprod),

        .avx2 = !flags.rtcd and x86 and
            std.Target.x86.featureSetHas(target.result.cpu.features, .avx2),
        .sse = !flags.rtcd and x86 and
            std.Target.x86.featureSetHas(target.result.cpu.features, .sse),
        .sse2 = !flags.rtcd and x86 and
            std.Target.x86.featureSetHas(target.result.cpu.features, .sse2),
        .sse4_1 = !flags.rtcd and x86 and
            std.Target.x86.featureSetHas(target.result.cpu.features, .sse4_1),
    };

    const config = b.addConfigHeader(.{}, .{
        .VAR_ARRAYS = true,
        .USE_ALLOCA = null,
        .HAVE_DLFCN_H = true,
        .HAVE_INTTYPES_H = true,
        .HAVE_LRINT = true,
        .HAVE_LRINTF = true,
        .HAVE_STDINT_H = true,
        .HAVE_STDIO_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = true,
        .HAVE_STRING_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = true,
        .CPU_INFO_BY_ASM = true,
        .FIXED_POINT = flags.fixed_point,
        .FIXED_DEBUG = flags.fixed_debug,
        .DISABLE_FLOAT_API = if (flags.float_api orelse true) null else true,
        .ENABLE_ASSERTIONS = flags.assertions orelse if (optimize == .Debug) true else null,
        .FLOAT_APPROX = if (flags.float_approx orelse false)
            if (target.result.cpu.arch.isAARCH64() or target.result.cpu.arch.isArm() or
                target.result.cpu.arch.isX86() or target.result.cpu.arch.isPowerPC()) true else null
        else
            null,
        .ENABLE_DRED = flags.dred,
        .ENABLE_DEEP_PLC = flags.deep_plc,
        .ENABLE_OSCE = flags.osce,
        .ENABLE_OSCE_BWE = flags.osce_bwe,
        .ENABLE_HARDENING = if (flags.hardening orelse true) true else null,
        .DISABLE_DEBUG_FLOAT = if (flags.debug_float orelse false) true else null,
        .OPUS_HAVE_RTCD = if (flags.rtcd) true else null,
        .OPUS_ARM_ASM = if (target.result.cpu.arch.isArm()) true else null,
        .OPUS_ARM_INLINE_ASM = if (cpu_features.arm_v4) true else null,
        .OPUS_ARM_INLINE_EDSP = if (cpu_features.arm_v5e) true else null,
        .OPUS_ARM_INLINE_MEDIA = if (cpu_features.arm_v6) true else null,
        .OPUS_ARM_INLINE_NEON = if (cpu_features.neon) true else null,
        .OPUS_ARM_PRESUME_DOTPROD = if (cpu_features.dotprod) true else null,
        .OPUS_ARM_PRESUME_NEON_INTR = if (cpu_features.neon) true else null,
        .OPUS_ARM_PRESUME_AARCH64_NEON_INTR = if (aarch64 and cpu_features.neon) true else null,
        .OPUS_X86_PRESUME_AVX2 = if (cpu_features.avx2) true else null,
        .OPUS_X86_PRESUME_SSE = if (cpu_features.sse) true else null,
        .OPUS_X86_PRESUME_SSE2 = if (cpu_features.sse2) true else null,
        .OPUS_X86_PRESUME_SSE4_1 = if (cpu_features.sse4_1) true else null,

        // 'may have's are compiler capability checks.
        .OPUS_ARM_MAY_HAVE_NEON = if ((aarch64 or arm) and (flags.rtcd or cpu_features.neon)) true else null,
        .OPUS_ARM_MAY_HAVE_NEON_INTR = if ((aarch64 or arm) and (flags.rtcd or cpu_features.neon)) true else null,
        .OPUS_ARM_MAY_HAVE_DOTPROD = if ((aarch64 or arm) and (flags.rtcd or cpu_features.dotprod)) true else null,
        .OPUS_ARM_MAY_HAVE_AARCH64_NEON_INTR = if (aarch64 and (flags.rtcd or cpu_features.neon)) true else null,
        .OPUS_X86_MAY_HAVE_AVX2 = if (x86 and (flags.rtcd or cpu_features.avx2)) true else null,
        .OPUS_X86_MAY_HAVE_SSE = if (x86 and (flags.rtcd or cpu_features.sse)) true else null,
        .OPUS_X86_MAY_HAVE_SSE2 = if (x86 and (flags.rtcd or cpu_features.sse2)) true else null,
        .OPUS_X86_MAY_HAVE_SSE4_1 = if (x86 and (flags.rtcd or cpu_features.sse4_1)) true else null,
    });

    const plc_model = if (flags.deep_plc orelse false)
        b.lazyDependency("plc_model", .{}) orelse null
    else
        null;

    const celt = buildCelt(b, target, optimize, cpu_features, upstream, plc_model, config);
    const silk = buildSilk(b, target, optimize, cpu_features, upstream, plc_model, config);

    const tc = b.addTranslateC(.{
        .root_source_file = upstream.path("include/opus.h"),
        .target = target,
        .optimize = optimize,
    });
    _ = tc.addModule("headers");

    const mod = b.addModule("opus", .{
        .root_source_file = tc.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "opus",
        .linkage = .static,
        .root_module = mod,
    });

    const dynlib = b.addLibrary(.{
        .name = "opus",
        .linkage = .dynamic,
        .root_module = mod,
    });

    mod.addImport("celt", celt);
    mod.addImport("silk", silk);

    mod.addConfigHeader(config);
    // lib.linkLibC();
    lib.installHeadersDirectory(upstream.path("include"), ".", .{});
    // lib.installHeader(xiph_opus.path("include/opus.h"), "opus.h");
    mod.addIncludePath(upstream.path("include"));
    mod.addIncludePath(upstream.path("src"));
    mod.addIncludePath(upstream.path("celt"));
    mod.addIncludePath(upstream.path("silk"));
    mod.addIncludePath(upstream.path("dnn"));
    mod.addIncludePath(upstream.path("."));
    mod.addCSourceFiles(.{
        .root = upstream.path("src/"),
        .files = &.{
            // OPUS_SOURCES
            "opus.c",
            "opus_decoder.c",
            "opus_encoder.c",
            "extensions.c",
            "opus_multistream.c",
            "opus_multistream_encoder.c",
            "opus_multistream_decoder.c",
            "repacketizer.c",
            "opus_projection_encoder.c",
            "opus_projection_decoder.c",
            "mapping_matrix.c",
            // OPUS_SOURCES_FLOAT
            "analysis.c",
            "mlp.c",
            "mlp_data.c",
        },
        .flags = cflags,
    });

    if (flags.dred orelse false) {
        mod.addCSourceFiles(.{
            .root = upstream.path("dnn/"),
            .files = &.{
                "burg.c",
                "dred_coding.c",
                // "dred_compare.c",
                "dred_decoder.c",
                "dred_encoder.c",
                "dred_rdovae_dec.c",
                "dred_rdovae_enc.c",
                "fargan.c",
                "freq.c",
                // "fwgan.c",
                "kiss99.c",
                // "lpcnet.c",
                "lpcnet_enc.c",
                "lpcnet_plc.c",
                "lpcnet_tables.c",
                "nndsp.c",
                "nnet.c",
                "nnet_default.c",
                "osce.c",
                "osce_features.c",
                "parse_lpcnet_weights.c",
                "pitchdnn.c",
            },
            .flags = cflags,
        });

        if (target.result.cpu.arch.isAARCH64()) {
            mod.addIncludePath(upstream.path("dnn/arm"));
            mod.addCSourceFiles(.{
                .root = upstream.path("dnn/arm"),
                .files = &.{
                    "arm_dnn_map.c",
                },
                .flags = cflags,
            });

            if (cpu_features.dotprod) {
                mod.addCSourceFiles(.{
                    .root = upstream.path("dnn/arm"),
                    .files = &.{
                        "nnet_dotprod.c",
                    },
                    .flags = cflags,
                });
            }

            if (cpu_features.neon) {
                mod.addCSourceFiles(.{
                    .root = upstream.path("dnn/arm"),
                    .files = &.{
                        "nnet_neon.c",
                    },
                    .flags = cflags,
                });
            }

            if (cpu_features.rtcd) {
                mod.linkLibrary(rtcdObject(b, target, &.{
                    upstream.path("include"),
                    upstream.path("dnn"),
                    upstream.path("dnn/arm"),
                    upstream.path("celt"),
                    upstream.path("."),
                }, config, "opus", .aarch64, .dotprod, .{
                    .root = upstream.path("dnn/arm"),
                    .files = &.{
                        "nnet_dotprod.c",
                    },
                    .flags = rtcdCFlags(.aarch64, .dotprod),
                }));

                mod.linkLibrary(rtcdObject(b, target, &.{
                    upstream.path("include"),
                    upstream.path("dnn"),
                    upstream.path("dnn/arm"),
                    upstream.path("celt"),
                    upstream.path("."),
                }, config, "opus", .aarch64, .neon, .{
                    .root = upstream.path("dnn/arm"),
                    .files = &.{
                        "nnet_neon.c",
                    },
                    .flags = rtcdCFlags(.aarch64, .neon),
                }));
            }
        }

        if (target.result.cpu.arch.isX86()) {
            mod.addIncludePath(upstream.path("dnn/x86"));
            mod.addCSourceFiles(.{
                .root = upstream.path("dnn/x86"),
                .files = &.{
                    "x86_dnn_map.c",
                },
                .flags = cflags,
            });
            if (cpu_features.sse2) {
                mod.addCSourceFiles(.{
                    .root = upstream.path("dnn/x86"),
                    .files = &.{
                        "nnet_sse2.c",
                    },
                    .flags = cflags,
                });
            }
            if (cpu_features.sse4_1) {
                mod.addCSourceFiles(.{
                    .root = upstream.path("dnn/x86"),
                    .files = &.{
                        "nnet_sse4_1.c",
                    },
                    .flags = cflags,
                });
            }
            if (cpu_features.avx2) {
                mod.addCSourceFiles(.{
                    .root = upstream.path("dnn/x86"),
                    .files = &.{
                        "nnet_avx2.c",
                    },
                    .flags = cflags,
                });
            }

            if (cpu_features.rtcd) {
                mod.linkLibrary(rtcdObject(b, target, &.{
                    upstream.path("include"),
                    upstream.path("dnn"),
                    upstream.path("dnn/x86"),
                    upstream.path("celt"),
                    upstream.path("."),
                }, config, "opus", .x86_64, .sse2, .{
                    .root = upstream.path("dnn/x86"),
                    .files = &.{
                        "nnet_sse2.c",
                    },
                    .flags = rtcdCFlags(.x86_64, .sse2),
                }));
                mod.linkLibrary(rtcdObject(b, target, &.{
                    upstream.path("include"),
                    upstream.path("dnn"),
                    upstream.path("dnn/x86"),
                    upstream.path("celt"),
                    upstream.path("."),
                }, config, "opus", .x86_64, .sse4_1, .{
                    .root = upstream.path("dnn/x86"),
                    .files = &.{
                        "nnet_sse4_1.c",
                    },
                    .flags = rtcdCFlags(.x86_64, .sse4_1),
                }));
                mod.linkLibrary(rtcdObject(b, target, &.{
                    upstream.path("include"),
                    upstream.path("dnn"),
                    upstream.path("dnn/x86"),
                    upstream.path("celt"),
                    upstream.path("."),
                }, config, "opus", .x86_64, .avx2, .{
                    .root = upstream.path("dnn/x86"),
                    .files = &.{
                        "nnet_avx2.c",
                    },
                    .flags = rtcdCFlags(.x86_64, .avx2),
                }));
            }
        }
    }
    if (plc_model) |plc| {
        mod.addIncludePath(plc.path("."));
        mod.addCSourceFiles(.{
            .root = plc.path(""),
            .files = &.{
                "bbwenet_data.c",
                "dred_rdovae_dec_data.c",
                "dred_rdovae_enc_data.c",
                "dred_rdovae_stats_data.c",
                "fargan_data.c",
                "lace_data.c",
                "lossgen_data.c",
                "nolace_data.c",
                "pitchdnn_data.c",
                "plc_data.c",
            },
            .flags = cflags,
        });
    }

    b.installArtifact(lib);

    const test_opus_api = b.addExecutable(.{
        .name = "test_opus_api",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    test_opus_api.root_module.linkLibrary(lib);
    test_opus_api.root_module.addCSourceFile(.{
        .file = upstream.path("tests/test_opus_api.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
        },
    });
    test_opus_api.root_module.addIncludePath(upstream.path("celt"));

    const run_test = b.addRunArtifact(test_opus_api);
    run_test.has_side_effects = false;

    return .{ lib, dynlib, run_test };
}

fn buildCelt(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cpu_features: CpuFeatures,
    upstream: *std.Build.Dependency,
    plc_model: ?*std.Build.Dependency,
    config: *std.Build.Step.ConfigHeader,
) *std.Build.Module {
    const mod = b.addModule("celt", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addConfigHeader(config);
    mod.addIncludePath(upstream.path("include"));
    mod.addIncludePath(upstream.path("celt"));
    mod.addIncludePath(upstream.path("silk"));
    mod.addIncludePath(upstream.path("dnn"));
    mod.addIncludePath(upstream.path("."));
    if (plc_model) |plc| {
        mod.addIncludePath(plc.path("."));
    }
    mod.addCSourceFiles(.{
        .root = upstream.path("celt"),
        .files = &.{
            "bands.c",        "celt.c",
            "celt_encoder.c", "celt_decoder.c",
            "cwrs.c",         "entcode.c",
            "entdec.c",       "entenc.c",
            "kiss_fft.c",     "laplace.c",
            "mathops.c",      "mdct.c",
            "modes.c",        "pitch.c",
            "celt_lpc.c",     "quant_bands.c",
            "rate.c",         "vq.c",
        },
        .flags = cflags,
    });
    if (target.result.cpu.arch.isAARCH64()) {
        mod.addIncludePath(upstream.path("celt/arm"));
        mod.addCSourceFiles(.{
            .root = upstream.path("celt/arm"),
            .files = &.{
                "armcpu.c",
                "arm_celt_map.c",
                // "celt_mdct_ne10.c",
                // "celt_fft_ne10.c",
            },
            .flags = cflags,
        });

        if (cpu_features.neon) {
            mod.addCSourceFiles(.{
                .root = upstream.path("celt/arm"),
                .files = &.{
                    "celt_neon_intr.c",
                    "pitch_neon_intr.c",
                },
                .flags = cflags,
            });
        }

        if (cpu_features.rtcd) {
            mod.linkLibrary(rtcdObject(b, target, &.{
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("celt"),
                upstream.path("celt/arm"),
                upstream.path("silk"),
                upstream.path("."),
            }, config, "celt", .aarch64, .neon, .{
                .root = upstream.path("celt/arm"),
                .files = &.{
                    "celt_neon_intr.c",
                    "pitch_neon_intr.c",
                },
                .flags = rtcdCFlags(.aarch64, .neon),
            }));
        }
    }

    if (target.result.cpu.arch.isX86()) {
        mod.addIncludePath(upstream.path("celt/x86"));
        mod.addCSourceFiles(.{
            .root = upstream.path("celt/x86"),
            .files = &.{
                "x86cpu.c",
                "x86_celt_map.c",
            },
            .flags = cflags,
        });

        if (cpu_features.sse) {
            mod.addCSourceFiles(.{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "pitch_sse.c",
                },
                .flags = cflags,
            });
        }
        if (cpu_features.sse2) {
            mod.addCSourceFiles(.{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "vq_sse2.c",
                    "pitch_sse2.c",
                },
                .flags = cflags,
            });
        }
        if (cpu_features.sse4_1) {
            mod.addCSourceFiles(.{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "pitch_sse4_1.c",
                    "celt_lpc_sse4_1.c",
                },
                .flags = cflags,
            });
        }
        if (cpu_features.avx2) {
            mod.addCSourceFiles(.{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "pitch_avx.c",
                },
                .flags = cflags,
            });
        }

        if (cpu_features.rtcd) {
            mod.linkLibrary(rtcdObject(b, target, &.{
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("celt"),
                upstream.path("celt/x86"),
                upstream.path("silk"),
                upstream.path("."),
            }, config, "celt", .x86_64, .sse, .{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "pitch_sse.c",
                },
                .flags = rtcdCFlags(.x86_64, .sse),
            }));
            mod.linkLibrary(rtcdObject(b, target, &.{
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("celt"),
                upstream.path("celt/x86"),
                upstream.path("silk"),
                upstream.path("."),
            }, config, "celt", .x86_64, .sse2, .{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "vq_sse2.c",
                    "pitch_sse2.c",
                },
                .flags = rtcdCFlags(.x86_64, .sse2),
            }));
            mod.linkLibrary(rtcdObject(b, target, &.{
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("celt"),
                upstream.path("celt/x86"),
                upstream.path("silk"),
                upstream.path("."),
            }, config, "celt", .x86_64, .sse4_1, .{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "pitch_sse4_1.c",
                    "celt_lpc_sse4_1.c",
                },
                .flags = rtcdCFlags(.x86_64, .sse4_1),
            }));
            mod.linkLibrary(rtcdObject(b, target, &.{
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("celt"),
                upstream.path("celt/x86"),
                upstream.path("silk"),
                upstream.path("."),
            }, config, "celt", .x86_64, .avx2, .{
                .root = upstream.path("celt/x86"),
                .files = &.{
                    "pitch_avx.c",
                },
                .flags = rtcdCFlags(.x86_64, .avx2),
            }));
        }
    }
    return mod;
}

fn buildSilk(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cpu_features: CpuFeatures,
    upstream: *std.Build.Dependency,
    plc_model: ?*std.Build.Dependency,
    config: *std.Build.Step.ConfigHeader,
) *std.Build.Module {
    const mod = b.addModule("silk", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addConfigHeader(config);
    mod.addIncludePath(upstream.path("include"));
    mod.addIncludePath(upstream.path("silk"));
    mod.addIncludePath(upstream.path("silk/float"));
    mod.addIncludePath(upstream.path("silk/fixed"));
    mod.addIncludePath(upstream.path("celt"));
    mod.addIncludePath(upstream.path("dnn"));
    mod.addIncludePath(upstream.path("."));
    if (plc_model) |plc| {
        mod.addIncludePath(plc.path("."));
    }
    mod.addCSourceFiles(.{
        .root = upstream.path("silk"),
        .files = &(.{
            "CNG.c",                       "code_signs.c",
            "init_decoder.c",              "decode_core.c",
            "decode_frame.c",              "decode_parameters.c",
            "decode_indices.c",            "decode_pulses.c",
            "decoder_set_fs.c",            "dec_API.c",
            "enc_API.c",                   "encode_indices.c",
            "encode_pulses.c",             "gain_quant.c",
            "interpolate.c",               "LP_variable_cutoff.c",
            "NLSF_decode.c",               "NSQ.c",
            "NSQ_del_dec.c",               "PLC.c",
            "shell_coder.c",               "tables_gain.c",
            "tables_LTP.c",                "tables_NLSF_CB_NB_MB.c",
            "tables_NLSF_CB_WB.c",         "tables_other.c",
            "tables_pitch_lag.c",          "tables_pulses_per_block.c",
            "VAD.c",                       "control_audio_bandwidth.c",
            "quant_LTP_gains.c",           "VQ_WMat_EC.c",
            "HP_variable_cutoff.c",        "NLSF_encode.c",
            "NLSF_VQ.c",                   "NLSF_unpack.c",
            "NLSF_del_dec_quant.c",        "process_NLSFs.c",
            "stereo_LR_to_MS.c",           "stereo_MS_to_LR.c",
            "check_control_input.c",       "control_SNR.c",
            "init_encoder.c",              "control_codec.c",
            "A2NLSF.c",                    "ana_filt_bank_1.c",
            "biquad_alt.c",                "bwexpander_32.c",
            "bwexpander.c",                "debug.c",
            "decode_pitch.c",              "inner_prod_aligned.c",
            "lin2log.c",                   "log2lin.c",
            "LPC_analysis_filter.c",       "LPC_inv_pred_gain.c",
            "table_LSF_cos.c",             "NLSF2A.c",
            "NLSF_stabilize.c",            "NLSF_VQ_weights_laroia.c",
            "pitch_est_tables.c",          "resampler.c",
            "resampler_down2_3.c",         "resampler_down2.c",
            "resampler_private_AR2.c",     "resampler_private_down_FIR.c",
            "resampler_private_IIR_FIR.c", "resampler_private_up2_HQ.c",
            "resampler_rom.c",             "sigm_Q15.c",
            "sort.c",                      "sum_sqr_shift.c",
            "stereo_decode_pred.c",        "stereo_encode_pred.c",
            "stereo_find_predictor.c",     "stereo_quant_pred.c",
            "LPC_fit.c",
        } ++ silk_flp),
        .flags = cflags,
    });

    if (target.result.cpu.arch.isAARCH64()) {
        mod.addIncludePath(upstream.path("silk/arm"));
        mod.addCSourceFiles(.{
            .root = upstream.path("silk/arm"),
            .files = &.{
                "arm_silk_map.c",
            },
            .flags = cflags,
        });
        if (cpu_features.neon) {
            mod.addCSourceFiles(.{
                .root = upstream.path("silk/arm"),
                .files = &.{
                    "NSQ_del_dec_neon_intr.c",
                    "LPC_inv_pred_gain_neon_intr.c",
                    "NSQ_neon.c",
                    "biquad_alt_neon_intr.c",
                },
                .flags = cflags,
            });
        }

        if (cpu_features.rtcd) {
            mod.linkLibrary(rtcdObject(b, target, &.{
                if (plc_model) |plc| plc.path(".") else upstream.path("."),
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("silk"),
                upstream.path("silk/float"),
                upstream.path("silk/arm"),
                upstream.path("celt"),
                upstream.path("."),
            }, config, "celt", .aarch64, .neon, .{
                .root = upstream.path("silk/arm"),
                .files = &.{
                    "NSQ_del_dec_neon_intr.c",
                    "LPC_inv_pred_gain_neon_intr.c",
                    "NSQ_neon.c",
                    "biquad_alt_neon_intr.c",
                },
                .flags = rtcdCFlags(.aarch64, .neon),
            }));
        }
    }
    if (target.result.cpu.arch.isX86()) {
        mod.addIncludePath(upstream.path("silk/x86"));
        mod.addCSourceFiles(.{
            .root = upstream.path("silk/x86"),
            .files = &.{
                "x86_silk_map.c",
            },
            .flags = cflags,
        });
        if (cpu_features.sse4_1) {
            mod.addCSourceFiles(.{
                .root = upstream.path("silk/x86"),
                .files = &.{
                    "VAD_sse4_1.c",
                    "NSQ_del_dec_sse4_1.c",
                    "NSQ_sse4_1.c",
                    "VQ_WMat_EC_sse4_1.c",
                },
                .flags = cflags,
            });
        }
        if (cpu_features.avx2) {
            mod.addCSourceFiles(.{
                .root = upstream.path("silk"),
                .files = &.{
                    "x86/NSQ_del_dec_avx2.c",
                    "float/x86/inner_product_FLP_avx2.c",
                },
                .flags = cflags,
            });
        }

        if (cpu_features.rtcd) {
            mod.linkLibrary(rtcdObject(b, target, &.{
                if (plc_model) |plc| plc.path(".") else upstream.path("."),
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("silk"),
                upstream.path("silk/float"),
                upstream.path("silk/x86"),
                upstream.path("celt"),
                upstream.path("."),
            }, config, "celt", .x86_64, .sse4_1, .{
                .root = upstream.path("silk/x86"),
                .files = &.{
                    "VAD_sse4_1.c",
                    "NSQ_del_dec_sse4_1.c",
                    "NSQ_sse4_1.c",
                    "VQ_WMat_EC_sse4_1.c",
                },
                .flags = rtcdCFlags(.x86_64, .sse4_1),
            }));
            mod.linkLibrary(rtcdObject(b, target, &.{
                if (plc_model) |plc| plc.path(".") else upstream.path("."),
                upstream.path("include"),
                upstream.path("dnn"),
                upstream.path("silk"),
                upstream.path("silk/float"),
                upstream.path("silk/x86"),
                upstream.path("celt"),
                upstream.path("."),
            }, config, "celt", .x86_64, .avx2, .{
                .root = upstream.path("silk"),
                .files = &.{
                    "x86/NSQ_del_dec_avx2.c",
                    "float/x86/inner_product_FLP_avx2.c",
                },
                .flags = rtcdCFlags(.x86_64, .avx2),
            }));
        }
    }
    return mod;
}

fn rtcdObject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    includes: []const std.Build.LazyPath,
    cfg: *std.Build.Step.ConfigHeader,
    comptime name: []const u8,
    comptime cpu_arch: std.Target.Cpu.Arch,
    comptime feature: @EnumLiteral(),
    add_c_source_files_options: std.Build.Module.AddCSourceFilesOptions,
) *std.Build.Step.Compile {
    const obj = b.addLibrary(.{
        .name = name ++ "_" ++ @tagName(cpu_arch) ++ "_" ++ @tagName(feature),
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = b.resolveTargetQuery(.{
                .cpu_arch = cpu_arch,
                .cpu_model = .baseline,
                .cpu_features_add = switch (cpu_arch) {
                    .x86_64 => std.Target.x86.featureSet(switch (feature) {
                        .sse => &.{.sse},
                        .sse2 => &.{.sse2},
                        .sse4_1 => &.{.sse4_1},
                        .avx2 => &.{ .avx2, .fma },
                        else => @compileError("TODO: support new feature"),
                    }),
                    .aarch64 => std.Target.aarch64.featureSet(&.{feature}),
                    .arm => std.Target.arm.featureSet(&.{feature}),
                    else => @compileError("TODO: add support for a new architecture"),
                },
                .os_tag = target.result.os.tag,
                .abi = target.result.abi,
            }),
            .link_libc = true,
            .pic = true,
        }),
    });
    for (includes) |i| obj.root_module.addIncludePath(i);
    obj.root_module.addConfigHeader(cfg);
    obj.root_module.addCSourceFiles(add_c_source_files_options);
    return obj;
}

const cflags = &[_][]const u8{
    "-DOPUS_BUILD",
    "-DHAVE_CONFIG_H",
    "-fno-sanitize=undefined",
    "-std=gnu99",
};

pub fn rtcdCFlags(
    comptime cpu_arch: std.Target.Cpu.Arch,
    comptime feature: @EnumLiteral(),
) []const []const u8 {
    return cflags ++ switch (cpu_arch) {
        .x86_64 => switch (feature) {
            .sse => &[_][]const u8{
                "-DOPUS_X86_MAY_HAVE_SSE=1",
                "-DOPUS_X86_PRESUME_SSE=1",
            },
            .sse2 => &[_][]const u8{
                "-DOPUS_X86_MAY_HAVE_SSE2=1",
                "-DOPUS_X86_PRESUME_SSE2=1",
            },
            .sse4_1 => &[_][]const u8{
                "-DOPUS_X86_MAY_HAVE_SSE4_1=1",
                "-DOPUS_X86_PRESUME_SSE4_1=1",
            },
            .avx2 => &[_][]const u8{
                "-DOPUS_X86_MAY_HAVE_AVX2=1",
                "-DOPUS_X86_PRESUME_AVX2=1",
            },
            else => @compileError("TODO add support for new CPU feature"),
        },
        .aarch64 => switch (feature) {
            .dotprod => &[_][]const u8{
                "-DOPUS_ARM_MAY_HAVE_DOTPROD=1",
                "-DOPUS_ARM_PRESUME_DOTPROD=1",
            },
            .neon => &[_][]const u8{
                "-DOPUS_ARM_MAY_HAVE_NEON=1",
                "-DOPUS_ARM_MAY_HAVE_NEON_INTR=1",
                "-DOPUS_ARM_MAY_HAVE_AARCH64_NEON_INTR=1",
                "-DOPUS_ARM_PRESUME_NEON=1",
                "-DOPUS_ARM_PRESUME_NEON_INTR=1",
                "-DOPUS_ARM_PRESUME_AARCH64_NEON_INTR=1",
            },
            else => @compileError("TODO add support for new CPU feature"),
        },
        else => @compileError("TODO implement support for new arch"),
    };
}

const silk_flp = .{
    "float/apply_sine_window_FLP.c",
    "float/corrMatrix_FLP.c",
    "float/encode_frame_FLP.c",
    "float/find_LPC_FLP.c",
    "float/find_LTP_FLP.c",
    "float/find_pitch_lags_FLP.c",
    "float/find_pred_coefs_FLP.c",
    "float/LPC_analysis_filter_FLP.c",
    "float/LTP_analysis_filter_FLP.c",
    "float/LTP_scale_ctrl_FLP.c",
    "float/noise_shape_analysis_FLP.c",
    "float/process_gains_FLP.c",
    "float/regularize_correlations_FLP.c",
    "float/residual_energy_FLP.c",
    "float/warped_autocorrelation_FLP.c",
    "float/wrappers_FLP.c",
    "float/autocorrelation_FLP.c",
    "float/burg_modified_FLP.c",
    "float/bwexpander_FLP.c",
    "float/energy_FLP.c",
    "float/inner_product_FLP.c",
    "float/k2a_FLP.c",
    "float/LPC_inv_pred_gain_FLP.c",
    "float/pitch_analysis_core_FLP.c",
    "float/scale_copy_vector_FLP.c",
    "float/scale_vector_FLP.c",
    "float/schur_FLP.c",
    "float/sort_FLP.c",
};

pub fn setupCi(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const ci = b.step("ci", "run ci");
    const configs: []const BuildFlags = &.{
        .{},
        .{ .rtcd = true },
        .{ .dred = true, .deep_plc = true, .osce = true, .osce_bwe = true },
        .{ .dred = true, .deep_plc = true, .osce = true, .osce_bwe = true, .rtcd = true },
    };

    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };

    for (configs, 0..) |c, idx| {
        const native_lib, const native_dynlib, const run_native_test = buildOpus(b, target, .Debug, c);
        ci.dependOn(&b.addInstallArtifact(native_lib, .{}).step);
        ci.dependOn(&b.addInstallArtifact(native_dynlib, .{}).step);
        run_native_test.setName(b.fmt("native-test-config #{} - {} ", .{ idx, c }));
        ci.dependOn(&run_native_test.step);

        for (targets, 0..) |q, qidx| {
            const rt = b.resolveTargetQuery(q);
            const lib, const dynlib, const run_test = buildOpus(b, rt, .Debug, c);
            ci.dependOn(&b.addInstallArtifact(lib, .{}).step);
            ci.dependOn(&b.addInstallArtifact(dynlib, .{}).step);
            run_test.setName(b.fmt("test-config #{} - target # {} ", .{ idx, qidx }));
            run_test.failing_to_execute_foreign_is_an_error = false;
            run_test.skip_foreign_checks = true;
            ci.dependOn(&run_test.step);
        }
    }
}
