const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xiph_opus = b.dependency("xiph_opus", .{});

    const config = b.addConfigHeader(.{}, .{
        .HAVE_LRINTF = {},
        .HAVE_LRINT = {},
        .HAVE_STDINT_H = {},
        .VAR_ARRAYS = true,
        .USE_ALLOCA = null,
        .FIXED_POINT = b.option(bool, "fixed-point", "use fixed point instead of floats"),
        .ENABLE_ASSERTIONS = b.option(bool, "assertions", "Enable assertions"),
        .ENABLE_DRED = b.option(bool, "dred", "Enable DRED"),
    });

    const celt = buildCelt(b, target, optimize, xiph_opus, config);
    const silk = buildSilk(b, target, optimize, xiph_opus, config);

    const lib = b.addStaticLibrary(.{
        .name = "opus",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibrary(celt);
    lib.linkLibrary(silk);

    lib.addConfigHeader(config);
    // lib.linkLibC();
    lib.installHeadersDirectory(xiph_opus.path("include"), ".", .{});
    // lib.installHeader(xiph_opus.path("include/opus.h"), "opus.h");
    lib.addIncludePath(xiph_opus.path("include"));
    lib.addIncludePath(xiph_opus.path("src"));
    lib.addIncludePath(xiph_opus.path("celt"));
    lib.addIncludePath(xiph_opus.path("silk"));
    lib.addIncludePath(xiph_opus.path("dnn"));
    lib.addCSourceFiles(.{
        .root = xiph_opus.path("src/"),
        .files = &.{
            "analysis.c",
            // "analysis.h",
            "extensions.c",
            "mapping_matrix.c",
            // "mapping_matrix.h",
            "mlp.c",
            // "mlp.h",
            "mlp_data.c",
            "opus.c",
            "opus_compare.c",
            "opus_decoder.c",
            // "opus_demo.c",
            "opus_encoder.c",
            "opus_multistream.c",
            "opus_multistream_decoder.c",
            "opus_multistream_encoder.c",
            // "opus_private.h",
            "opus_projection_decoder.c",
            "opus_projection_encoder.c",
            "repacketizer.c",
            // "repacketizer_demo.c",
            // "tansig_table.h",
        },
        .flags = &.{
            "-DOPUS_BUILD",
            "-DHAVE_CONFIG_H",
            "-std=gnu99",
            "-fno-sanitize=undefined",
        },
    });

    b.installArtifact(lib);

    const test_opus_api = b.addExecutable(.{
        .name = "test_opus_api",
        .target = target,
        .optimize = optimize,
    });

    test_opus_api.linkLibrary(lib);
    test_opus_api.addCSourceFile(.{
        .file = xiph_opus.path("tests/test_opus_api.c"),
        .flags = &.{
            "-fno-sanitize=undefined",
        },
    });
    test_opus_api.root_module.addIncludePath(xiph_opus.path("celt"));

    const run_test = b.addRunArtifact(test_opus_api);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}

fn buildCelt(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    xiph_opus: *std.Build.Dependency,
    config: *std.Build.Step.ConfigHeader,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "celt",
        .target = target,
        .optimize = optimize,
    });

    lib.addConfigHeader(config);
    lib.addIncludePath(xiph_opus.path("include"));
    lib.addCSourceFiles(.{
        .root = xiph_opus.path("celt"),
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
        .flags = &.{
            "-DOPUS_BUILD",
            "-DHAVE_CONFIG_H",
            "-std=gnu99",
            "-fno-sanitize=undefined",
        },
    });

    // "x86/x86cpu.c ",
    // "x86/x86_celt_map.",
    // "x86/pitch_sse.",
    // "x86/pitch_sse2.c ",
    // "x86/vq_sse2.",
    // "x86/celt_lpc_sse4_1.c ",
    // "x86/pitch_sse4_1.",
    // "x86/pitch_avx.c",
    // "arm/armcpu.c",
    // "arm/arm_celt_map.",
    // "arm/celt_pitch_xcorr_arm.s",
    // "arm/armopts.s.in",

    // "arm/celt_neon_intr.c ",
    // "arm/pitch_neon_intr.c",
    // "arm/celt_fft_ne10.c ",
    // "arm/celt_mdct_ne10.c",
    return lib;
}

fn buildSilk(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    xiph_opus: *std.Build.Dependency,
    config: *std.Build.Step.ConfigHeader,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "silk",
        .target = target,
        .optimize = optimize,
    });

    lib.addConfigHeader(config);
    lib.addIncludePath(xiph_opus.path("include"));
    lib.addIncludePath(xiph_opus.path("silk"));
    lib.addIncludePath(xiph_opus.path("silk/float"));
    lib.addIncludePath(xiph_opus.path("celt"));
    lib.addCSourceFiles(.{
        .root = xiph_opus.path("silk"),
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
        .flags = &.{
            "-DOPUS_BUILD",
            "-DHAVE_CONFIG_H",
            "-fno-sanitize=undefined",
            "-std=gnu99",
        },
    });

    return lib;
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
